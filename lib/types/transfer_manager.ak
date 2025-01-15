use cardano/address.{Credential}

pub type TransferManagerMintRedeemer {
  smart_tokens_node_ref_input_index: Int,
  prev_smart_tokens_node_ref_input_index: Int,
  minted_amount: Int,
  issuer_key: Int,
  issuer_node_ref_input_index: Int,
  prev_issuer_node_ref_input_index: Int,
  smart_tokens_spend_script_output_index: Int,
}

pub type TransferOutput {
  credential: Credential,
  amount: Int,
  receiverStateIndex: Int,
}

pub type TransferManagerAction {
  user_node_ref_input_index: Int,
  prev_user_node_ref_input_index: Int,
}

pub type TransferManagerWithdrawRedeemer {
  config_ref_input_index: Int,
  smart_tokens_node_ref_input_index: Int,
  prev_smart_tokens_node_ref_input_index: Int,
  actionsForEachInput: List<TransferManagerAction>,
}
