pub type User {
  is_verified: Bool,
  is_blacklisted: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyUser {
    own_output_index: Int,
    node_nft_asset_name: ByteArray,
    //Index of the field in the User datum to change
    state_to_change_index: Int,
    state_field_value: Bool,
    power_user_node_ref_input_index: Int,
    power_user_anchor_node_ref_input_index: Int,
  }
}

pub type MintRedeemer {
  Init
  Deinit
  AddUser {
    new_user_key: ByteArray,
    appended_node_output_index: Int,
    anchor_node_output_index: Int,
    power_user_node_ref_input_index: Int,
    power_user_anchor_node_ref_input_index: Int,
  }
  RemoveUser {
    user_key_to_remove: ByteArray,
    removed_node_input_index: Int,
    anchor_node_input_index: Int,
    admin_node_ref_input_index: Int,
    admin_anchor_node_ref_input_index: Int,
  }
}
