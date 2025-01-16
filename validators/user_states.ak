use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{
  Key, NodeDatum, get_node_inputs, get_node_outputs,
}
use cardano/assets.{PolicyId, tokens}
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
          //Must be signed by the power user
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
  init_input_out_ref: OutputReference,
  power_users_mint_script_hash: ByteArray,
  admin_node_ref_input_index: Int,
  admin_anchor_node_ref_input_index: Int,
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
      AddUser(
        new_user_status_key,
        inserted_node_output_index,
        anchor_node_output_index,
      ) -> {
        expect Some(admin_ref_input) =
          list.at(self.reference_inputs, admin_node_ref_input_index)
        expect InlineDatum(admin_datum) = admin_ref_input.output.datum
        expect parsed_admin_datum: NodeDatum = admin_datum
        expect power_user_data: PowerUser = parsed_admin_datum.data
        expect Key(admin_node_key) = parsed_admin_datum.key
        expect Some(admin_anchor_node_ref_input) =
          list.at(self.reference_inputs, admin_anchor_node_ref_input_index)
        expect Some(inserted_node_output) =
          list.at(self.outputs, inserted_node_output_index)
        expect InlineDatum(user_status_datum) = inserted_node_output.datum
        expect parsed_user_status_datum: NodeDatum = user_status_datum
        //Datum must be of correct type
        expect _parsed_user_status_data: UserState =
          parsed_user_status_datum.data
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_mint_script_hash,
            parsed_admin_datum.key,
            admin_anchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, admin_node_key),
          //Must be a admin
          power_user_data.is_admin,
          //User must be added into the user status list
          ordered.insert(
            Key(new_user_status_key),
            inserted_node_output_index,
            anchor_node_output_index,
            node_in_outputs,
            node_outputs,
            node_mint,
          ),
        }
      }
      RemoveUser(
        user_status_key,
        removed_node_input_index,
        anchor_node_input_index,
      ) -> {
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
          //Must be signed by the power user
          must_be_signed_by_credential(self, admin_node_key),
          //Must be a admin
          power_user_data.is_admin,
          //User must be added into the user status list
          ordered.remove(
            Key(user_status_key),
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
