use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{NodeDatum}
use cardano/address.{Credential}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use types/locked_tokens.{LockedTokensWithdrawRedeemer}
use types/power_user.{PowerUser}
use utils.{must_be_signed_by_credential}

validator locked_tokens_withdraw(
  power_user_linked_list_script_hash: ByteArray,
) {
  withdraw(
    redeemer: LockedTokensWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
    expect Some(admin_node_ref_input) =
      list.at(self.reference_inputs, redeemer.admin_node_ref_input_index)
    expect InlineDatum(admin_node_datum) = admin_node_ref_input.output.datum
    expect parsed_admin_node_datum: NodeDatum = admin_node_datum
    expect power_user_data: PowerUser = parsed_admin_node_datum.data
    expect Some(prev_admin_node_ref_input) =
      list.at(self.reference_inputs, redeemer.prev_admin_node_ref_input_index)
    and {
      //The node must belong to the admin list
      ordered.prove_is_member(
        power_user_linked_list_script_hash,
        parsed_admin_node_datum.key,
        prev_admin_node_ref_input.output,
      ),
      //Must be a admin
      power_user_data.is_admin,
      //Must be signed by this admin
      must_be_signed_by_credential(self, power_user_data.credential),
    }
  }

  else(_) {
    fail
  }
}
