use aiken/collection/dict.{size}
use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{
  DatumHash, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
}
use types/global_state.{
  GlobalState, GlobalStateMintRedeemer, GlobalStateSpendRedeemer, MintSecurity,
  PauseTransfers, UpgradeGlobalState,
} as gs
use utils

validator global_state(
  init_input_out_ref: OutputReference,
  global_state_spend_script_hash: ByteArray,
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
      //Goes to the smart tokens spend script
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
    input: OutputReference,
    self: Transaction,
  ) {
    expect Some(datum) = datumOpt

    when redeemer is {
      MintSecurity(global_state_output_index) -> False
      PauseTransfers(global_state_output_index) -> False
      UpgradeGlobalState(global_state_output_index) -> False
    }
  }

  else(_) {
    fail
  }
}
//Spend rules
//MintSecurities: mint of transfer manager must be called (look for redeemer to know minted_amount and 
//global_state_output), minted_amount must be mintable_amount - minted_amount >= 0, output must have 
//updated mintable_amount and rest of the datum untouched

// expect Some(global_state_output) =
//   list.at(self.outputs, redeemer.global_state_output_index)
// expect InlineDatum(global_state_output_datum) = global_state_output.datum
// expect GlobalState { mintable_amount, .. } = global_state_output_datum
// let remaining_amount = input_datum.mintable_amount - transfer_manager_redeemer.minted_amount
//   //Remaining amount must NOT be negative
//   remaining_amount >= 0,
//   //Global state mintable amount must be updated
//   global_state_output_datum.mintable_amount == remaining_amount,

//         //Global State output must have same Value
//   quantity_of(
//     global_state_output.value,
//     global_state_nft_policy_id,
//     global_state_nft_asset_name,
//   ) > 0,
//TODO Global state must go back to this spend script with proper datum

//PauseTransfers: called only if powerUser canPause and must not change anything else
//UpgradeGlobalState: called only by owner to freely change the datum
