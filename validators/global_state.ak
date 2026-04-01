use aiken/builtin
use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Script}
use cardano/assets.{PolicyId, quantity_of, without_lovelace}
use cardano/transaction.{
  InlineDatum, Mint, Output, OutputReference, Transaction, find_input,
}
use constants
use types/global_state.{
  GlobalStateDatum, GlobalStateSpendRedeemer, MintSecurity, ModifySecurityInfo,
  PauseTransfers,
} as gs
use types/power_users.{PowerUser}
use utils.{must_be_signed_by_credential, quantity_of_policy_id}

validator global_state_mint_validator(tx0: ByteArray, index0: Int) {
  mint(_redeemer: Data, policy_id: PolicyId, self: Transaction) {
    let contract_credential = Script(policy_id)

    let one_time_utxo = OutputReference(tx0, index0)
    //we won't use input_present, we just need it to be there, otherwise error
    expect Some(_input_present) = find_input(self.inputs, one_time_utxo)
    let output_parameters = utils.safe_list_at(self.outputs, 0)

    and {
      //First output goes to this address
      output_parameters.address.payment_credential == contract_credential,
      //Only 1 token of same policy
      quantity_of_policy_id(self.mint, policy_id) == 1,
      //I am minting only 1 token (NFT)
      quantity_of(self.mint, policy_id, constants.global_state_asset_name) == 1,
      //NFT goes to the output
      quantity_of(
        output_parameters.value,
        policy_id,
        constants.global_state_asset_name,
      ) == 1,
    }
  }

  else(_) {
    fail
  }
}

validator global_state_spend_validator(
  // statically setting `owner_credential_hash` here is imho not the best. it should be an attribute of the datum in teh global utxo
  // so that i can be rotated, the nft policy id guarding the utxo should be used as paramter for indirection.
  owner_credential_hash: ByteArray,
  security_asset_name: ByteArray,
  config_policy_id: ByteArray,
  global_state_policy_id: ByteArray,
) {
  spend(
    datum_opt: Option<GlobalStateDatum>,
    redeemer: GlobalStateSpendRedeemer,
    input_out_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datum_opt
    expect Some(own_input) =
      list.find(
        self.inputs,
        fn(input) { input.output_reference == input_out_ref },
      )

    let config =
      utils.get_config_as_data_list(
        utils.safe_list_at(
          self.reference_inputs,
          redeemer.config_ref_input_index,
        ),
        config_policy_id,
        constants.config_asset_name,
      )
    let issuance_policy_id = builtin.un_b_data(utils.safe_list_at(config, 0))

    let global_state_output =
      utils.safe_list_at(self.outputs, redeemer.global_state_output_index)
    expect InlineDatum(global_state_output_datum) = global_state_output.datum
    expect parsed_global_state_output_datum: GlobalStateDatum =
      global_state_output_datum
    when redeemer.action is {
      MintSecurity { issuance_policy_redeemer_index } -> {
        //issuance_logic.mint validator must be called
        let issuance_policy_redeemer =
          utils.safe_list_at(self.redeemers, issuance_policy_redeemer_index)
        expect issuance_policy_redeemer.1st == Mint(issuance_policy_id)
        let minted_amount =
          quantity_of(self.mint, issuance_policy_id, security_asset_name)
        let remaining_amount = input_datum.mintable_amount - minted_amount
        let expected_datum =
          GlobalStateDatum {
            transfers_paused: input_datum.transfers_paused,
            mintable_amount: remaining_amount,
            users_linked_list_policy_id: input_datum.users_linked_list_policy_id,
            power_user_linked_list_policy_id: input_datum.power_user_linked_list_policy_id,
            security_info: input_datum.security_info,
          }
        and {
          //Remaining amount must NOT be negative
          remaining_amount >= 0,
          //Goes to this spend script
          global_state_output.address.payment_credential == own_input.output.address.payment_credential,
          //Datum must change only mintable_amount
          parsed_global_state_output_datum == expected_datum,
          //Global State output must have the correct NFT to be the legit one
          quantity_of(
            global_state_output.value,
            global_state_policy_id,
            constants.global_state_asset_name,
          ) == 1,
          //No Value change
          own_input.output.value == global_state_output.value,
        }
      }
      PauseTransfers {
        transfers_paused,
        power_user_node_ref_input_index,
      } -> {
        let power_user_node_ref_input =
          utils.safe_list_at(
            self.reference_inputs,
            power_user_node_ref_input_index,
          )

        let (power_user_credential_hash, power_user_data) =
          get_element_info(
            power_user_node_ref_input.output,
            fn(_lovelace, node_key, data, _link) {
              expect Some(key) = node_key
              expect power_user_data: PowerUser = data
              (key, power_user_data)
            },
          )
            |> run_element_with(
                input_datum.power_user_linked_list_policy_id,
                constants.linked_list_root_key,
                constants.linked_list_node_key_prefix,
                constants.linked_list_node_key_prefix_length,
              )

        let expected_datum =
          GlobalStateDatum {
            transfers_paused,
            mintable_amount: input_datum.mintable_amount,
            users_linked_list_policy_id: input_datum.users_linked_list_policy_id,
            power_user_linked_list_policy_id: input_datum.power_user_linked_list_policy_id,
            security_info: input_datum.security_info,
          }
        and {
          //Must be signed by the minter
          must_be_signed_by_credential(self, power_user_credential_hash),
          //Must have permission to pause/unpause transfers
          power_user_data.can_pause,
          //Goes to the this spend script
          global_state_output.address.payment_credential == own_input.output.address.payment_credential,
          //Datum must change only transfers_paused
          parsed_global_state_output_datum == expected_datum,
          //No Value change
          own_input.output.value == global_state_output.value,
        }
      }
      ModifySecurityInfo { new_security_info } -> {
        let expected_datum =
          GlobalStateDatum {
            transfers_paused: input_datum.transfers_paused,
            mintable_amount: input_datum.mintable_amount,
            users_linked_list_policy_id: input_datum.users_linked_list_policy_id,
            power_user_linked_list_policy_id: input_datum.power_user_linked_list_policy_id,
            security_info: new_security_info,
          }
        and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, owner_credential_hash),
          //Goes to the this spend script
          global_state_output.address.payment_credential == own_input.output.address.payment_credential,
          //No Value change
          without_lovelace(own_input.output.value) == without_lovelace(
            global_state_output.value,
          ),
          //Datum must change only transfers_paused
          parsed_global_state_output_datum == expected_datum,
        }
      }
    }
  }

  else(_) {
    fail
  }
}
