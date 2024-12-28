//This SC receives security tokens that must be locked.
//Only the custodialAdmin can unlock them and send them back to a user
use aiken/hash.{Blake2b_224, Hash}
use aiken/list.{foldl, length}
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, WithdrawFrom,
}
use aiken/transaction/credential.{Address, Inline, Script, ScriptCredential}
use aiken/transaction/value.{AssetName, PolicyId, flatten, quantity_of}
use types.{LockedTransferDatum, TransferDatum}
use utils.{
  get_inputs_from_sc, get_outputs_to_sc, get_own_hash, must_be_signed_by,
}

type Redeemer {
  withdrawIndex: Int,
}

validator(custodialAdminAddress: Address) {
  fn minter(datum: LockedTransferDatum, redeemer: Redeemer, ctx: ScriptContext) {
    when ctx.purpose is {
      Spend(_) -> {
        let ownScriptHash = get_own_hash(ctx.purpose, ctx.transaction.inputs)

        expect Some(withdrawScript) =
          list.at(ctx.transaction.withdrawals, redeemer.withdrawIndex)
        when withdrawScript is {
          Pair(Inline(ScriptCredential(script)), _amnt) ->
            script == ownScriptHash
          _ -> False
        }
      }
      WithdrawFrom(withdrawStakeCredential) -> {
        expect Inline(ScriptCredential(ownScriptHash)) = withdrawStakeCredential
        and {
          must_be_signed_by(ctx.transaction, custodialAdminAddress),
          areAllInputTokensToTransferManager(
            ctx.transaction.inputs,
            ctx.transaction.outputs,
            datum.tokenPolicyId,
            datum.tokenAssetName,
            datum.tranferManagerScriptHash,
            ownScriptHash,
          ),
        }
      }
      _ -> False
    }
  }
}

fn areAllInputTokensToTransferManager(
  inputs: List<Input>,
  outputs: List<Output>,
  tokenPolicyId: PolicyId,
  tokenAssetName: AssetName,
  tranferManagerScriptHash: Hash<Blake2b_224, Script>,
  ownScriptHash: Hash<Blake2b_224, Script>,
) {
  let inputFromThisSC = get_inputs_from_sc(inputs, ownScriptHash)
  let outputsToTransferManager =
    get_outputs_to_sc(outputs, tranferManagerScriptHash)
  let tokensAmountFromThisSC =
    foldl(
      inputFromThisSC,
      0,
      fn(input, result) {
        quantity_of(input.output.value, tokenPolicyId, tokenAssetName) + result
      },
    )
  let tokensAmountToTransferManager =
    foldl(
      outputsToTransferManager,
      0,
      fn(output, result) {
        let output_datum_dos_checks = {
          expect InlineDatum(output_datum) = output.datum
          expect parsedOutputDatum: TransferDatum = output_datum
          and {
            parsedOutputDatum == TransferDatum { i: 0 },
            //dos protection
            length(flatten(output.value)) <= 5,
          }
        }
        //Throw error if datum and dos are not valid
        expect output_datum_dos_checks
        quantity_of(output.value, tokenPolicyId, tokenAssetName) + result
      },
    )

  tokensAmountFromThisSC == tokensAmountToTransferManager
}
