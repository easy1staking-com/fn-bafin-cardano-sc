//This SC mints tokens that go to issuer_manager to give issuers their powers.
//While the issuers PolicyId remain the same, the AssetName is different for each type of security token.
//If there must be 2 issuers for the same security, then the same AssetName must be used for both issuers.
//In other words: different AssetName == different security
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address}
use utils.{must_be_signed_by}

type Redeemer {
  Redeemer
}

validator(bafinAddress: Address) {
  fn minter(_redeemer: Redeemer, ctx: ScriptContext) {
    must_be_signed_by(ctx.transaction, bafinAddress)
  }
}
