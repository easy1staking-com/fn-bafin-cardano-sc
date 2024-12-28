//Each instance of this SC contains one type of security tokens of all users, where each utxo has the user's stake_credential.
//The user is authorized to spend or receive the security tokens only if the state_manager has an utxo with
//a valid state token issued by the issuer and with the user's stake_credential.
//The security token has PolicyId and AssetName of transfer_factory.
//The user state token has PolicyId and AssetName of state_factory.

//This is what should be public to use this contract
//[tokenPolicyId, tokenAssetName, userStatePolicyId, stateManagerAddress, transferManagerAddress]
use aiken/hash.{Blake2b_224, Hash}
use aiken/list.{foldl, length}
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, WithdrawFrom,
}
use aiken/transaction/credential.{
  Address, Inline, Script, ScriptCredential, StakeCredential,
}
use aiken/transaction/value.{AssetName, PolicyId, flatten, quantity_of}
use common.{is_user_allowed}
use types.{LockedTransferDatum, TransferDatum}
use utils.{
  get_inputs_from_sc, get_outputs_with_token, get_own_hash, is_output_to_sc,
  must_be_signed_by_stake_credential,
}

type Redeemer {
  SpendRedeemer { withdrawIndex: Int }
  Transfer {
    //StakeCredential of the owner of the utxos that are being transferred
    ownerStakeCredential: StakeCredential,
    //index in the reference input list
    ownerNFTIndex: Int,
    //indexes in the reference input list, one for each output that receives tokens
    receiversNFTIndex: List<Int>,
  }
  LockTokens {
    //StakeCredential of the owner of the utxos that are being transferred
    ownerStakeCredential: StakeCredential,
    //index in the reference input list
    ownerNFTIndex: Int,
    //amount of tokens to lock
    lockedTokens: Int,
    //index in the output list that go to the locked_transfer_manager
    lockingOutputIndex: Int,
    //index in the output list that contains the change if any
    changeOutputIndex: Int,
  }
}

validator(
  securityTokenPolicyId: PolicyId,
  securityTokenAssetName: AssetName,
  userStatePolicyId: PolicyId,
  userStateAssetName: AssetName,
  lockedTransferManager: Hash<Blake2b_224, Script>,
) {
  fn validate(
    _datum: TransferDatum,
    redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when ctx.purpose is {
      Spend(_) -> {
        expect SpendRedeemer(withdrawIndex) = redeemer
        let ownScriptHash = get_own_hash(ctx.purpose, ctx.transaction.inputs)

        expect Some(withdrawScript) =
          list.at(ctx.transaction.withdrawals, withdrawIndex)
        when withdrawScript is {
          Pair(Inline(ScriptCredential(script)), _amnt) ->
            script == ownScriptHash
          _ -> False
        }
      }
      WithdrawFrom(withdrawStakeCredential) ->
        when redeemer is {
          Transfer(ownerStakeCredential, ownerNFTIndex, receiversNFTIndex) -> {
            expect Inline(ScriptCredential(ownScriptHash)) =
              withdrawStakeCredential
            expect Some(userRefInput) =
              list.at(ctx.transaction.reference_inputs, ownerNFTIndex)
            and {
              must_be_signed_by_stake_credential(
                ctx.transaction,
                ownerStakeCredential,
              ),
              validate_all_inputs(
                ctx.transaction.inputs,
                ownScriptHash,
                userRefInput,
                ownerStakeCredential,
                userStatePolicyId,
                userStateAssetName,
              ),
              validate_all_outputs(
                ctx.transaction.reference_inputs,
                ctx.transaction.outputs,
                ownScriptHash,
                securityTokenPolicyId,
                securityTokenAssetName,
                receiversNFTIndex,
                userStatePolicyId,
                userStateAssetName,
              ),
            }
          }
          LockTokens(
            ownerStakeCredential,
            ownerNFTIndex,
            lockedTokens,
            lockingOutputIndex,
            changeOutputIndex,
          ) -> {
            expect Inline(ScriptCredential(ownScriptHash)) =
              withdrawStakeCredential
            expect Some(userRefInput) =
              list.at(ctx.transaction.reference_inputs, ownerNFTIndex)
            //only inputs from account
            let accountInputs =
              get_inputs_from_sc(ctx.transaction.inputs, ownScriptHash)
            let actualTotalTokens =
              foldl(
                accountInputs,
                0,
                fn(input, result) {
                  quantity_of(
                    input.output.value,
                    securityTokenPolicyId,
                    securityTokenAssetName,
                  ) + result
                },
              )
            and {
              must_be_signed_by_stake_credential(
                ctx.transaction,
                ownerStakeCredential,
              ),
              validate_all_inputs(
                ctx.transaction.inputs,
                ownScriptHash,
                userRefInput,
                ownerStakeCredential,
                userStatePolicyId,
                userStateAssetName,
              ),
              validate_lock_and_change_outputs(
                ctx.transaction.outputs,
                ownScriptHash,
                securityTokenPolicyId,
                securityTokenAssetName,
                actualTotalTokens,
                lockedTokens,
                lockingOutputIndex,
                changeOutputIndex,
                lockedTransferManager,
                ownerStakeCredential,
              ),
            }
          }
          _ -> False
        }
      _ -> False
    }
  }
}

fn validate_all_inputs(
  inputs: List<Input>,
  accountScriptHash: Hash<Blake2b_224, Script>,
  userRefInput: Input,
  stakeCredential: StakeCredential,
  userStatePolicyId: PolicyId,
  userStateAssetName: AssetName,
) {
  //only inputs from account
  let accountInputs = get_inputs_from_sc(inputs, accountScriptHash)
  and {
    //user must be allowed to transfer
    is_user_allowed(
      userRefInput,
      stakeCredential,
      userStatePolicyId,
      userStateAssetName,
    ),
    //all inputs from account must belong to this user
    list.all(
      accountInputs,
      fn(input) {
        expect Some(inputStakeCredential) =
          input.output.address.stake_credential
        inputStakeCredential == stakeCredential
      },
    ),
  }
}

fn is_user_allowed_with_index(
  referenceInputs: List<Input>,
  referenceInputNFTIndex: Int,
  stakeCredential: StakeCredential,
  userStatePolicyId: PolicyId,
  userStateAssetName: AssetName,
) {
  expect Some(userRefInput) = list.at(referenceInputs, referenceInputNFTIndex)
  is_user_allowed(
    userRefInput,
    stakeCredential,
    userStatePolicyId,
    userStateAssetName,
  )
}

fn validate_all_outputs(
  referenceInputs: List<Input>,
  outputs: List<Output>,
  accountScriptHash: Hash<Blake2b_224, Script>,
  securityTokenPolicyId: PolicyId,
  securityTokenAssetName: AssetName,
  receiversNFTIndex: List<Int>,
  userStatePolicyId: PolicyId,
  userStateAssetName: AssetName,
) {
  let outputsWithThisToken =
    get_outputs_with_token(
      outputs,
      securityTokenPolicyId,
      securityTokenAssetName,
    )

  let outputsAndRefInputIndexes =
    list.zip(outputsWithThisToken, receiversNFTIndex)

  and {
    length(outputsWithThisToken) == length(receiversNFTIndex),
    list.all(
      outputsAndRefInputIndexes,
      fn(outputAndRefIndex) {
        let output = outputAndRefIndex.1st
        expect Some(outputStakeCredential) = output.address.stake_credential
        expect InlineDatum(output_datum) = output.datum
        expect parsedDatum: TransferDatum = output_datum
        and {
          is_output_to_sc(output, accountScriptHash),
          is_user_allowed_with_index(
            referenceInputs,
            outputAndRefIndex.2nd,
            outputStakeCredential,
            userStatePolicyId,
            userStateAssetName,
          ),
          parsedDatum == TransferDatum { i: 0 },
          //dos protection
          length(flatten(output.value)) <= 5,
        }
      },
    ),
  }
}

fn validate_lock_and_change_outputs(
  outputs: List<Output>,
  accountScriptHash: Hash<Blake2b_224, Script>,
  securityTokenPolicyId: PolicyId,
  securityTokenAssetName: AssetName,
  actualTotalTokens: Int,
  lockedTokens: Int,
  lockingOutputIndex: Int,
  changeOutputIndex: Int,
  lockedTransferManager: Hash<Blake2b_224, Script>,
  stakeCredential: StakeCredential,
) {
  let change = actualTotalTokens - lockedTokens

  expect Some(lockingOutput) = list.at(outputs, lockingOutputIndex)
  expect InlineDatum(locking_output_datum) = lockingOutput.datum
  expect parsedLockingDatum: LockedTransferDatum = locking_output_datum

  expect Some(changeOutput) = list.at(outputs, changeOutputIndex)
  expect Some(changeOutputStakeCredential) =
    changeOutput.address.stake_credential
  expect InlineDatum(change_output_datum) = changeOutput.datum
  expect parsedChangeDatum: TransferDatum = change_output_datum

  let isLockingOutputValid = and {
      is_output_to_sc(lockingOutput, lockedTransferManager),
      parsedLockingDatum == LockedTransferDatum {
        ownerStakeCredential: stakeCredential,
        tranferManagerScriptHash: accountScriptHash,
        tokenPolicyId: securityTokenPolicyId,
        tokenAssetName: securityTokenAssetName,
      },
      quantity_of(
        changeOutput.value,
        securityTokenPolicyId,
        securityTokenAssetName,
      ) == lockedTokens,
      //dos protection
      length(flatten(lockingOutput.value)) <= 5,
    }
  let isChangeOutputValid = and {
      is_output_to_sc(changeOutput, accountScriptHash),
      changeOutputStakeCredential == stakeCredential,
      parsedChangeDatum == TransferDatum { i: 0 },
      quantity_of(
        changeOutput.value,
        securityTokenPolicyId,
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
