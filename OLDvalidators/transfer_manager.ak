//There is an instance of this SC for each state_manager instance, so one for each admin token (PolicyId+AssetName).
//Each utxo has the securities owner's stake_credential.
//The user is authorized to spend or receive the security tokens only if the state_manager has an utxo with
//a valid state token issued by the issuer and with the user's stake_credential.
use aiken/collection/list.{foldl, length}
use cardano/address.{Address, Credential, Inline, Script, StakeCredential}
use cardano/assets.{AssetName, PolicyId, flatten, quantity_of}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use common.{is_user_allowed}
use types.{
  LockTokens, LockedTransferDatum, StateManagerDatum, Transfer,
  TransferManagerDatum, TransferManagerMintRedeemer,
  TransferManagerSpendRedeemer, TransferManagerWithdrawRedeemer, TransferOutput,
}
use utils.{
  all_sc_inputs_from_same_user, get_inputs_from_sc, get_own_hash,
  is_output_to_sc, must_be_signed_by_stake_credential,
}

validator transfer_manager(
  issuerManagerHash: PolicyId,
  issuerAssetName: AssetName,
  adminManagerHash: PolicyId,
  adminAssetName: AssetName,
  stateManagerHash: PolicyId,
  lockedTransferManagerHash: ByteArray,
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
      //We don't check the datum because we don't use it but it exists to be CIP-113 compliant
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerManagerHash,
        issuerAssetName,
      ),
      redeemer.transferAmount > 0,
      quantity_of(self.mint, policy_id, securityAssetName) == redeemer.transferAmount,
      quantity_of(transferManagerOutput.value, policy_id, securityAssetName) == redeemer.transferAmount,
      is_output_to_sc(transferManagerOutput, policy_id),
      length(flatten(transferManagerOutput.value)) <= 21,
    }
  }

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

  withdraw(
    redeemer: TransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    let stateAssetName = adminAssetName
    let securityAssetName = adminAssetName
    expect Script(ownScriptHash) = credential
    when redeemer is {
      Transfer(
        outputsDetails,
        firstOutputIndex,
        totalInputAmount,
        ownerStateIndex,
        ownerStakeCredential,
      ) -> {
        expect Some(userRefInput) =
          list.at(self.reference_inputs, ownerStateIndex)
        let actualInputTotalAmount =
          validate_all_inputs_and_get_total_amount(
            self.inputs,
            ownScriptHash,
            securityAssetName,
            userRefInput,
            stateManagerHash,
            stateAssetName,
          )
        let outputsToThisSC = list.drop(self.outputs, firstOutputIndex)
        and {
          must_be_signed_by_stake_credential(self, ownerStakeCredential),
          totalInputAmount == actualInputTotalAmount,
          validate_all_outputs(
            self.reference_inputs,
            outputsToThisSC,
            ownScriptHash,
            securityAssetName,
            outputsDetails,
            actualInputTotalAmount,
            stateManagerHash,
            stateAssetName,
          ),
        }
      }
      LockTokens(
        adminStakeCredential,
        adminRefInputIndex,
        lockedTokensAmount,
        lockingOutputIndex,
        changeOutputIndex,
        lastUserStakeCredential,
      ) -> {
        expect Some(adminRefInput) =
          list.at(self.reference_inputs, adminRefInputIndex)
        //only inputs from account
        let transferManagerInputs =
          get_inputs_from_sc(self.inputs, ownScriptHash)
        let actualInputTotalTokens =
          foldl(
            transferManagerInputs,
            0,
            fn(input, result) {
              quantity_of(input.output.value, ownScriptHash, securityAssetName) + result
            },
          )
        and {
          must_be_signed_by_stake_credential(self, adminStakeCredential),
          is_user_allowed(
            adminRefInput,
            adminStakeCredential,
            adminManagerHash,
            adminAssetName,
          ),
          all_sc_inputs_from_same_user(
            transferManagerInputs,
            lastUserStakeCredential,
          ),
          validate_lock_and_change_outputs(
            self.outputs,
            ownScriptHash,
            securityAssetName,
            actualInputTotalTokens,
            lockedTokensAmount,
            lockingOutputIndex,
            changeOutputIndex,
            lockedTransferManagerHash,
            lastUserStakeCredential,
          ),
        }
      }
    }
  }

  else(_) {
    fail
  }
}

pub fn test_validate_all_inputs_and_get_total_amount(
  inputs: List<Input>,
  transferManagerScriptHash: ByteArray,
  securityAssetName: AssetName,
  userRefInput: Input,
  stateManagerHash: PolicyId,
  userStateAssetName: AssetName,
) {
  validate_all_inputs_and_get_total_amount(
    inputs,
    transferManagerScriptHash,
    securityAssetName,
    userRefInput,
    stateManagerHash,
    userStateAssetName,
  )
}

fn validate_all_inputs_and_get_total_amount(
  inputs: List<Input>,
  transferManagerScriptHash: ByteArray,
  securityAssetName: AssetName,
  userRefInput: Input,
  stateManagerHash: PolicyId,
  userStateAssetName: AssetName,
) {
  //only inputs from account
  let inputFromThisSC = get_inputs_from_sc(inputs, transferManagerScriptHash)
  expect InlineDatum(user_state_datum) = userRefInput.output.datum
  expect userStateDatum: StateManagerDatum = user_state_datum

  expect
    quantity_of(userRefInput.output.value, stateManagerHash, userStateAssetName) > 0
  let tokensAmountFromThisSC =
    foldl(
      inputFromThisSC,
      0,
      fn(input, result) {
        expect Some(inputStakeCredential) =
          input.output.address.stake_credential
        expect Inline(inputCredential) = inputStakeCredential
        expect inputCredential == userStateDatum.credential
        quantity_of(
          input.output.value,
          transferManagerScriptHash,
          securityAssetName,
        ) + result
      },
    )

  tokensAmountFromThisSC
}

fn validate_all_outputs(
  referenceInputs: List<Input>,
  outputsToThisSC: List<Output>,
  transferManagerScriptHash: ByteArray,
  securityAssetName: AssetName,
  outputsDetails: List<TransferOutput>,
  actualInputTotalAmount: Int,
  stateManagerHash: PolicyId,
  userStateAssetName: AssetName,
) {
  let totalTokensInOutput =
    list.indexed_foldr(
      outputsToThisSC,
      0,
      fn(index, output, result) {
        expect Some(outputDetails) = list.at(outputsDetails, index)
        expect Some(outputStakeCredential) = output.address.stake_credential
        expect Inline(outputCredential) = outputStakeCredential
        expect Some(receiverStateRefInput) =
          list.at(referenceInputs, outputDetails.receiverStateIndex)
        expect InlineDatum(receiver_state_datum) =
          receiverStateRefInput.output.datum
        expect receiverStateDatum: StateManagerDatum = receiver_state_datum

        let securityTokenInOutput =
          quantity_of(
            output.value,
            transferManagerScriptHash,
            securityAssetName,
          )
        expect and {
            quantity_of(
              receiverStateRefInput.output.value,
              stateManagerHash,
              userStateAssetName,
            ) > 0,
            outputCredential == outputDetails.credential,
            outputCredential == receiverStateDatum.credential,
            securityTokenInOutput == outputDetails.amount,
            is_output_to_sc(output, transferManagerScriptHash),
            //dos protection
            length(flatten(output.value)) <= 5,
          }
        securityTokenInOutput + result
      },
    )

  totalTokensInOutput == actualInputTotalAmount
}

fn validate_lock_and_change_outputs(
  outputs: List<Output>,
  transferManagerScriptHash: ByteArray,
  securityTokenAssetName: AssetName,
  actualInputTotalTokens: Int,
  lockedTokensAmount: Int,
  lockingOutputIndex: Int,
  changeOutputIndex: Int,
  lockedTransferManager: ByteArray,
  lastUserStakeCredential: StakeCredential,
) {
  let change = actualInputTotalTokens - lockedTokensAmount

  expect Some(lockingOutput) = list.at(outputs, lockingOutputIndex)
  expect InlineDatum(locking_output_datum) = lockingOutput.datum
  expect parsedLockingDatum: LockedTransferDatum = locking_output_datum

  expect Some(changeOutput) = list.at(outputs, changeOutputIndex)
  expect Some(changeOutputStakeCredential) =
    changeOutput.address.stake_credential

  let isLockingOutputValid = and {
      is_output_to_sc(lockingOutput, lockedTransferManager),
      parsedLockingDatum == LockedTransferDatum {
        ownerStakeCredential: lastUserStakeCredential,
        tranferManagerScriptHash: transferManagerScriptHash,
        tokenAssetName: securityTokenAssetName,
      },
      quantity_of(
        lockingOutput.value,
        transferManagerScriptHash,
        securityTokenAssetName,
      ) == lockedTokensAmount,
      //dos protection
      length(flatten(lockingOutput.value)) <= 5,
    }
  let isChangeOutputValid = and {
      is_output_to_sc(changeOutput, transferManagerScriptHash),
      changeOutputStakeCredential == lastUserStakeCredential,
      quantity_of(
        changeOutput.value,
        transferManagerScriptHash,
        securityTokenAssetName,
      ) == change,
      //dos protection
      length(flatten(changeOutput.value)) <= 5,
    }
  and {
    isLockingOutputValid,
    or {
      change == 0,
      and {
        change > 0,
        isChangeOutputValid,
      },
    },
  }
}
