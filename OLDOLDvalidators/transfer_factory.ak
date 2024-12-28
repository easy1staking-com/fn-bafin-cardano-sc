use aiken/hash.{Blake2b_224, Hash}
//Each instance of this SC produces a certain type of security tokens, authorized by the issuer and always sent to the
//correct transfer_manager instance.
//The tokens minted here must NEVER leave the transfer_manager instance.
//The token AssetName must always be the same and it's determined by the transfer_manager parameter.
//Issuer cannot mint more than the max amount written in the security manager utxo.
use aiken/list.{length}
use aiken/transaction.{InlineDatum, Input, Mint, Output, ScriptContext}
use aiken/transaction/credential.{Script, StakeCredential}
use aiken/transaction/value.{
  AssetName, PolicyId, flatten, from_minted_value, quantity_of,
}
use common.{is_user_allowed}
use types.{SecurityDatum}
use utils.{is_output_to_sc, must_be_signed_by_stake_credential}

type Redeemer {
  issuerStakeCredential: StakeCredential,
  issuerTokenRefInputIndex: Int,
  //input index of the security coming to security_manager SC
  securityManagerInputIndex: Int,
  //input index of the security returning to security_manager SC
  securityManagerOutputIndex: Int,
  transferAmount: Int,
}

validator(
  issuerTokenPolicyId: PolicyId,
  issuerTokenAssetName: AssetName,
  securityManagerTokenPolicyId: PolicyId,
  securityManagerTokenAssetName: AssetName,
  securityManagerScriptHash: Hash<Blake2b_224, Script>,
) {
  fn minter(redeemer: Redeemer, ctx: ScriptContext) {
    expect Mint(ownPolicyId) = ctx.purpose
    expect Some(issuerRefInput) =
      list.at(
        ctx.transaction.reference_inputs,
        redeemer.issuerTokenRefInputIndex,
      )
    expect Some(securityManagerInput) =
      list.at(ctx.transaction.inputs, redeemer.securityManagerInputIndex)
    expect Some(securityManagerOutput) =
      list.at(ctx.transaction.outputs, redeemer.securityManagerOutputIndex)
    and {
      must_be_signed_by_stake_credential(
        ctx.transaction,
        redeemer.issuerStakeCredential,
      ),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerTokenPolicyId,
        issuerTokenAssetName,
      ),
      //security input must have the NFT
      quantity_of(
        securityManagerInput.output.value,
        securityManagerTokenPolicyId,
        securityManagerTokenAssetName,
      ) > 0,
      quantity_of(
        from_minted_value(ctx.transaction.mint),
        ownPolicyId,
        "securityToken",
      ) == redeemer.transferAmount,
      //TODO Issuer must be super careful to send the tokens (with correct datum) to transfer_manager as we cannot enforce it!
      validate_security_output(
        securityManagerInput,
        securityManagerOutput,
        redeemer.transferAmount,
        securityManagerTokenPolicyId,
        securityManagerTokenAssetName,
        securityManagerScriptHash,
      ),
    }
  }
}

fn validate_security_output(
  securityManagerInput: Input,
  securityManagerOutput: Output,
  transferAmount: Int,
  securityManagerTokenPolicyId: PolicyId,
  securityManagerTokenAssetName: AssetName,
  securityManagerScriptHash: Hash<Blake2b_224, Script>,
) {
  expect InlineDatum(input_datum) = securityManagerInput.output.datum
  expect parsedInputDatum: SecurityDatum = input_datum
  expect InlineDatum(output_datum) = securityManagerOutput.datum
  expect parsedOutputDatum: SecurityDatum = output_datum

  let expectedDatum =
    SecurityDatum {
      securityInfo: parsedInputDatum.securityInfo,
      securityPolicyId: parsedInputDatum.securityPolicyId,
      securityAssetName: parsedInputDatum.securityAssetName,
      issuerTokenPolicyId: parsedInputDatum.issuerTokenPolicyId,
      issuerTokenAssetName: parsedInputDatum.issuerTokenAssetName,
      remainingSecurityTokens: parsedInputDatum.remainingSecurityTokens - transferAmount,
    }

  and {
    is_output_to_sc(securityManagerOutput, securityManagerScriptHash),
    parsedOutputDatum == expectedDatum,
    quantity_of(
      securityManagerOutput.value,
      securityManagerTokenPolicyId,
      securityManagerTokenAssetName,
    ) == 1,
    expectedDatum.remainingSecurityTokens >= 0,
    //dos protection
    length(flatten(securityManagerOutput.value)) <= 5,
  }
}
