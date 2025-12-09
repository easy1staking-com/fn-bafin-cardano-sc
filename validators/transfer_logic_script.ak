use aiken/builtin
use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use constants
use types/transfer_logic_script.{TransferLogicScriptWithdrawRedeemer}
use types/users.{User}
use utils

validator transfer_logic_validator(
  security_asset_name: ByteArray,
  global_state_policy_id: ByteArray,
  users_linked_list_policy_id: ByteArray,
  issuance_policy_id: PolicyId,
) {
  withdraw(
    redeemer: TransferLogicScriptWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
    let global_state_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.global_state_ref_input_index,
      )
    expect InlineDatum(global_state_datum) = global_state_ref_input.output.datum
    //Efficient retrieval of the transfers_paused field
    let transfers_paused =
      builtin.unconstr_index(builtin.unconstr_fields(global_state_datum)) == 1

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
    let inputs_user_stake_cred_hash =
      list.unique(
        list.foldr(
          self.inputs,
          [],
          fn(input, result) {
            if quantity_of(
              input.output.value,
              issuance_policy_id,
              security_asset_name,
            ) > 0 {
              expect Some(Inline(stake_cred)) =
                input.output.address.stake_credential
              let credential_hash =
                when stake_cred is {
                  VerificationKey(hash) -> hash
                  Script(hash) -> hash
                }
              list.push(result, credential_hash)
            } else {
              result
            }
          },
        ),
      )

    //As we loop through the inputs we DO NOT need to ensure that the number of actions is equal 
    //to the number of inputs (additional actions can be simply ignored)
    let all_token_inputs_can_be_spent =
      list.indexed_foldr(
        inputs_user_stake_cred_hash,
        True,
        fn(index, input_stake_cred_hash, result) {
          //As all inputs must return True, if any of previous input returned False, then fail
          //The last input is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          let action =
            utils.safe_list_at(redeemer.actions_for_each_input, index)

          let user_node_ref_input =
            utils.safe_list_at(
              self.reference_inputs,
              action.user_node_ref_input_index,
            )
          expect InlineDatum(user_node_datum) = user_node_ref_input.output.datum
          expect parsed_user_node_datum: NodeDatum = user_node_datum
          expect user_state: User = parsed_user_node_datum.data
          let prev_user_node_ref_input =
            utils.safe_list_at(
              self.reference_inputs,
              action.user_anchor_node_ref_input_index,
            )

          and {
            //The node must belong to the user state list
            ordered.prove_is_member(
              users_linked_list_policy_id,
              parsed_user_node_datum.key,
              prev_user_node_ref_input.output,
            ),
            //Node must have the user credential hash
            parsed_user_node_datum.key == Key { key: input_stake_cred_hash },
            //Tx must be signed by the user owning this utxo
            //Already done by CIP113 programmable_logic_global
            //User has been verified
            user_state.is_verified == True,
            //User is not blacklisted
            user_state.is_blacklisted == False,
          }
        },
      )

    and {
      //Outputs are already checked by programmable_logic_base
      all_token_inputs_can_be_spent,
      global_state_ok,
    }
  }

  else(_) {
    fail
  }
}
