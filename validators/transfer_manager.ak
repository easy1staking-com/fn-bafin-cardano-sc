use aiken/collection/list.{foldl, length}
use cardano/address.{Address, Credential, Inline, Script, StakeCredential}
use cardano/assets.{AssetName, PolicyId, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use common.{is_user_allowed}
use types/datum.{LockedTransferDatum, StateManagerDatum, TransferManagerDatum}
use types/redeemer.{
  LockTokens, Transfer, TransferManagerMintRedeemer,
  TransferManagerSpendRedeemer, TransferManagerWithdrawRedeemer, TransferOutput,
}
use utils.{
  all_sc_inputs_from_same_user, get_inputs_from_sc, get_own_hash,
  is_output_to_sc, must_be_signed_by_stake_credential,
}

validator transfer_manager(
  smartTokenSpendScriptHash: ByteArray,
  lockedManagerSpendScriptHash: ByteArray,
  issuerManagerHash: PolicyId,
  issuerAssetName: AssetName,
  adminManagerHash: PolicyId,
  adminAssetName: AssetName,
) {
  mint(
    redeemer: TransferManagerMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let securityAssetName = adminAssetName
    expect Some(issuerRefInput) =
      list.at(self.reference_inputs, redeemer.issuerTokenRefInputIndex)
    expect Some(transferManagerOutput) =
      list.at(self.outputs, redeemer.transferManagerOutputIndex)
    and {
      //TODO SHOULDN'T WE REDUCE remainingSecurityTokens and check that it's possible to do that?
      //We don't check the datum because we don't use it but it exists to be CIP-113 compliant
      //TODO FIX AUTH PROCESS WITH LATEST 
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerManagerHash,
        issuerAssetName,
      ),
      //No burning, only minting
      redeemer.transferAmount > 0,
      //Must mint the correct amount
      quantity_of(self.mint, policy_id, securityAssetName) == redeemer.transferAmount,
      //In output exactly how much you have minted
      quantity_of(transferManagerOutput.value, policy_id, securityAssetName) == redeemer.transferAmount,
      //Must always go to the smart token spend validator
      is_output_to_sc(transferManagerOutput, smartTokenSpendScriptHash),
      //Only ADA and this token
      length(flatten(transferManagerOutput.value)) <= 2,
    }
  }

  withdraw(
    redeemer: TransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    todo
  }

  else(_) {
    fail
  }
}
