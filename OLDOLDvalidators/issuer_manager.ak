//This SC contain the issuer tokens.
//To remove the issuer's authorization, BaFin just has to spend the issuer utxo and remove his stake_credentials.
use aiken/transaction.{ScriptContext}
use aiken/transaction/credential.{Address}
use utils.{must_be_signed_by}

type Redeemer {
  Redeemer
}

validator(bafinAddress: Address) {
  fn spend(_redeemer: Redeemer, ctx: ScriptContext) {
    must_be_signed_by(ctx.transaction, bafinAddress)
  }
}
