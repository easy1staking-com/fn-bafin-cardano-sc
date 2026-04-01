pub type User {
  is_verified: Bool,
  is_blacklisted: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyUser {
    own_input_index: Int,
    own_output_index: Int,
    //Index of the field in the User datum to change
    state_to_change_index: Int,
    state_field_value: Bool,
    power_user_node_ref_input_index: Int,
  }
}

pub type MintRedeemer {
  Init { root_output_index: Int }
  Deinit { root_input_index: Int }
  AddUser {
    new_user_key: ByteArray,
    anchor_node_input_index: Int,
    anchor_node_output_index: Int,
    appended_node_output_index: Int,
    power_user_node_ref_input_index: Int,
  }
  RemoveUser {
    user_key_to_remove: ByteArray,
    anchor_node_input_index: Int,
    removed_node_input_index: Int,
    anchor_node_output_index: Int,
    admin_node_ref_input_index: Int,
  }
}
