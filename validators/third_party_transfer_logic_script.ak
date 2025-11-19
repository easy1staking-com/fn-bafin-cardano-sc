use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{NodeDatum}
use cardano/address.{Credential}
use cardano/assets.{PolicyId, flatten, quantity_of}
use cardano/transaction.{DatumHash, InlineDatum, Input, Output, Transaction}
use constants
use types/power_users.{PowerUser}
use types/third_party_transfer_logic_script.{
  ThirdPartyTransferLogicScriptWithdrawRedeemer,
}
use types/users.{User}
use utils.{must_be_signed_by_credential}

validator third_party_transfer_logic_validator(
  issuance_policy_id: PolicyId,
  users_linked_list_policy_id: ByteArray,
) {
  withdraw(
    redeemer: ThirdPartyTransferLogicScriptWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
    //Any input can be spent
    //Any output with this token must go to a KYCed and non-blacklisted address
    //programmable_logic_base already check the correct destination payment credentials
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

    let all_token_outputs_are_correct =
      list.indexed_foldr(
        outputs_with_token,
        True,
        fn(index, output, result) {
          //As all outputs must return True, if any of previous input returned False, then fail
          //The last output is not checked but will return its value at the end, so if False withdraw will fail
          expect result

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
            //The node must belong to the power users registry
            ordered.prove_is_member(
              users_linked_list_policy_id,
              parsed_destination_user_datum.key,
              destination_user_anchor_node_ref_input.output,
            ),
            destination_user_data.is_kyced,
            destination_user_data.is_blacklisted == False,
            //TODO Are these 2 checks necessary? CIP113 base script should already check them
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

    //Power user must have the can_force_transfer right
    expect Some(power_user_ref_input) =
      list.at(self.reference_inputs, redeemer.power_user_node_ref_input_index)
    expect InlineDatum(power_user_user_datum) =
      power_user_ref_input.output.datum
    expect parsed_power_user_user_datum: NodeDatum = power_user_user_datum
    expect power_user_data: PowerUser = parsed_power_user_user_datum.data
    and {
      all_token_outputs_are_correct,
      power_user_data.can_force_transfer,
      must_be_signed_by_credential(self, power_user_data.credential_hash),
    }
  }

  else(_) {
    fail
  }
}
