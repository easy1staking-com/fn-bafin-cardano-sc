use aiken/collection/dict.{size}
use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, Transaction,
}
use types/global_state.{GlobalState}
use types/power_users.{PowerUser}
use types/transfer_manager.{
  TransferManagerMintRedeemer, TransferManagerWithdrawRedeemer,
} as tm
use types/user_states.{UserState}
use utils.{must_be_signed_by_credential}

validator transfer_manager(
  smart_tokens_spend_script_hash: ByteArray,
  global_state_nft_policy_id: ByteArray,
  global_state_nft_asset_name: ByteArray,
  user_state_linked_list_policy_id: ByteArray,
  security_asset_name: ByteArray,
) {
  mint(
    redeemer: TransferManagerMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let minted_amount = quantity_of(self.mint, policy_id, security_asset_name)
    expect Some(global_state_input) =
      list.at(self.reference_inputs, redeemer.global_state_input_index)
    expect InlineDatum(global_state_datum) = global_state_input.output.datum
    expect GlobalState { power_user_linked_list_policy_id, .. } =
      global_state_datum
    expect Some(issuer_node_ref_input) =
      list.at(self.reference_inputs, redeemer.issuer_node_ref_input_index)
    expect InlineDatum(issuer_node_datum) = issuer_node_ref_input.output.datum
    expect parsed_issuer_node_datum: NodeDatum = issuer_node_datum
    expect Key(power_user_credential_hash) = parsed_issuer_node_datum.key
    expect power_user_data: PowerUser = parsed_issuer_node_datum.data
    expect Some(prev_issuer_node_ref_input) =
      list.at(self.reference_inputs, redeemer.prev_issuer_node_ref_input_index)
    and {
      //Only 1 token AssetName minted
      size(tokens(self.mint, policy_id)) == 1,
      //Must mint the correct amount
      minted_amount == redeemer.minted_amount,
      //Global State input must have the correct NFT
      quantity_of(
        global_state_input.output.value,
        global_state_nft_policy_id,
        global_state_nft_asset_name,
      ) > 0,
      //The node must belong to the PowerUser list
      ordered.prove_is_member(
        power_user_linked_list_policy_id,
        parsed_issuer_node_datum.key,
        prev_issuer_node_ref_input.output,
      ),
      //Must be signed by the power user
      must_be_signed_by_credential(self, power_user_credential_hash),
      if minted_amount > 0 {
        expect Some(smart_tokens_spend_script_output) =
          list.at(self.outputs, redeemer.smart_tokens_spend_script_output_index)
        and {
          //Must be a minter
          power_user_data.is_minter,
          //Goes to the smart tokens spend script
          smart_tokens_spend_script_output.address.payment_credential == Script(
            smart_tokens_spend_script_hash,
          ),
          //No datum
          smart_tokens_spend_script_output.datum == NoDatum,
          //In output exactly how much you have minted
          quantity_of(
            smart_tokens_spend_script_output.value,
            policy_id,
            security_asset_name,
          ) == minted_amount,
          //Only ADA and this token
          length(flatten(smart_tokens_spend_script_output.value)) <= 2,
        }
      } else {
        //Must be a burner
        power_user_data.is_burner
      },
    }
  }

  withdraw(
    redeemer: TransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    expect Script(security_policy_id) = credential

    expect Some(global_state_ref_input) =
      list.at(self.reference_inputs, redeemer.global_state_ref_input_index)
    expect InlineDatum(global_state_datum) = global_state_ref_input.output.datum
    expect GlobalState { transfers_paused, .. } = global_state_datum

    let global_status_ok = and {
        //Global State must have the correct NFT
        quantity_of(
          global_state_ref_input.output.value,
          global_state_nft_policy_id,
          global_state_nft_asset_name,
        ) > 0,
        //Overall transfers of this token must NOT be paused
        transfers_paused == False,
      }

    //Collect unique input stake_cred that must be verified
    let inputs_user_stake_cred =
      list.unique(
        list.foldr(
          self.inputs,
          [],
          fn(input, result) {
            if quantity_of(
              input.output.value,
              security_policy_id,
              security_asset_name,
            ) > 0 {
              expect Some(Inline(stake_cred)) =
                input.output.address.stake_credential
              list.push(result, stake_cred)
            } else {
              result
            }
          },
        ),
      )

    let outputs_with_token =
      list.filter(
        self.outputs,
        fn(output) {
          quantity_of(output.value, security_policy_id, security_asset_name) > 0
        },
      )

    //As we loop through the inputs we DO NOT need to ensure that the number of actions is equal to the number of inputs
    let all_token_inputs_can_be_spent =
      list.indexed_foldr(
        inputs_user_stake_cred,
        True,
        fn(index, stake_cred, result) {
          //As all inputs must return True, if any of previous input returned False, then fail
          //The last input is not checked but will return its value at the end, so if False withdraw will fail
          expect result
          let input_credential_hash =
            when stake_cred is {
              VerificationKey(hash) -> hash
              Script(hash) -> hash
            }

          expect Some(action) = list.at(redeemer.actionsForEachInput, index)

          expect Some(user_node_ref_input) =
            list.at(self.reference_inputs, action.user_node_ref_input_index)
          expect InlineDatum(user_node_datum) = user_node_ref_input.output.datum
          expect parsed_user_node_datum: NodeDatum = user_node_datum
          expect user_state: UserState = parsed_user_node_datum.data
          expect Some(prev_user_node_ref_input) =
            list.at(
              self.reference_inputs,
              action.prev_user_node_ref_input_index,
            )

          and {
            //The node must belong to the user state list
            ordered.prove_is_member(
              user_state_linked_list_policy_id,
              parsed_user_node_datum.key,
              prev_user_node_ref_input.output,
            ),
            parsed_user_node_datum.key == Key { key: input_credential_hash },
            //Must be signed by the user owning this utxo
            must_be_signed_by_credential(self, input_credential_hash),
            //User has done KYC properly
            user_state.is_kyced == True,
            //User is not blacklisted
            user_state.is_blacklisted == False,
          }
        },
      )

    let all_token_outputs_are_correct =
      list.foldr(
        outputs_with_token,
        True,
        fn(output, result) {
          //As all outputs must return True, if any of previous input returned False, then fail
          //The last output is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          and {
            //Stays in the smart tokens spend script
            output.address.payment_credential == Script(
              smart_tokens_spend_script_hash,
            ),
            //Datum must not be of type hash to avoid generating a too big tx
            when output.datum is {
              DatumHash(_hash) -> False
              _ -> True
            },
            //DOS protection
            length(flatten(output.value)) <= 21,
          }
        },
      )

    and {
      global_status_ok,
      all_token_inputs_can_be_spent,
      all_token_outputs_are_correct,
    }
  }

  else(_) {
    fail
  }
}
