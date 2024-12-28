use aiken/collection/list.{foldl, length}
use cardano/address.{Address, Credential, Script, StakeCredential}
use cardano/assets.{AssetName, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use types.{
  LockedTransferDatum, LockedTransferManagerSpendRedeemer,
  LockedTransferManagerWithdrawRedeemer,
}
use utils.{get_inputs_from_sc, get_own_hash, is_output_to_sc, must_be_signed_by}

validator locked_transfer_manager(custodialAdminAddress: Address) {
  spend(
    _datumOpt: Option<Data>,
    redeemer: LockedTransferManagerSpendRedeemer,
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

  withdraw(
    redeemer: LockedTransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    expect Script(ownScriptHash) = credential
    let lockedTransferManagerInputs =
      get_inputs_from_sc(self.inputs, ownScriptHash)
    let actualInputTotalTokens =
      foldl(
        lockedTransferManagerInputs,
        0,
        fn(input, result) {
          expect InlineDatum(input_datum) = input.output.datum
          expect lockedDatum: LockedTransferDatum = input_datum
          //All inputs must have same token
          expect
            lockedDatum.tranferManagerScriptHash == redeemer.tranferManagerScriptHash && lockedDatum.tokenAssetName == redeemer.tokenAssetName
          quantity_of(
            input.output.value,
            redeemer.tranferManagerScriptHash,
            redeemer.tokenAssetName,
          ) + result
        },
      )
    and {
      must_be_signed_by(self, custodialAdminAddress),
      validate_unlock_and_change_outputs(
        self.outputs,
        ownScriptHash,
        redeemer.tokenAssetName,
        actualInputTotalTokens,
        redeemer.unlockedTokensAmount,
        redeemer.unlockingOutputIndex,
        redeemer.changeOutputIndex,
        redeemer.tranferManagerScriptHash,
        redeemer.newUserStakeCredential,
        redeemer.changeUserStakeCredential,
      ),
    }
  }

  else(_) {
    fail
  }
}

fn validate_unlock_and_change_outputs(
  outputs: List<Output>,
  lockedTransferManagerScriptHash: ByteArray,
  tokenAssetName: AssetName,
  actualInputTotalTokens: Int,
  unlockedTokensAmount: Int,
  unlockingOutputIndex: Int,
  changeOutputIndex: Int,
  transferManagerScriptHash: ByteArray,
  newUserStakeCredential: StakeCredential,
  changeUserStakeCredential: StakeCredential,
) {
  let change = actualInputTotalTokens - unlockedTokensAmount

  expect Some(unlockingOutput) = list.at(outputs, unlockingOutputIndex)
  expect Some(unlockingOutputStakeCredential) =
    unlockingOutput.address.stake_credential
  expect Some(changeOutput) = list.at(outputs, changeOutputIndex)
  expect InlineDatum(change_output_datum) = changeOutput.datum
  expect changeLockingDatum: LockedTransferDatum = change_output_datum

  let isUnlockingOutputValid = and {
      //We don't check the datum because we don't use it but it exists to be CIP-113 compliant
      is_output_to_sc(unlockingOutput, transferManagerScriptHash),
      unlockingOutputStakeCredential == newUserStakeCredential,
      quantity_of(
        unlockingOutput.value,
        transferManagerScriptHash,
        tokenAssetName,
      ) == unlockedTokensAmount,
      //dos protection
      length(flatten(unlockingOutput.value)) <= 5,
    }
  let isChangeOutputValid = and {
      is_output_to_sc(changeOutput, lockedTransferManagerScriptHash),
      quantity_of(changeOutput.value, transferManagerScriptHash, tokenAssetName) == change,
      changeLockingDatum == LockedTransferDatum {
        ownerStakeCredential: changeUserStakeCredential,
        tranferManagerScriptHash: transferManagerScriptHash,
        tokenAssetName,
      },
      //dos protection
      length(flatten(changeOutput.value)) <= 5,
    }
  and {
    isUnlockingOutputValid,
    or {
      change == 0,
      and {
        change > 0,
        isChangeOutputValid,
      },
    },
  }
}
