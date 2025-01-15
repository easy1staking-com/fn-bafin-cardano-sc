use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{
  Key, NodeDatum, get_node_inputs, get_node_outputs,
}
use cardano/assets.{PolicyId, quantity_of, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types/power_users.{PowerUser}
use types/user_states.{
  AddUser, Deinit, Init, MintRedeemer, ModifyUserStatus, RemoveUser,
  SpendRedeemer, StateTransition, UserState,
}
use utils.{must_be_signed_by_credential}

validator spend(
  power_users_mint_script_hash: ByteArray,
  user_states_mint_script_hash: ByteArray,
) {
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
          tokens(self.mint, user_states_mint_script_hash),
        )
      ModifyUserStatus(
        own_output_index,
        node_nft_asset_name,
        wanted_user_state,
        admin_node_ref_input_index,
        admin_anchor_node_ref_input_index,
      ) -> {
        expect Some(own_input) =
          list.find(
            self.inputs,
            fn(input) { input.output_reference == inputOutRef },
          )
        let node_mint = tokens(self.mint, user_states_mint_script_hash)
        expect Some(own_output) = list.at(self.outputs, own_output_index)
        expect InlineDatum(output_datum) = own_output.datum
        expect parsed_output_datum: NodeDatum = output_datum
        expect output_user_state: UserState = parsed_output_datum.data
        expect Some(admin_ref_input) =
          list.at(self.reference_inputs, admin_node_ref_input_index)
        expect InlineDatum(admin_datum) = admin_ref_input.output.datum
        expect parsed_admin_datum: NodeDatum = admin_datum
        expect power_user_data: PowerUser = parsed_admin_datum.data
        expect Key(admin_node_key) = parsed_admin_datum.key
        expect Some(admin_anchor_node_ref_input) =
          list.at(self.reference_inputs, admin_anchor_node_ref_input_index)
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_mint_script_hash,
            parsed_admin_datum.key,
            admin_anchor_node_ref_input.output,
          ),
          //Must be signed by the user owning this utxo
          must_be_signed_by_credential(self, admin_node_key),
          //Must be a admin
          power_user_data.is_admin,
          //Ensure you're only modifying data
          ordered.modify_data(
            node_mint,
            own_input.output,
            own_output,
            user_states_mint_script_hash,
            node_nft_asset_name,
          ),
          //output should have the desired data
          output_user_state == wanted_user_state,
        }
      }
    }
  }

  else(_) {
    fail
  }
}

validator mint(
  hub_oracle_script_hash: PolicyId,
  hub_oracle_asset_name: ByteArray,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, self: Transaction) {
    let node_in_outputs = get_node_inputs(self.inputs, policy_id)
    let node_outputs = get_node_outputs(self.outputs, policy_id)
    let node_mint = tokens(self.mint, policy_id)
    when redeemer is {
      Init -> and {
          //TODO
          quantity_of(self.mint, hub_oracle_script_hash, hub_oracle_asset_name) == 1,
          ordered.init(node_outputs, node_mint, policy_id),
        }
      Deinit -> and {
          //TODO
          quantity_of(self.mint, hub_oracle_script_hash, hub_oracle_asset_name) == -1,
          ordered.deinit(node_in_outputs, node_mint, policy_id),
        }
      AddUser(
        new_user_status_key,
        appended_node_output_index,
        anchor_node_output_index,
      ) ->
        //TODO
        False
      RemoveUser(
        user_status_key,
        removed_node_input_index,
        anchor_node_input_index,
      ) ->
        //TODO
        False
    }
  }

  else(_) {
    fail
  }
}
