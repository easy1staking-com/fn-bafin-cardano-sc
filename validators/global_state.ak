use aiken/collection/dict
use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Transaction,
}
use types/global_state.{
  GlobalState, GlobalStateMintRedeemer, GlobalStateSpendRedeemer, MintSecurity,
  PauseTransfers, UpgradeGlobalState,
} as gs
use types/power_users.{PowerUser}
use types/transfer_manager.{TransferManagerMintRedeemer} as tm
use utils.{must_be_signed_by_credential}

validator global_state(
  init_input_out_ref: OutputReference,
  global_state_spend_script_hash: ByteArray,
  transfer_manager_policy_id: ByteArray,
) {
  mint(
    redeemer: GlobalStateMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let inputRefHash = utils.hash_output_ref(init_input_out_ref)

    expect Some(global_state_output) =
      list.at(self.outputs, redeemer.global_state_output_index)
    expect InlineDatum(global_state_output_datum) = global_state_output.datum
    //Ensure datum is of correct type
    expect _parsed_global_state_output_datum: GlobalState =
      global_state_output_datum
    and {
      //The init input must be spent
      list.any(
        self.inputs,
        fn(input) { input.output_reference == init_input_out_ref },
      ),
      //Only 1 NFT minted ever
      dict.size(tokens(self.mint, policy_id)) == 1,
      //NFT minted goes to output
      quantity_of(global_state_output.value, policy_id, inputRefHash) == 1,
      //Goes to this spend script
      global_state_output.address.payment_credential == Script(
        global_state_spend_script_hash,
      ),
      //Only ADA and this token
      length(flatten(global_state_output.value)) <= 2,
    }
  }

  spend(
    datumOpt: Option<GlobalState>,
    redeemer: GlobalStateSpendRedeemer,
    inputOutRef: OutputReference,
    self: Transaction,
  ) {
    expect Some(input_datum) = datumOpt
    expect Some(own_input) =
      list.find(
        self.inputs,
        fn(input) { input.output_reference == inputOutRef },
      )

    expect Some(global_state_output) =
      list.at(self.outputs, redeemer.global_state_output_index)
    expect InlineDatum(global_state_output_datum) = global_state_output.datum
    expect parsed_global_state_output_datum: GlobalState =
      global_state_output_datum

    when redeemer.action is {
      MintSecurity(transfer_manager_mint_redeemer_index) -> {
        //TransferManager Mint script must be called
        expect Some(transfer_manager_mint_redeemer_in_tx) =
          list.at(self.redeemers, transfer_manager_mint_redeemer_index)
        expect
          transfer_manager_mint_redeemer_in_tx.1st == Mint(
            transfer_manager_policy_id,
          )
        expect TransferManagerMintRedeemer { minted_amount, .. } =
          transfer_manager_mint_redeemer_in_tx.2nd

        let remaining_amount = input_datum.mintable_amount - minted_amount

        let expected_datum =
          GlobalState {
            transfers_paused: input_datum.transfers_paused,
            power_user_linked_list_policy_id: input_datum.power_user_linked_list_policy_id,
            mintable_amount: remaining_amount,
            owner_credential_hash: input_datum.owner_credential_hash,
            security_info: input_datum.security_info,
          }

        and {
          //Remaining amount must NOT be negative
          remaining_amount >= 0,
          //Goes to this spend script
          global_state_output.address.payment_credential == Script(
            global_state_spend_script_hash,
          ),
          //Datum must change only mintable_amount
          parsed_global_state_output_datum == expected_datum,
          //No Value change
          own_input.output.value == global_state_output.value,
        }
      }

      PauseTransfers(
        transfers_paused,
        issuer_node_ref_input_index,
        prev_issuer_node_ref_input_index,
      ) -> {
        expect Some(issuer_node_ref_input) =
          list.at(self.reference_inputs, issuer_node_ref_input_index)
        expect InlineDatum(issuer_node_datum) =
          issuer_node_ref_input.output.datum
        expect parsed_issuer_node_datum: NodeDatum = issuer_node_datum
        expect Key(power_user_credential_hash) = parsed_issuer_node_datum.key
        expect power_user_data: PowerUser = parsed_issuer_node_datum.data
        expect Some(prev_issuer_node_ref_input) =
          list.at(self.reference_inputs, prev_issuer_node_ref_input_index)

        let expected_datum =
          GlobalState {
            transfers_paused,
            power_user_linked_list_policy_id: input_datum.power_user_linked_list_policy_id,
            mintable_amount: input_datum.mintable_amount,
            owner_credential_hash: input_datum.owner_credential_hash,
            security_info: input_datum.security_info,
          }

        and {
          //The node must belong to the poweruser list
          ordered.prove_is_member(
            input_datum.power_user_linked_list_policy_id,
            parsed_issuer_node_datum.key,
            prev_issuer_node_ref_input.output,
          ),
          //Must be signed by the minter
          must_be_signed_by_credential(self, power_user_credential_hash),
          //Must be a pauser
          power_user_data.is_pauser,
          //Goes to the this spend script
          global_state_output.address.payment_credential == Script(
            global_state_spend_script_hash,
          ),
          //Datum must change only transfer_paused
          parsed_global_state_output_datum == expected_datum,
          //No Value change
          own_input.output.value == global_state_output.value,
        }
      }
      UpgradeGlobalState -> and {
          //Must be signed by the owner
          must_be_signed_by_credential(self, input_datum.owner_credential_hash),
          //Goes to the this spend script
          global_state_output.address.payment_credential == Script(
            global_state_spend_script_hash,
          ),
          //No Value change
          own_input.output.value == global_state_output.value,
        }
    }
  }

  else(_) {
    fail
  }
}
