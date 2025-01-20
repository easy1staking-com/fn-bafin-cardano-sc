use cardano/address.{Credential}

pub type GlobalState {
  //If true, no transfer can be executed
  transfers_paused: Bool,
  //PowerUsers linked list minting policy
  power_user_linked_list_policy_id: ByteArray,
  //Goes to zero when new tokens are minted, increases when tokens are burnt
  mintable_amount: Int,
  //Owner of the security
  owner_credential: Credential,
  //BaFin compliant info, not directly used in the contracts
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

pub type GlobalStateMintRedeemer {
  global_state_output_index: Int,
}

pub type GlobalStateSpendRedeemer {
  MintSecurity { global_state_output_index: Int }
  PauseTransfers { global_state_output_index: Int }
  UpgradeGlobalState { global_state_output_index: Int }
}
// pub fn get_useful_global_state(output: Output) -> (Data, Data) {
//   expect InlineDatum(output_datum) = output.datum
//   let constr = builtin.un_constr_data(output_datum).2nd
//   let transfers_paused = builtin.head_list(constr)
//   let power_user_linked_list_policy_id =
//     builtin.head_list(builtin.tail_list(constr))
//   let mintable_amount =
//     builtin.head_list(builtin.tail_list(builtin.tail_list(constr)))
//   let owner_credential =
//     builtin.head_list(
//       builtin.tail_list(builtin.tail_list(builtin.tail_list(constr))),
//     )

//   expect global_state: (Bool, ByteArray, Int, Credential) =
//     (
//       transfers_paused,
//       power_user_linked_list_policy_id,
//       mintable_amount,
//       owner_credential,
//     )
//   global_state
// }
