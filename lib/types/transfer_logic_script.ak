pub type TransferLogicScriptAction {
  user_node_ref_input_index: Int,
  prev_user_node_ref_input_index: Int,
}

pub type TransferLogicScriptWithdrawRedeemer {
  global_state_ref_input_index: Int,
  actionsForEachInput: List<TransferLogicScriptAction>,
}
