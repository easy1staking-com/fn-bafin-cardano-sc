pub type MintingLogicScriptWithdrawRedeemer {
  global_state_reference: GlobalStateRef,
  power_user_node_ref_input_index: Int,
  //Amount minted
  minted_amount: Int,
}

pub type GlobalStateRef {
  GlobalStateReferenceInput { index: Int }
  GlobalStateOutputIndex { index: Int }
}
