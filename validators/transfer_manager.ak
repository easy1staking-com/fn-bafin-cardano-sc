use aiken/collection/list.{foldl, length}
use cardano/address.{Address, Credential, Inline, Script, StakeCredential}
use cardano/assets.{AssetName, PolicyId, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use common.{is_user_allowed}
use types/datum.{LockedTransferDatum, StateManagerDatum, TransferManagerDatum}
use types/redeemer.{
  LockTokens, Transfer, TransferManagerMintRedeemer,
  TransferManagerSpendRedeemer, TransferManagerWithdrawRedeemer, TransferOutput,
}
use utils.{
  all_sc_inputs_from_same_user, get_inputs_from_sc, get_own_hash,
  is_output_to_sc, must_be_signed_by_stake_credential,
}

validator transfer_manager(
  smartTokenSpendScriptHash: ByteArray,
  locked_manager_script_hash: ByteArray,
  issuerManagerHash: PolicyId,
  issuerAssetName: AssetName,
  adminManagerHash: PolicyId,
  adminAssetName: AssetName,
) {
  mint(
    redeemer: TransferManagerMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let securityAssetName = adminAssetName
    expect Some(issuerRefInput) =
      list.at(self.reference_inputs, redeemer.issuerTokenRefInputIndex)
    expect Some(transferManagerOutput) =
      list.at(self.outputs, redeemer.transferManagerOutputIndex)
    and {
      //TODO SHOULDN'T WE REDUCE remainingSecurityTokens and check that it's possible to do that?
      //We don't check the datum because we don't use it but it exists to be CIP-113 compliant
      //TODO FIX AUTH PROCESS WITH LATEST 
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerManagerHash,
        issuerAssetName,
      ),
      //No burning, only minting
      redeemer.transferAmount > 0,
      //Must mint the correct amount
      quantity_of(self.mint, policy_id, securityAssetName) == redeemer.transferAmount,
      //In output exactly how much you have minted
      quantity_of(transferManagerOutput.value, policy_id, securityAssetName) == redeemer.transferAmount,
      //Must always go to the smart token spend validator
      is_output_to_sc(transferManagerOutput, smartTokenSpendScriptHash),
      //Only ADA and this token
      length(flatten(transferManagerOutput.value)) <= 2,
    }
  }

  withdraw(
    redeemer: TransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    let securityAssetName = adminAssetName
    expect Script(security_policy_id) = credential

    //TODO we can probably make this part more efficient
    let inputs_with_token =
      list.filter(
        self.inputs,
        fn(input) {
          quantity_of(input.output.value, security_policy_id, securityAssetName) > 0
        },
      )

    let outputs_with_token =
      list.filter(
        self.outputs,
        fn(output) {
          quantity_of(output.value, security_policy_id, securityAssetName) > 0
        },
      )

    let all_token_inputs_can_be_spent =
      list.indexed_foldr(
        inputs_with_token,
        True,
        fn(index, input, result) {
          //As all inputs must return True, if any of previous input returned False, then fail
          //The last input is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          //If input is coming from the locked manager that only admin can unlock
          if input.output.address.stake_credential == Some(
            Inline(Script(locked_manager_script_hash)),
          ) {
            and {
              //The admin node must belong to the user state ordered list
              ordered.is_member(
                admin_node,
                redeemer.admin_key,
                node_address,
                admin_linked_list_address,
              ),
              //Must be signed by this admin
              must_be_signed_by_credential(
                self,
                admin_node.data.adminCredential,
              ),
            }
          } else {
            and {
              //Overall transfers of this tokens must NOT be paused
              smart_token_node.transfers_paused == False,
              //Must be signed by the user owning this utxo
              must_be_signed_by_credential(
                self,
                input.output.address.stake_credential,
              ),
              //The user node must belong to the user state ordered list
              ordered.is_member(
                user_state_node,
                redeemer.user_key,
                node_address,
                user_state_linked_list_address,
              ),
              //User has done KYC properly
              user_state_node.data.whitelisted == True,
              //User is not blacklisted
              user_state_node.data.blacklisted == False,
            }
          }
        },
      )

    let all_token_outputs_go_to_smart_tokens_spend_script =
      list.indexed_foldr(
        outputs_with_token,
        True,
        fn(index, output, result) {
          //As all outputs must return True, if any of previous input returned False, then fail
          //The last output is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          and {
            //Stays in the smart tokens spend script
            output.address.payment_credential == Script(
              smartTokensSpendScriptHash,
            ),
            //DOS protection
            length(flatten(output.value)) <= 21,
          }
        },
      )

    and {
      all_token_inputs_can_be_spent,
      all_token_outputs_go_to_smart_tokens_spend_script,
    }
  }

  else(_) {
    fail
  }
}
