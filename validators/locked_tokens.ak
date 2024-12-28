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

validator locked_tokens(
  issuerManagerHash: PolicyId,
  issuerAssetName: AssetName,
  adminManagerHash: PolicyId,
  adminAssetName: AssetName,
  stateManagerHash: PolicyId,
  lockedTransferManagerHash: ByteArray,
) {
  spend(
    _datumOpt: Option<TransferManagerDatum>,
    redeemer: TransferManagerSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    let ownScriptHash = get_own_hash(input, self.inputs)
    expect Some(withdrawScript) =
      list.at(self.withdrawals, redeemer.withdrawIndex)
    when withdrawScript is {
      Pair(Script(scriptHash), _amnt) -> scriptHash == ownScriptHash
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
