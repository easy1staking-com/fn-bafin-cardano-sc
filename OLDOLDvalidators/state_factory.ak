//There is an instance of this SC for each admin token (PolicyId+AssetName), which also means there's an instance of this SC
//for each type of security tokens.
//This SC produces user status tokens that must be always sent to the state_manager.
//The token AssetName must always be the same and it's determined by the transfer_manager parameter.
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
  fn minter(redeemer: Redeemer, ctx: ScriptContext) {
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
