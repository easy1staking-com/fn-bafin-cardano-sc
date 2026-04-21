pub type MintingLogicScriptWithdrawRedeemer {
  global_state_reference: GlobalStateRef,
  power_user_node_ref_input_index: Int,
  //Amount minted
  minted_amount: Int,
}

pub type GlobalStateRef {
  // Index into `self.inputs`: the GS UTxO is being spent in this tx
  // (steady state; GS spend validator will run and enforce the cap).
  // NOT a Cardano reference input — named `Input` to avoid confusion
  // with `reference_inputs`, which have a specific meaning in the ledger.
  GlobalStateInput { index: Int }
  // Index into `self.outputs`: the GS UTxO is being created in this tx
  // (genesis / registration). The minting_logic output-branch enforces
  // the genesis guard and minted <= initial mintable_amount.
  GlobalStateOutputIndex { index: Int }
}
