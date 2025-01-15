use cardano/address.{Credential}

pub type ConfigDatum {
  owner_credential: Credential,
  locked_manager_withdraw_script_hash: ByteArray,
  power_user_linked_list_script_hash: ByteArray,
}
