pub type PowerUser {
  credential_hash: ByteArray,
  //Admins can add/remove users from the users linked list
  is_admin: Bool,
  //Minters can mint new tokens
  can_mint: Bool,
  //Burners can burn tokens
  can_burn: Bool,
  //Pausers can pause/unpause all the transfers
  can_pause: Bool,
  //Kycers can kyc users
  can_kyc: Bool,
  //Blacklisters can blacklist users so they cannot transfer tokens
  can_blacklist: Bool,
  //Force transfers can move tokens from users to any KYCed and non-blacklisted address
  can_force_transfer: Bool,
}

pub type SpendRedeemer {
  StateTransition
  ModifyPowerUser {
    own_output_index: Int,
    node_nft_asset_name: ByteArray,
    wanted_user_state: PowerUser,
  }
}

pub type MintRedeemer {
  Init
  Deinit
  AddPowerUser {
    new_power_user_key: ByteArray,
    appended_node_output_index: Int,
    anchor_node_output_index: Int,
  }
  RemovePowerUser {
    power_user_key_to_remove: ByteArray,
    removed_node_input_index: Int,
    anchor_node_input_index: Int,
  }
}
