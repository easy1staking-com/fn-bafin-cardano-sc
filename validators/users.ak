use aiken/collection/dict
use aiken/collection/list
use aiken_design_patterns/linked_list.{
  deinit, get_element_info, init, insert_ascending, remove, run_element_with,
  run_eval_with, run_root_with, spend_for_adding_or_removing_an_element,
  spend_for_updating_elements_data,
}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{OutputReference, Transaction}
use constants
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
    _datum_opt: Option<Data>,
    redeemer: SpendRedeemer,
    input_out_ref: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      StateTransition ->
        //Delegating responsibility to the mint validator
        spend_for_adding_or_removing_an_element(
          users_linked_list_policy_id,
          self.mint,
        )
      ModifyUser {
        own_input_index,
        own_output_index,
        state_to_change_index,
        state_field_value,
        power_user_node_ref_input_index,
      } -> {
        let power_user_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_node_ref_input_index,
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
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_user_node_key),
          //Ensure you're only modifying data, and validate permission logic
          spend_for_updating_elements_data(
            own_input_index,
            own_output_index,
            input_out_ref,
            self.inputs,
            self.outputs,
            self.mint,
            fn(_lovelace_change, _node_key, old_data, new_data) {
              expect input_datum: User = old_data
              expect output_user_status: User = new_data
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
                  //Cannot verify a blacklisted user
                  input_datum.is_blacklisted == False,
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
                  //Cannot blacklist a verified user
                  input_datum.is_verified == False,
                  output_user_status == expected_datum,
                }
              }
            },
          )
            |> run_eval_with(
                users_linked_list_policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
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
    when redeemer is {
      Init { root_output_index } -> {
        let nonce_validated =
          list.any(
            self.inputs,
            fn(input) { input.output_reference == init_input_out_ref },
          )
        let root_output = utils.safe_list_at(self.outputs, root_output_index)
        and {
          //Only 1 token of this policy must be minted (the root NFT)

          // FIXME: expensive
          dict.size(tokens(self.mint, policy_id)) == 1,
          init(nonce_validated, root_output, self.mint, fn(_, _) { True })
            |> run_root_with(policy_id, constants.linked_list_root_key),
        }
      }
      Deinit { root_input_index } -> {
        let root_input = utils.safe_list_at(self.inputs, root_input_index)
        and {
          //Only 1 token of this policy must be burned (the root NFT)
          dict.size(tokens(self.mint, policy_id)) == 1,
          deinit(root_input, self.mint, fn(_, _) { True })
            |> run_root_with(policy_id, constants.linked_list_root_key),
        }
      }
      AddUser {
        new_user_key,
        anchor_node_input_index,
        anchor_node_output_index,
        appended_node_output_index,
        power_user_node_ref_input_index,
      } -> {
        let power_user_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_node_ref_input_index,
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

        let anchor_input =
          utils.safe_list_at(self.inputs, anchor_node_input_index)
        let anchor_output =
          utils.safe_list_at(self.outputs, anchor_node_output_index)
        let new_node_output =
          utils.safe_list_at(self.outputs, appended_node_output_index)

        and {
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_user_node_key),
          //Only 1 token of this policy must be minted (prevents detached node forgery)
          dict.size(tokens(self.mint, policy_id)) == 1,
          //User must be added into the user status list
          insert_ascending(
            anchor_input,
            anchor_output,
            new_node_output,
            self.mint,
            fn(
              _lovelace_change,
              _anchor_key,
              _anchor_data,
              _new_lovelace,
              node_key,
              node_data,
              _link,
            ) {
              //Datum must be of correct type
              expect parsed_users_status_data: User = node_data
              and {
                node_key == new_user_key,
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
              }
            },
          )
            |> run_eval_with(
                policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
              ),
        }
      }
      RemoveUser {
        user_key_to_remove,
        anchor_node_input_index,
        removed_node_input_index,
        anchor_node_output_index,
        admin_node_ref_input_index,
      } -> {
        let admin_ref_input =
          utils.safe_list_at(self.reference_inputs, admin_node_ref_input_index)

        let (admin_node_key, admin_data) =
          get_element_info(
            admin_ref_input.output,
            fn(_lovelace, node_key, data, _link) {
              expect Some(key) = node_key
              expect admin_data: PowerUser = data
              (key, admin_data)
            },
          )
            |> run_element_with(
                power_users_linked_list_policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
              )

        let anchor_input =
          utils.safe_list_at(self.inputs, anchor_node_input_index)
        let removing_input =
          utils.safe_list_at(self.inputs, removed_node_input_index)
        let anchor_output =
          utils.safe_list_at(self.outputs, anchor_node_output_index)

        and {
          //Must be signed by the power user
          must_be_signed_by_credential(self, admin_node_key),
          //Must be an admin
          admin_data.is_admin,
          //Only 1 token of this policy must be burned (prevents extra mint in same tx)
          dict.size(tokens(self.mint, policy_id)) == 1,
          //User must be removed from the user status list
          remove(
            anchor_input,
            removing_input,
            anchor_output,
            self.mint,
            fn(
              _lovelace_change,
              _anchor_key,
              _anchor_data,
              _rem_lovelace,
              rem_key,
              rem_data,
              _link,
            ) {
              //Datum must be of correct type
              expect _parsed: User = rem_data
              rem_key == user_key_to_remove
            },
          )
            |> run_eval_with(
                policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
              ),
        }
      }
    }
  }

  else(_) {
    fail
  }
}
