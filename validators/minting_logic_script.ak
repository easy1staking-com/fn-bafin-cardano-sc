use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{Transaction}
use constants
use env
use types/issuance.{
  IssuanceCborHex, apply_hashed_parameter, issuance_cbor_hex_token_name,
}
use types/minting_logic_script.{
  GlobalStateOutputIndex, GlobalStateReferenceInput,
  MintingLogicScriptWithdrawRedeemer,
}
use types/power_users.{PowerUser}
use utils.{expect_inline_datum, must_be_signed_by_credential}

validator minting_logic_validator(
  security_asset_name: ByteArray,
  global_state_policy_id: ByteArray,
  power_users_linked_list_policy_id: ByteArray,
) {
  withdraw(
    redeemer: MintingLogicScriptWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    expect Script(hashed_params) = credential
    let issuance_policy_id =
      derive_token_policy(self, env.issuance_cbor_hex_policy_id, hashed_params)
    trace @"mint": self.mint
    trace @"issuance_policy_id": issuance_policy_id

    let global_state_value =
      when redeemer.global_state_reference is {
        GlobalStateReferenceInput { index } -> {
          let global_state_input = utils.safe_list_at(self.inputs, index)
          global_state_input.output.value
        }
        GlobalStateOutputIndex { index } -> {
          let global_state_output = utils.safe_list_at(self.outputs, index)
          global_state_output.value
        }
      }

    let minted_amount =
      quantity_of(self.mint, issuance_policy_id, security_asset_name)

    let power_user_ref_input =
      utils.safe_list_at(
        self.reference_inputs,
        redeemer.power_user_node_ref_input_index,
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

    trace @"minted_amount": minted_amount
    trace @"redeemer.minted_amount": redeemer.minted_amount

    and {
      //Redeemer contains the amount just for easy reference for eventual other contracts
      (minted_amount == redeemer.minted_amount)?,
      //global_state.spend must be called, so we check that the unique nft is spent
      (quantity_of(
        global_state_value,
        global_state_policy_id,
        constants.global_state_asset_name,
      ) > 0)?,
      //A power user must have signed the transaction
      must_be_signed_by_credential(self, power_user_node_key)?,
      //If minted_amount > 0, power user must be minter
      //If minted_amount < 0, power user must be burner
      if minted_amount > 0 {
        power_user_data.can_mint
      } else {
        power_user_data.can_burn
      }?,
    }
  }

  else(_) {
    fail
  }
}

fn derive_token_policy(
  self: Transaction,
  issuance_cbor_hex_cs: PolicyId,
  hashed_param: ByteArray,
) -> PolicyId {
  expect Some(issuance_ref_input) =
    list.find(
      self.reference_inputs,
      fn(input) {
        assets.has_nft_strict(
          input.output.value,
          issuance_cbor_hex_cs,
          issuance_cbor_hex_token_name,
        )
      },
    )

  // Extract the IssuanceCborHex datum
  let issuance_datum = expect_inline_datum(issuance_ref_input.output)
  expect issuance_cbor: IssuanceCborHex = issuance_datum

  apply_hashed_parameter(
    issuance_cbor.prefix_cbor_hex,
    issuance_cbor.postfix_cbor_hex,
    hashed_param,
  )
}
