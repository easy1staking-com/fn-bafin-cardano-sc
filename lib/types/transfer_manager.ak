pub type TransferManagerMintRedeemer {
  minted_amount: Int,
  issuer_node_ref_input_index: Int,
  prev_issuer_node_ref_input_index: Int,
  smart_tokens_spend_script_output_index: Int,
  global_state_input_index: Int,
}

pub type TransferManagerAction {
  user_node_ref_input_index: Int,
  prev_user_node_ref_input_index: Int,
}

pub type TransferManagerWithdrawRedeemer {
  global_state_ref_input_index: Int,
  smart_tokens_node_ref_input_index: Int,
  prev_smart_tokens_node_ref_input_index: Int,
  actionsForEachInput: List<TransferManagerAction>,
}
