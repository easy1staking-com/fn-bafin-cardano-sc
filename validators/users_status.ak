use aiken/collection/list
use aiken_design_patterns/linked_list/ordered.{
  Key, NodeDatum, get_node_inputs, get_node_outputs,
}
use cardano/assets.{PolicyId, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types/power_users.{PowerUser}
use types/users_status.{
  AddUser, Deinit, Init, MintRedeemer, ModifyUserStatus, RemoveUser,
  SpendRedeemer, StateTransition, UserStatus,
}
use utils.{must_be_signed_by_credential}

validator spend(
  power_users_mint_script_hash: ByteArray,
  users_status_mint_script_hash: ByteArray,
) {
  spend(
    datumOpt: Option<UserStatus>,
    redeemer: SpendRedeemer,
    inputOutRef: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datumOpt
    when redeemer is {
      StateTransition ->
        //Delegating responsibility to the mint validator
        ordered.list_state_transition(
          tokens(self.mint, users_status_mint_script_hash),
        )
      ModifyUserStatus(
        own_output_index,
        node_nft_asset_name,
        state_to_change_index,
        state_field_value,
        power_user_node_ref_input_index,
        power_useranchor_node_ref_input_index,
      ) -> {
        expect Some(own_input) =
          list.find(
            self.inputs,
            fn(input) { input.output_reference == inputOutRef },
          )
        let node_mint = tokens(self.mint, users_status_mint_script_hash)
        expect Some(own_output) = list.at(self.outputs, own_output_index)
        expect InlineDatum(output_datum) = own_output.datum
        expect parsed_output_datum: NodeDatum = output_datum
        expect output_user_status: UserStatus = parsed_output_datum.data
        expect Some(power_userref_input) =
          list.at(self.reference_inputs, power_user_node_ref_input_index)
        expect InlineDatum(power_userdatum) = power_userref_input.output.datum
        expect parsed_power_userdatum: NodeDatum = power_userdatum
        expect power_user_data: PowerUser = parsed_power_userdatum.data
        expect Key(power_usernode_key) = parsed_power_userdatum.key
        expect Some(power_useranchor_node_ref_input) =
          list.at(self.reference_inputs, power_useranchor_node_ref_input_index)
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_mint_script_hash,
            parsed_power_userdatum.key,
            power_useranchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_usernode_key),
          //Check which field of the status we are changing
          if state_to_change_index == 0 {
            let expected_datum =
              UserStatus {
                is_kyced: state_field_value,
                is_blacklisted: input_datum.is_blacklisted,
              }
            and {
              //Must have permission
              power_user_data.can_kyc,
              output_user_status == expected_datum,
            }
          } else {
            let expected_datum =
              UserStatus {
                is_kyced: input_datum.is_kyced,
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
            users_status_mint_script_hash,
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
  power_users_mint_script_hash: ByteArray,
  power_user_node_ref_input_index: Int,
  power_useranchor_node_ref_input_index: Int,
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
        new_users_status_key,
        inserted_node_output_index,
        anchor_node_output_index,
      ) -> {
        expect Some(power_userref_input) =
          list.at(self.reference_inputs, power_user_node_ref_input_index)
        expect InlineDatum(power_userdatum) = power_userref_input.output.datum
        expect parsed_power_userdatum: NodeDatum = power_userdatum
        expect power_user_data: PowerUser = parsed_power_userdatum.data
        expect Key(power_usernode_key) = parsed_power_userdatum.key
        expect Some(power_useranchor_node_ref_input) =
          list.at(self.reference_inputs, power_useranchor_node_ref_input_index)
        expect Some(inserted_node_output) =
          list.at(self.outputs, inserted_node_output_index)
        expect InlineDatum(users_status_datum) = inserted_node_output.datum
        expect parsed_users_status_datum: NodeDatum = users_status_datum
        //Datum must be of correct type
        expect _parsed_users_status_data: UserStatus =
          parsed_users_status_datum.data
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_mint_script_hash,
            parsed_power_userdatum.key,
            power_useranchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_usernode_key),
          //Must be a admin
          power_user_data.is_admin,
          //User must be added into the user status list
          ordered.insert(
            Key(new_users_status_key),
            inserted_node_output_index,
            anchor_node_output_index,
            node_in_outputs,
            node_outputs,
            node_mint,
          ),
        }
      }
      RemoveUser(
        users_status_key,
        removed_node_input_index,
        anchor_node_input_index,
      ) -> {
        expect Some(power_userref_input) =
          list.at(self.reference_inputs, power_user_node_ref_input_index)
        expect InlineDatum(power_userdatum) = power_userref_input.output.datum
        expect parsed_power_userdatum: NodeDatum = power_userdatum
        expect power_user_data: PowerUser = parsed_power_userdatum.data
        expect Key(power_usernode_key) = parsed_power_userdatum.key
        expect Some(power_useranchor_node_ref_input) =
          list.at(self.reference_inputs, power_useranchor_node_ref_input_index)
        and {
          //The node must belong to the power users registry
          ordered.prove_is_member(
            power_users_mint_script_hash,
            parsed_power_userdatum.key,
            power_useranchor_node_ref_input.output,
          ),
          //Must be signed by the power user
          must_be_signed_by_credential(self, power_usernode_key),
          //Must be a admin
          power_user_data.is_admin,
          //User must be added into the user status list
          ordered.remove(
            Key(users_status_key),
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
