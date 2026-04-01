pub type PowerUser {
  credential_hash: ByteArray,
  //Admins can add/remove users from the Users linked list
  is_admin: Bool,
  //Minters can mint new tokens
  can_mint: Bool,
  //Burners can burn tokens
  can_burn: Bool,
  //Pausers can pause/unpause all the transfers
  can_pause: Bool,
  //Verifiers can verify users (KYC)
  can_verify: Bool,
  //Blacklisters can blacklist users so they cannot transfer tokens
  can_blacklist: Bool,
  //Force transfers can move tokens from users to any verified and non-blacklisted address
  can_force_transfer: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyPowerUser {
    own_input_index: Int,
    own_output_index: Int,
    wanted_user_state: PowerUser,
  }
}

pub type MintRedeemer {
  Init { root_output_index: Int }
  Deinit { root_input_index: Int }
  AddPowerUser {
    new_power_user_key: ByteArray,
    anchor_node_input_index: Int,
    anchor_node_output_index: Int,
    appended_node_output_index: Int,
  }
  RemovePowerUser {
    power_user_key_to_remove: ByteArray,
    anchor_node_input_index: Int,
    removed_node_input_index: Int,
    anchor_node_output_index: Int,
  }
}
