use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/address.{Credential, StakeCredential}
use cardano/assets.{AssetName, PolicyId}

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

pub type SecurityDatum {
  securityPolicyId: PolicyId,
  securityAssetName: AssetName,
  transferManagerWithdrawScriptHash: ByteArray,
  userStateManagerSpendScriptHash: ByteArray,
  securityInfo: SecurityInfo,
  issuerTokenAssetName: AssetName,
  remainingSecurityTokens: Int,
}

pub type AdminManagerDatum {
  issuerAssetName: AssetName,
}

pub type StateManagerData {
  adminAssetName: AssetName,
}

pub type StateManagerDatum {
  credential: Credential,
  data: StateManagerData,
}

pub type TransferManagerDatum {
  userStateAssetName: AssetName,
  data: Option<Data>,
}

pub type LockedTransferDatum {
  ownerStakeCredential: StakeCredential,
  tranferManagerScriptHash: Hash<Blake2b_224, VerificationKey>,
  tokenAssetName: AssetName,
}
