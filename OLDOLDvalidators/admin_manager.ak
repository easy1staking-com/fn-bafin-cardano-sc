//There is an instance of this SC for each issuer token (PolicyId+AssetName), which also means there's an instance of this SC
//for each type of security tokens.
//Each utxo that contains a admin_factory token can optionally have a user stake_credential.
//If there is, it means the user is admin.
//To remove the user's authorization, issuer just has to spend the user utxo and remove his stake_credentials.
use aiken/list
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{StakeCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use common.{is_user_allowed}
use utils.{must_be_signed_by_stake_credential}

type Redeemer {
  issuerStakeCredential: StakeCredential,
  issuerTokenRefInputIndex: Int,
}

validator(issuerTokenPolicyId: PolicyId, issuerTokenAssetName: AssetName) {
  fn spend(redeemer: Redeemer, ctx: ScriptContext) {
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
        issuerTokenPolicyId,
        issuerTokenAssetName,
      ),
    }
  }
}
