//There is an instance of this SC for each admin token (PolicyId+AssetName), which also means there's an instance of this SC
//for each type of security tokens.
//Each utxo that contains a state_factory token can optionally have a user stake_credential.
//If there is, it means the user has a status and he is authorized to send and receive that specific security.
//To remove the user's authorization, admin just has to spend the user utxo and remove his stake_credentials.
use aiken/list
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{StakeCredential}
use aiken/transaction/value.{AssetName, PolicyId}
use common.{is_user_allowed}
use utils.{must_be_signed_by_stake_credential}

type Redeemer {
  adminStakeCredential: StakeCredential,
  adminTokenRefInputIndex: Int,
}

validator(adminTokenPolicyId: PolicyId, adminTokenAssetName: AssetName) {
  fn spend(redeemer: Redeemer, ctx: ScriptContext) {
    expect Some(adminRefInput) =
      list.at(
        ctx.transaction.reference_inputs,
        redeemer.adminTokenRefInputIndex,
      )
    and {
      must_be_signed_by_stake_credential(
        ctx.transaction,
        redeemer.adminStakeCredential,
      ),
      is_user_allowed(
        adminRefInput,
        redeemer.adminStakeCredential,
        adminTokenPolicyId,
        adminTokenAssetName,
      ),
    }
  }
}
