//There is an instance of this SC for each issuer token (PolicyId+AssetName), which also means there's an instance of this SC
//for each type of security tokens.
//This SC produces admin tokens that must be always sent to the admin_manager.
//The token AssetName must always be the same and it's determined by the state_factory and state_manager parameter.
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
  fn minter(redeemer: Redeemer, ctx: ScriptContext) {
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
