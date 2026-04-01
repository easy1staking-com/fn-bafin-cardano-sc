use aiken/collection/dict
use aiken/collection/list
use aiken_design_patterns/linked_list.{
  deinit, init, insert_ascending, remove, run_eval_with, run_root_with,
  spend_for_adding_or_removing_an_element, spend_for_updating_elements_data,
}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{OutputReference, Transaction}
use constants
use types/power_users.{
  AddPowerUser, Deinit, Init, MintRedeemer, ModifyPowerUser, PowerUser,
  RemovePowerUser, SpendRedeemer, StateTransition,
}
use utils.{must_be_signed_by_credential}

validator power_users_validator(
  owner_credential_hash: ByteArray,
  power_users_linked_list_policy_id: ByteArray,
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
          power_users_linked_list_policy_id,
          self.mint,
        )
      ModifyPowerUser {
        own_input_index,
        own_output_index,
        wanted_user_state,
      } ->
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //Ensure you're only modifying data, and output has the desired data
          spend_for_updating_elements_data(
            own_input_index,
            own_output_index,
            input_out_ref,
            self.inputs,
            self.outputs,
            self.mint,
            fn(_lovelace_change, _node_key, _old_data, new_data) {
              expect power_user_data: PowerUser = new_data
              power_user_data == wanted_user_state
            },
          )
            |> run_eval_with(
                power_users_linked_list_policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
              ),
        }
    }
  }

  else(_) {
    fail
  }
}

validator mint(
  owner_credential_hash: ByteArray,
  init_input_out_ref: OutputReference,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, self: Transaction) {
    when redeemer is {
      Init { root_output_index } -> {
        let nonce_validated =
          list.any(
            self.inputs,
            fn(input) { input.output_reference == init_input_out_ref },
          )
        let root_output =
          utils.safe_list_at(self.outputs, root_output_index)
        and {
          //Only 1 token of this policy must be minted (the root NFT)
          dict.size(tokens(self.mint, policy_id)) == 1,
          init(nonce_validated, root_output, self.mint, fn(_, _) { True })
            |> run_root_with(policy_id, constants.linked_list_root_key),
        }
      }
      Deinit { root_input_index } -> {
        let root_input =
          utils.safe_list_at(self.inputs, root_input_index)
        and {
          //Only 1 token of this policy must be burned (the root NFT)
          dict.size(tokens(self.mint, policy_id)) == 1,
          deinit(root_input, self.mint, fn(_, _) { True })
            |> run_root_with(policy_id, constants.linked_list_root_key),
        }
      }
      AddPowerUser {
        new_power_user_key,
        anchor_node_input_index,
        anchor_node_output_index,
        appended_node_output_index,
      } -> {
        let anchor_input =
          utils.safe_list_at(self.inputs, anchor_node_input_index)
        let anchor_output =
          utils.safe_list_at(self.outputs, anchor_node_output_index)
        let new_node_output =
          utils.safe_list_at(self.outputs, appended_node_output_index)
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //Only 1 token of this policy must be minted (prevents detached node forgery)
          dict.size(tokens(self.mint, policy_id)) == 1,
          //Power user must be added into the list
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
              expect _parsed: PowerUser = node_data
              node_key == new_power_user_key
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
      RemovePowerUser {
        power_user_key_to_remove,
        anchor_node_input_index,
        removed_node_input_index,
        anchor_node_output_index,
      } -> {
        let anchor_input =
          utils.safe_list_at(self.inputs, anchor_node_input_index)
        let removing_input =
          utils.safe_list_at(self.inputs, removed_node_input_index)
        let anchor_output =
          utils.safe_list_at(self.outputs, anchor_node_output_index)
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //Only 1 token of this policy must be burned (prevents extra mint in same tx)
          dict.size(tokens(self.mint, policy_id)) == 1,
          //Power user must be removed from the list
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
              expect _parsed: PowerUser = rem_data
              rem_key == power_user_key_to_remove
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
