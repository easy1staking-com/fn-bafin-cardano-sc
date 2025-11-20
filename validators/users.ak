use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{
  Key, NodeDatum, get_node_inputs, get_node_outputs,
}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types/power_users.{PowerUser}
use types/users.{
  AddUser, Deinit, Init, MintRedeemer, ModifyUser, RemoveUser, SpendRedeemer,
  StateTransition, User,
}
use utils.{must_be_signed_by_credential}

validator users_validator(
  power_users_linked_list_policy_id: ByteArray,
  users_linked_list_policy_id: ByteArray,
) {
  spend(
    datum_opt: Option<User>,
    redeemer: SpendRedeemer,
    input_out_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datum_opt
    when redeemer is {
      StateTransition ->
        //Delegating responsibility to the mint validator
        ordered.list_state_transition(
          tokens(self.mint, users_linked_list_policy_id),
        )
      ModifyUser {
        own_output_index,
        node_nft_asset_name,
        state_to_change_index,
        state_field_value,
        power_user_node_ref_input_index,
        power_user_anchor_node_ref_input_index,
      } -> {
        expect Some(own_input) =
          list.find(
            self.inputs,
            fn(input) { input.output_reference == input_out_ref },
          )
        let node_mint = tokens(self.mint, users_linked_list_policy_id)
        let own_output = utils.safe_list_at(self.outputs, own_output_index)
        expect InlineDatum(output_datum) = own_output.datum
        expect parsed_output_datum: NodeDatum = output_datum
        expect output_user_status: User = parsed_output_datum.data
        let power_user_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_node_ref_input_index,
          )
        expect InlineDatum(power_user_user_datum) =
          power_user_ref_input.output.datum
        expect parsed_power_user_user_datum: NodeDatum = power_user_user_datum
        expect power_user_data: PowerUser = parsed_power_user_user_datum.data
        expect Key { key: power_user_node_key } =
          parsed_power_user_user_datum.key
        let power_user_anchor_node_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_anchor_node_ref_input_index,
          )
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_linked_list_policy_id,
            parsed_power_user_user_datum.key,
            power_user_anchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_user_node_key),
          //Check which field of the status we are changing
          if state_to_change_index == 0 {
            let expected_datum =
              User {
                is_verified: state_field_value,
                is_blacklisted: input_datum.is_blacklisted,
              }
            and {
              //Must have permission
              power_user_data.can_verify,
              output_user_status == expected_datum,
            }
          } else {
            let expected_datum =
              User {
                is_verified: input_datum.is_verified,
                is_blacklisted: state_field_value,
              }
            and {
              //Must have permission
              power_user_data.can_blacklist,
              output_user_status == expected_datum,
            }
          },
          //Ensure you're only modifying data
          ordered.modify_data(
            node_mint,
            own_input.output,
            own_output,
            users_linked_list_policy_id,
            node_nft_asset_name,
          ),
        }
      }
    }
  }

  else(_) {
    fail
  }
}

validator mint(
  init_input_out_ref: OutputReference,
  power_users_linked_list_policy_id: ByteArray,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, self: Transaction) {
    let node_in_outputs = get_node_inputs(self.inputs, policy_id)
    let node_outputs = get_node_outputs(self.outputs, policy_id)
    let node_mint = tokens(self.mint, policy_id)
    when redeemer is {
      Init -> and {
          //The init input must be spent
          list.any(
            self.inputs,
            fn(input) { input.output_reference == init_input_out_ref },
          ),
          ordered.init(node_outputs, node_mint, policy_id),
        }
      Deinit -> ordered.deinit(node_in_outputs, node_mint, policy_id)
      AddUser {
        new_user_key,
        appended_node_output_index,
        anchor_node_output_index,
        power_user_node_ref_input_index,
        power_user_anchor_node_ref_input_index,
      } -> {
        let power_user_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_node_ref_input_index,
          )
        expect InlineDatum(power_user_user_datum) =
          power_user_ref_input.output.datum
        expect parsed_power_user_user_datum: NodeDatum = power_user_user_datum
        expect power_user_data: PowerUser = parsed_power_user_user_datum.data
        expect Key { key: power_user_node_key } =
          parsed_power_user_user_datum.key
        let power_user_anchor_node_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_anchor_node_ref_input_index,
          )
        let inserted_node_output =
          utils.safe_list_at(self.outputs, appended_node_output_index)
        expect InlineDatum(users_status_datum) = inserted_node_output.datum
        expect parsed_users_status_datum: NodeDatum = users_status_datum
        //Datum must be of correct type
        expect parsed_users_status_data: User = parsed_users_status_datum.data
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_linked_list_policy_id,
            parsed_power_user_user_datum.key,
            power_user_anchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_user_node_key),
          //User datum can be set depending on power user role
          or {
            and {
              power_user_data.is_admin,
              parsed_users_status_data == User {
                is_verified: False,
                is_blacklisted: False,
              },
            },
            and {
              power_user_data.can_verify,
              parsed_users_status_data.is_blacklisted == False,
            },
            and {
              power_user_data.can_blacklist,
              parsed_users_status_data.is_verified == False,
            },
          },
          //User must be added into the user status list
          ordered.insert(
            Key(new_user_key),
            appended_node_output_index,
            anchor_node_output_index,
            node_in_outputs,
            node_outputs,
            node_mint,
          ),
        }
      }
      RemoveUser {
        user_key_to_remove,
        removed_node_input_index,
        anchor_node_input_index,
        admin_node_ref_input_index,
        admin_anchor_node_ref_input_index,
      } -> {
        let admin_ref_input =
          utils.safe_list_at(self.reference_inputs, admin_node_ref_input_index)
        expect InlineDatum(admin_datum) = admin_ref_input.output.datum
        expect parsed_admin_datum: NodeDatum = admin_datum
        expect admin_data: PowerUser = parsed_admin_datum.data
        expect Key { key: admin_node_key } = parsed_admin_datum.key
        let admin_anchor_node_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            admin_anchor_node_ref_input_index,
          )
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_linked_list_policy_id,
            parsed_admin_datum.key,
            admin_anchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, admin_node_key),
          //Must be a admin
          admin_data.is_admin,
          //User must be added into the user status list
          ordered.remove(
            Key(user_key_to_remove),
            removed_node_input_index,
            anchor_node_input_index,
            node_in_outputs,
            node_outputs,
            node_mint,
          ),
        }
      }
    }
  }

  else(_) {
    fail
  }
}
