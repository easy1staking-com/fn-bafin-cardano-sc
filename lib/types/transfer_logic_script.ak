pub type TransferLogicScriptAction {
  user_node_ref_input_index: Int,
}

pub type TransferLogicScriptWithdrawRedeemer {
  global_state_ref_input_index: Int,
  actions_for_each_input: List<TransferLogicScriptAction>,
}
