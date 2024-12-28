//Each instance of this SC produces a certain type of security tokens, authorized by the issuer and always sent to the
//correct transfer_manager instance.
//The tokens minted here must NEVER leave the transfer_manager instance.
//The token AssetName must always be the same and it's determined by the transfer_manager parameter.
//Issuer cannot mint more than the max amount written in the security manager utxo.
use aiken/bytearray
use aiken/hash.{sha2_256}
use aiken/list.{length}
use aiken/transaction.{InlineDatum, Input, Mint, Output, ScriptContext}
use aiken/transaction/credential.{StakeCredential}
use aiken/transaction/value.{
  AssetName, PolicyId, flatten, from_minted_value, quantity_of,
}
use common.{is_user_allowed}
use types.{SecurityDatum}
use utils.{must_be_signed_by_stake_credential}

type Redeemer {
  issuerStakeCredential: StakeCredential,
  issuerTokenRefInputIndex: Int,
  //input index of the security returning to security_manager SC
  securityManagerOutputIndex: Int,
  securityDatum: SecurityDatum,
}

validator(issuerTokenPolicyId: PolicyId, issuerTokenAssetName: AssetName) {
  fn minter(redeemer: Redeemer, ctx: ScriptContext) {
    expect Mint(ownPolicyId) = ctx.purpose
    expect Some(issuerRefInput) =
      list.at(
        ctx.transaction.reference_inputs,
        redeemer.issuerTokenRefInputIndex,
      )
    expect Some(securityManagerOutput) =
      list.at(ctx.transaction.outputs, redeemer.securityManagerOutputIndex)
    expect Some(firstInput) = list.at(ctx.transaction.inputs, 0)

    let nftAssetName =
      sha2_256(
        bytearray.push(
          firstInput.output_reference.transaction_id.hash,
          firstInput.output_reference.output_index,
        ),
      )
    and {
      //overflow protection
      firstInput.output_reference.output_index < 256,
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
      quantity_of(
        from_minted_value(ctx.transaction.mint),
        ownPolicyId,
        nftAssetName,
      ) == 1,
      //TODO Issuer must be super careful to send the tokens (with correct datum) to security_manager as we cannot enforce it!
      validate_security_manager_output(
        ownPolicyId,
        nftAssetName,
        securityManagerOutput,
        redeemer.securityDatum,
      ),
    }
  }
}

fn validate_security_manager_output(
  ownPolicyId: PolicyId,
  nftAssetName: AssetName,
  securityManagerOutput: Output,
  securityDatum: SecurityDatum,
) {
  expect InlineDatum(output_datum) = securityManagerOutput.datum
  expect parsedOutputDatum: SecurityDatum = output_datum

  and {
    parsedOutputDatum == securityDatum,
    quantity_of(securityManagerOutput.value, ownPolicyId, nftAssetName) == 1,
    //dos protection
    length(flatten(securityManagerOutput.value)) <= 5,
  }
}
