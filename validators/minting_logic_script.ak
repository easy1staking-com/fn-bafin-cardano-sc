use aiken/builtin
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Credential}
use cardano/assets.{quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}
use constants
use types/minting_logic_script.{MintingLogicScriptWithdrawRedeemer}
use types/power_users.{PowerUser}
use utils.{must_be_signed_by_credential}

validator minting_logic_validator(
  security_asset_name: ByteArray,
  config_policy_id: ByteArray,
  global_state_policy_id: ByteArray,
  power_users_linked_list_policy_id: ByteArray,
) {
  withdraw(
    redeemer: MintingLogicScriptWithdrawRedeemer,
    _credential: Credential,
    self: Transaction,
  ) {
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

    let global_state_input =
      utils.safe_list_at(self.inputs, redeemer.global_state_input_index)

    let minted_amount =
      quantity_of(self.mint, issuance_policy_id, security_asset_name)

    let power_user_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.power_user_node_ref_input_index,
      )
    expect InlineDatum(power_user_user_datum) =
      power_user_ref_input.output.datum
    expect parsed_power_user_user_datum: NodeDatum = power_user_user_datum
    expect power_user_data: PowerUser = parsed_power_user_user_datum.data
    expect Key { key: power_user_node_key } = parsed_power_user_user_datum.key
    let power_user_anchor_node_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.power_user_anchor_node_ref_input_index,
      )
    and {
      //Redeemer contains the amount just for easy reference for eventual other contracts
      minted_amount == redeemer.minted_amount,
      //The node must belong to the power users registry
      ordered.prove_is_member(
        power_users_linked_list_policy_id,
        parsed_power_user_user_datum.key,
        power_user_anchor_node_ref_input.output,
      ),
      //global_state.spend must be called, so we check that the unique nft is spent
      quantity_of(
        global_state_input.output.value,
        global_state_policy_id,
        constants.global_state_asset_name,
      ) > 0,
      //A power user must have signed the transaction
      must_be_signed_by_credential(self, power_user_node_key),
      //If minted_amount > 0, power user must be minter
      //If minted_amount < 0, power user must be burner
      if minted_amount > 0 {
        power_user_data.can_mint
      } else {
        power_user_data.can_burn
      },
    }
  }

  else(_) {
    fail
  }
}
