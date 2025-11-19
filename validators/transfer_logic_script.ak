use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, quantity_of}
use cardano/transaction.{DatumHash, InlineDatum, Input, Output, Transaction}
use constants
use types/global_state.{GlobalStateDatum}
use types/transfer_logic_script.{TransferLogicScriptWithdrawRedeemer}
use types/users.{User}
use utils.{must_be_signed_by_credential}

validator transfer_logic_validator(
  global_state_policy_id: ByteArray,
  users_linked_list_policy_id: ByteArray,
  issuance_policy_id: PolicyId,
) {
  withdraw(
    redeemer: TransferLogicScriptWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
    expect Some(global_state_ref_input) =
      list.at(self.reference_inputs, redeemer.global_state_ref_input_index)
    expect InlineDatum(global_state_datum) = global_state_ref_input.output.datum
    //TODO This can be more efficient with builtins
    expect GlobalStateDatum { transfers_paused, .. } = global_state_datum

    let global_state_ok = and {
        //Global State must have the correct NFT
        quantity_of(
          global_state_ref_input.output.value,
          global_state_policy_id,
          constants.global_state_asset_name,
        ) > 0,
        //General transfers of this token must NOT be paused
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
              issuance_policy_id,
              constants.security_asset_name,
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
          quantity_of(
            output.value,
            issuance_policy_id,
            constants.security_asset_name,
          ) > 0
        },
      )

    //As we loop through the inputs we DO NOT need to ensure that the number of actions is equal 
    //to the number of inputs (additional actions can be simply ignored)
    let all_token_inputs_can_be_spent =
      list.indexed_foldr(
        inputs_user_stake_cred,
        True,
        fn(index, stake_cred, result) {
          //As all inputs must return True, if any of previous input returned False, then fail
          //The last input is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          //TODO Is it safe to ignore the type of stake_cred and consider only its hash?
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
          expect user_state: User = parsed_user_node_datum.data
          expect Some(prev_user_node_ref_input) =
            list.at(
              self.reference_inputs,
              action.prev_user_node_ref_input_index,
            )

          and {
            //The node must belong to the user state list
            ordered.prove_is_member(
              users_linked_list_policy_id,
              parsed_user_node_datum.key,
              prev_user_node_ref_input.output,
            ),
            //Node must have the user credential hash
            parsed_user_node_datum.key == Key { key: input_credential_hash },
            //Tx must be signed by the user owning this utxo
            must_be_signed_by_credential(self, input_credential_hash),
            //User has done KYC properly
            user_state.is_kyced == True,
            //User is not blacklisted
            user_state.is_blacklisted == False,
          }
        },
      )

    //TODO Is this necessary? programmable_logic_base already checks the address
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
              constants.programmable_logic_base_script_hash,
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
      global_state_ok,
      all_token_inputs_can_be_spent,
      all_token_outputs_are_correct,
    }
  }

  else(_) {
    fail
  }
}
