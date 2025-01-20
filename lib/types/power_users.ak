use cardano/address.{Credential}

pub type PowerUser {
  credential: Credential,
  is_admin: Bool,
  is_minter: Bool,
  is_burner: Bool,
  is_pauser: Bool,
  can_kyc: Bool,
  can_blacklist: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyUserStatus {
    own_output_index: Int,
    node_nft_asset_name: ByteArray,
    wanted_user_state: PowerUser,
  }
}

pub type MintRedeemer {
  Init
  Deinit
  AddUser {
    new_users_status_key: ByteArray,
    appended_node_output_index: Int,
    anchor_node_output_index: Int,
  }
  RemoveUser {
    users_status_key: ByteArray,
    removed_node_input_index: Int,
    anchor_node_input_index: Int,
  }
}
