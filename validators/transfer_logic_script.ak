use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use constants
use types/global_state
use types/transfer_logic_script.{TransferLogicScriptWithdrawRedeemer}
use types/users.{User}
use utils

// issuance_logic_script_hash

validator transfer_logic_validator(
  // we don't need this if the asset name is always ONE and it's a parameters of the minting script, which will lead to the policy id itself changing.
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
    // Resolve the GS reference input. `is_paused` (in types/global_state)
    // asserts the NFT is present and returns the `transfers_paused` flag via
    // UPLC builtins (no full-datum deserialisation).
    let gs_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.global_state_ref_input_index,
      )
    let transfers_paused =
      global_state.is_paused(gs_input, global_state_policy_id)

    //Collect unique input stake_cred that must be verified
    let inputs_user_stake_cred_hash =
      // ah there it is the dedup, is it costly?
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

          let (user_node_key, user_state) =
            get_element_info(
              user_node_ref_input.output,
              fn(_lovelace, node_key, data, _link) {
                expect Some(key) = node_key
                expect user_state: User = data
                (key, user_state)
              },
            )
              |> run_element_with(
                  users_linked_list_policy_id,
                  constants.linked_list_root_key,
                  constants.linked_list_node_key_prefix,
                  constants.linked_list_node_key_prefix_length,
                )

          and {
            //Node must have the user credential hash
            user_node_key == input_stake_cred_hash,
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
      //General transfers of this token must NOT be paused
      transfers_paused == False,
    }
  }

  // Whitelist RegisterCredential only — see minting_logic_script for rationale.
  // A rubber-stamp publish would let anyone de-register this script's stake
  // credential via UnregisterCredential, bricking every transfer until
  // re-registered (and paying the attacker the 2 ADA deposit refund).
  publish(_r: Data, c: Certificate, _s: Transaction) {
    when c is {
      RegisterCredential { .. } -> True
      _ -> False
    }
  }

  else(_) {
    fail
  }
}

