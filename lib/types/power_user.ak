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
