use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{Transaction}
use constants
use types/power_users.{PowerUser}
use types/third_party_transfer_logic_script.{
  ThirdPartyTransferLogicScriptWithdrawRedeemer,
}
use types/users.{User}
use utils.{must_be_signed_by_credential}

validator third_party_transfer_logic_validator(
  security_asset_name: ByteArray,
  power_users_linked_list_policy_id: ByteArray,
  users_linked_list_policy_id: ByteArray,
  issuance_policy_id: PolicyId,
) {
  withdraw(
    redeemer: ThirdPartyTransferLogicScriptWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
    //Any input can be spent
    //Any output with this token must go to a verified and non-blacklisted address
    //programmable_logic_base already check the correct destination payment credentials
    let outputs_with_token =
      list.filter(
        self.outputs,
        fn(output) {
          quantity_of(output.value, issuance_policy_id, security_asset_name) > 0
        },
      )

    let all_token_outputs_are_correct =
      list.indexed_foldr(
        outputs_with_token,
        True,
        fn(index, output, result) {
          //As all outputs must return True, if any of previous input returned False, then fail
          //The last output is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          expect Some(Inline(stake_cred)) = output.address.stake_credential
          let output_stake_credential_hash =
            when stake_cred is {
              VerificationKey(hash) -> hash
              Script(hash) -> hash
            }

          let destination_user_node_ref_input =
            utils.safe_list_at(
              self.reference_inputs,
              utils.safe_list_at(
                redeemer.destination_user_node_ref_input_indexes,
                index,
              ),
            )

          let (destination_user_key, destination_user_data) =
            get_element_info(
              destination_user_node_ref_input.output,
              fn(_lovelace, node_key, data, _link) {
                expect Some(key) = node_key
                expect user_data: User = data
                (key, user_data)
              },
            )
              |> run_element_with(
                  users_linked_list_policy_id,
                  constants.linked_list_root_key,
                  constants.linked_list_node_key_prefix,
                  constants.linked_list_node_key_prefix_length,
                )

          and {
            //The key of the destination user must match the output credential hash
            destination_user_key == output_stake_credential_hash,
            destination_user_data.is_verified,
            destination_user_data.is_blacklisted == False,
          }
        },
      )

    //Power user must have the can_force_transfer right
    let power_user_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.power_user_node_ref_input_index,
      )

    let (power_user_node_key, power_user_data) =
      get_element_info(
        power_user_ref_input.output,
        fn(_lovelace, node_key, data, _link) {
          expect Some(key) = node_key
          expect power_user_data: PowerUser = data
          (key, power_user_data)
        },
      )
        |> run_element_with(
            power_users_linked_list_policy_id,
            constants.linked_list_root_key,
            constants.linked_list_node_key_prefix,
            constants.linked_list_node_key_prefix_length,
          )

    and {
      all_token_outputs_are_correct,
      power_user_data.can_force_transfer,
      must_be_signed_by_credential(self, power_user_node_key),
    }
  }

  else(_) {
    fail
  }
}
