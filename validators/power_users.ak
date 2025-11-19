use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{
  Key, NodeDatum, get_node_inputs, get_node_outputs,
}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use constants
use types/power_users.{
  AddPowerUser, Deinit, Init, MintRedeemer, ModifyPowerUser, PowerUser,
  RemovePowerUser, SpendRedeemer, StateTransition,
}
use utils.{must_be_signed_by_credential}

validator power_users_validator(power_users_linked_list_policy_id: ByteArray) {
  spend(
    _datumOpt: Option<Data>,
    redeemer: SpendRedeemer,
    inputOutRef: OutputReference,
    self: Transaction,
  ) {
    when redeemer is {
      StateTransition ->
        //Delegating responsibility to the mint validator
        ordered.list_state_transition(
          tokens(self.mint, power_users_linked_list_policy_id),
        )
      ModifyPowerUser {
        own_output_index,
        node_nft_asset_name,
        wanted_user_state,
      } -> {
        expect Some(own_input) =
          list.find(
            self.inputs,
            fn(input) { input.output_reference == inputOutRef },
          )
        let node_mint = tokens(self.mint, power_users_linked_list_policy_id)
        expect Some(own_output) = list.at(self.outputs, own_output_index)
        expect InlineDatum(output_datum) = own_output.datum
        expect parsed_output_datum: NodeDatum = output_datum
        expect power_user_data: PowerUser = parsed_output_datum.data
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, constants.owner_credential_hash),
          //Ensure you're only modifying data
          ordered.modify_data(
            node_mint,
            own_input.output,
            own_output,
            power_users_linked_list_policy_id,
            node_nft_asset_name,
          ),
          //output should have the desired data
          power_user_data == wanted_user_state,
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
  owner_credential_hash: ByteArray,
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
      AddPowerUser {
        new_power_user_key,
        appended_node_output_index,
        anchor_node_output_index,
      } -> {
        expect Some(inserted_node_output) =
          list.at(self.outputs, appended_node_output_index)
        expect InlineDatum(power_users_status_datum) =
          inserted_node_output.datum
        expect parsed_power_users_status_datum: NodeDatum =
          power_users_status_datum
        //Datum must be of correct type
        expect _parsed_users_status_data: PowerUser =
          parsed_power_users_status_datum.data
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //User must be added into the user status list
          ordered.insert(
            Key(new_power_user_key),
            appended_node_output_index,
            anchor_node_output_index,
            node_in_outputs,
            node_outputs,
            node_mint,
          ),
        }
      }
      RemovePowerUser {
        power_user_key_to_remove,
        removed_node_input_index,
        anchor_node_input_index,
      } -> {
        expect Some(inserted_node_output) =
          list.at(self.outputs, removed_node_input_index)
        expect InlineDatum(power_users_status_datum) =
          inserted_node_output.datum
        expect parsed_power_users_status_datum: NodeDatum =
          power_users_status_datum
        //Datum must be of correct type
        expect _parsed_users_status_data: PowerUser =
          parsed_power_users_status_datum.data
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //User must be removed from the status list
          ordered.remove(
            Key(power_user_key_to_remove),
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
