use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
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

          let destination_user_anchor_node_ref_input =
            utils.safe_list_at(
              self.reference_inputs,
              utils.safe_list_at(
                redeemer.destination_user_anchor_node_ref_input_indexes,
                index,
              ),
            )

          expect InlineDatum(destination_user_datum) =
            destination_user_node_ref_input.output.datum
          expect parsed_destination_user_datum: NodeDatum =
            destination_user_datum
          expect destination_user_data: User =
            parsed_destination_user_datum.data

          and {
            //The node must belong to the users registry
            ordered.prove_is_member(
              users_linked_list_policy_id,
              parsed_destination_user_datum.key,
              destination_user_anchor_node_ref_input.output,
            ),
            //The key of the destination user must match the output credential hash
            parsed_destination_user_datum.key == Key(
              output_stake_credential_hash,
            ),
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
    expect InlineDatum(power_user_user_datum) =
      power_user_ref_input.output.datum
    expect parsed_power_user_user_datum: NodeDatum = power_user_user_datum
    expect power_user_data: PowerUser = parsed_power_user_user_datum.data
    expect Key { key: power_user_node_key } = parsed_power_user_user_datum.key
    let power_user_anchor_node_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.power_user_anchor_node_ref_input_index,
      )
    and {
      all_token_outputs_are_correct,
      //The node must belong to the power users registry
      ordered.prove_is_member(
        power_users_linked_list_policy_id,
        parsed_power_user_user_datum.key,
        power_user_anchor_node_ref_input.output,
      ),
      power_user_data.can_force_transfer,
      must_be_signed_by_credential(self, power_user_node_key),
    }
  }

  else(_) {
    fail
  }
}
