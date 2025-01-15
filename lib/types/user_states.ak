pub type UserState {
  is_kyced: Bool,
  is_blacklisted: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyUserStatus {
    own_output_index: Int,
    node_nft_asset_name: ByteArray,
    wanted_user_state: UserState,
    admin_node_ref_input_index: Int,
    admin_anchor_node_ref_input_index: Int,
  }
}

pub type MintRedeemer {
  Init
  Deinit
  AddUser {
    new_user_status_key: ByteArray,
    appended_node_output_index: Int,
    anchor_node_output_index: Int,
  }
  RemoveUser {
    user_status_key: ByteArray,
    removed_node_input_index: Int,
    anchor_node_input_index: Int,
  }
}
