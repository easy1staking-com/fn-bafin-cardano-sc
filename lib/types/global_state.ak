pub type GlobalStateDatum {
  //If true, no transfer can be executed
  transfers_paused: Bool,
  //Goes to zero when new tokens are minted, increases when tokens are burnt
  mintable_amount: Int,
  //Users linked list minting policy
  users_linked_list_policy_id: ByteArray,
  //PowerUsers linked list minting policy
  power_user_linked_list_policy_id: ByteArray,
  //Owner of the security
  owner_credential_hash: ByteArray,
  //Regulation (eg. BaFin) compliancy info, not directly used in the contracts
  security_info: Data,
}

pub type GlobalStateSpendAction {
  MintSecurity { issuance_policy_redeemer_index: Int }
  PauseTransfers {
    transfers_paused: Bool,
    power_user_node_ref_input_index: Int,
    prev_power_user_node_ref_input_index: Int,
  }
  ModifySecurityInfo { new_security_info: Data }
}

pub type GlobalStateSpendRedeemer {
  global_state_output_index: Int,
  action: GlobalStateSpendAction,
}
