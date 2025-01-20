pub type UserStatus {
  is_kyced: Bool,
  is_blacklisted: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyUserStatus {
    own_output_index: Int,
    node_nft_asset_name: ByteArray,
    state_to_change_index: Int,
    state_field_value: Bool,
    admin_node_ref_input_index: Int,
    admin_anchor_node_ref_input_index: Int,
  }
}

pub type MintRedeemer {
  Init
  Deinit
  AddUser {
    new_users_status_key: ByteArray,
    appended_node_output_index: Int,
    anchor_node_output_index: Int,
    power_user_node_ref_input_index: Int,
    power_useranchor_node_ref_input_index: Int,
  }
  RemoveUser {
    users_status_key: ByteArray,
    removed_node_input_index: Int,
    anchor_node_input_index: Int,
    power_user_node_ref_input_index: Int,
    power_useranchor_node_ref_input_index: Int,
  }
}
