use aiken/cbor
use aiken/collection/dict
use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Credential}
use cardano/assets.{PolicyId, quantity_of}
use cardano/transaction.{Transaction}
use constants
use types/issuance.{IssuanceCborHex, apply_hashed_parameter}
use types/minting_logic_script.{MintingLogicScriptWithdrawRedeemer}
use types/power_users.{PowerUser}
use utils.{expect_inline_datum, must_be_signed_by_credential}

validator minting_logic_validator(
  issuance_cbor_hex_cs: PolicyId,
  security_asset_name: ByteArray,
  global_state_policy_id: ByteArray,
  power_users_linked_list_policy_id: ByteArray,
) {
  withdraw(
    redeemer: MintingLogicScriptWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    // you should be able to calculate policy id reproducing the same steps that the registry mint does.
    // The reason why I think this should work: https://github.com/cardano-foundation/cip113-programmable-tokens/blob/main/src/programmable-tokens-onchain-aiken/validators/registry_mint.ak#L72-L79
    // is that if an attacker is spoofing the issuance utxo, it won't be anyway a registered programmable token (ie. there won't be an entry in the registry),
    // BUT if the correct issuance is used, because of invoking the proper issuance contract, the token will actually be a programmable token
    // which can be registered accordingly

    expect Some(issuance_ref_input) =
      //should this be a find.any instead of find.some?
      list.find(
        self.reference_inputs,
        fn(input) {
          let tokens = assets.tokens(input.output.value, issuance_cbor_hex_cs)
          !dict.is_empty(tokens)
        },
      )

    // Extract the IssuanceCborHex datum
    let issuance_datum = expect_inline_datum(issuance_ref_input.output)
    expect issuance_cbor: IssuanceCborHex = issuance_datum

    let issuance_policy_id =
      apply_hashed_parameter(
        issuance_cbor.prefix_cbor_hex,
        issuance_cbor.postfix_cbor_hex,
        cbor.serialise(credential),
      )

    let global_state_input =
      utils.safe_list_at(self.inputs, redeemer.global_state_input_index)

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

    and {
      //Redeemer contains the amount just for easy reference for eventual other contracts
      minted_amount == redeemer.minted_amount,
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
