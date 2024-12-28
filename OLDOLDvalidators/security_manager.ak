//This is one SC for all existing securities.
//In this SC the issuer registers, edits or cancels new securities.
//As everybody can send utxos in this SC, only the ones created by a proper issuer are valid.
//Proper issuer: there's an issuer token in issuer_manager with his stake_credential.
//Only the issuer designated in the datum can edit/cancel the security.
use aiken/list
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{StakeCredential}
use common.{is_user_allowed}
use types.{SecurityDatum}
use utils.{must_be_signed_by_stake_credential}

type Redeemer {
  issuerStakeCredential: StakeCredential,
  issuerTokenRefInputIndex: Int,
}

//TODO Too much power to issuer? Do we want to at least enforce that the NFT goes back to this SC?
validator(_version: Int) {
  fn spend(datum: SecurityDatum, redeemer: Redeemer, ctx: ScriptContext) {
    expect Some(issuerRefInput) =
      list.at(
        ctx.transaction.reference_inputs,
        redeemer.issuerTokenRefInputIndex,
      )
    and {
      must_be_signed_by_stake_credential(
        ctx.transaction,
        redeemer.issuerStakeCredential,
      ),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        datum.issuerTokenPolicyId,
        datum.issuerTokenAssetName,
      ),
    }
  }
}
