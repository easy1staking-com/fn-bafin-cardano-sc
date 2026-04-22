use aiken/collection/list
use aiken_design_patterns/linked_list.{get_element_info, run_element_with}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId, quantity_of}
use cardano/certificate.{Certificate, RegisterCredential}
use cardano/transaction.{Transaction}
use constants
use env
use types/global_state.{GlobalStateDatum}
use types/issuance.{
  IssuanceCborHex, apply_hashed_parameter, issuance_cbor_hex_token_name,
}
use types/minting_logic_script.{
  GlobalStateInput, GlobalStateOutputIndex,
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

    let minted_amount =
      quantity_of(self.mint, issuance_policy_id, security_asset_name)

    // Validate GS presence per branch. The GS NFT is pinned to the GS spend
    // script address (invariant enforced in global_state.ak), so NFT-in-input
    // implies the spend validator ran, and NFT-in-output in the absence of an
    // NFT-carrying input implies the GS mint validator ran (genesis only).
    when redeemer.global_state_reference is {
      GlobalStateInput { index } -> {
        // Steady state: GS is being spent. Its spend validator runs; and by
        // the non-Mint-branches-reject-mint invariant in global_state.ak,
        // MintSecurity is the only branch compatible with a security mint,
        // which enforces `mintable_amount - minted_amount >= 0`.
        let gs_input = utils.safe_list_at(self.inputs, index)
        expect
          quantity_of(
            gs_input.output.value,
            global_state_policy_id,
            constants.global_state_asset_name,
          ) == 1
      }
      GlobalStateOutputIndex { index } -> {
        // Genesis (registration): GS is freshly minted in this tx. There is
        // no prior cap to decrement. We still enforce:
        //   (a) NFT really appears in the referenced output,
        //   (b) NFT does NOT appear on any input (forces steady-state mints
        //       to use the input branch — where the cap is truly enforced),
        //   (c) minted_amount <= initial mintable_amount written to the GS
        //       output datum (uniform cap semantics across genesis + steady).
        let gs_output = utils.safe_list_at(self.outputs, index)
        expect
          quantity_of(
            gs_output.value,
            global_state_policy_id,
            constants.global_state_asset_name,
          ) == 1
        expect
          !list.any(
            self.inputs,
            fn(i) {
              quantity_of(
                i.output.value,
                global_state_policy_id,
                constants.global_state_asset_name,
              ) == 1
            },
          )
        let gs_datum_raw = expect_inline_datum(gs_output)
        expect gs_datum: GlobalStateDatum = gs_datum_raw
        expect minted_amount <= gs_datum.mintable_amount
      }
    }

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

  // Whitelist RegisterCredential only. Rejecting UnregisterCredential prevents
  // a ~2 ADA griefing DoS: a rubber-stamp publish would allow anyone to
  // de-register this script's stake credential, which would brick every
  // withdraw-zero mint/burn until re-registered. Also rejects delegation and
  // DRep/committee cert types — this credential exists solely for withdraw-0.
  // Tradeoff: the stake credential becomes permanent (2 ADA locked forever).
  publish(_r: Data, c: Certificate, _s: Transaction) {
    when c is {
      RegisterCredential { .. } -> True
      _ -> False
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
