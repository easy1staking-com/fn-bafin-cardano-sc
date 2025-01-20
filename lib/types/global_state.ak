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

pub type GlobalState {
  //If true, no transfer can be executed
  transfers_paused: Bool,
  //PowerUsers linked list minting policy
  power_user_linked_list_policy_id: ByteArray,
  //Goes to zero when new tokens are minted, increases when tokens are burnt
  mintable_amount: Int,
  //Owner of the security
  owner_credential_hash: ByteArray,
  //BaFin compliant info, not directly used in the contracts
  security_info: SecurityInfo,
}

pub type GlobalStateMintRedeemer {
  global_state_output_index: Int,
}

pub type GlobalStateSpendAction {
  MintSecurity { transferManagerMintRedeemerIndex: Int }
  PauseTransfers {
    transfers_paused: Bool,
    issuer_node_ref_input_index: Int,
    prev_issuer_node_ref_input_index: Int,
  }
  UpgradeGlobalState
}

pub type GlobalStateSpendRedeemer {
  global_state_output_index: Int,
  action: GlobalStateSpendAction,
}
