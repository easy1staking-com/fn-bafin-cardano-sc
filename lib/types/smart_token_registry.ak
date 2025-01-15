use cardano/address.{Credential}

pub type RegistryData {
  token_policy_id: ByteArray,
  token_asset_name: ByteArray,
  //TODO HERE FIXED FIELDS OF CIP113
  owner_credential: Credential,
  user_state_linked_list_script_hash: ByteArray,
  power_user_linked_list_script_hash: ByteArray,
  locked_manager_withdraw_script_hash: ByteArray,
  transfers_paused: Bool,
  //Goes to zero when new tokens are minted, increases when tokens are burnt
  mintable_amount: Int,
  security_info: SecurityInfo,
}

pub type SecurityInfo {
  isin: ByteArray,
  termOfIssue: ByteArray,
  securityType: ByteArray,
  securityForm: ByteArray,
  securityClass: ByteArray,
  recordKeeping: ByteArray,
  entryType: ByteArray,
  withoutVotingRights: Bool,
  transferRestrictions: Bool,
  thirdPartyRights: Bool,
  companyConsent: Bool,
  participateSettlement: Bool,
  paymentbond: ByteArray,
  dividendPaymentFrequency: ByteArray,
  //total number of tokens
  volumeOfIssuance: Int,
  nominalAmount: Int,
  issuerName: ByteArray,
  issuerRegistration: ByteArray,
  cryptoSecurityRegister: ByteArray,
  shareCustodian: ByteArray,
  tokenCustodian: ByteArray,
}
