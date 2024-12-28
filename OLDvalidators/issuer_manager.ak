//Bafin Address can create a new issuer minting an NFT, specifying issuer's stakeCredentials and locking in issuer_manager.
//Bafin Address then can create a SecurityInfo minting an NFT, specifying issuer's stakeCredentials and locking in security_info.
//A issuer can then create a new admin minting an NFT, specifying admin's stakeCredentials and locking in admin_manager.
//A admin can then create a user state minting an NFT, specifying user's stakeCredentials and locking in a dedicated state_manager instance.
//A issuer can then create securities minting them in a dedicated transfer_manager instance.
//Bafin can remove an issuer changing stakeCredentials of his issuer utxo.
//A issuer can edit the security infos for the security_info utxos he controls.
//A issuer can remove an admin changing stakeCredentials of his admin utxo.
//An admin can freeze a user changing stakeCredentials of his state utxo datum.
//An admin can lock user's securities sending them in a utxo to locked_transfer_manager. 
//An admin can lock user's securities and give them to anyone sending them in a utxo to transfer_manager. 

//For each security, there's 1 issuer utxo, 1 security_info utxo, 1 admin utxo, 1 state_manager SC instance and 1 transfer_manager SC instance.
//Only 1 locked_transfer_manager SC exists for all the securities, the utxo datum specifies where the securities are coming from.
use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use utils.{must_be_signed_by}

validator issuer_manager(bafinAddress: Address) {
  mint(_redeemer: Data, _policy_id: PolicyId, self: Transaction) {
    must_be_signed_by(self, bafinAddress)
  }

  spend(
    _datumOpt: Option<Data>,
    _redeemer: Data,
    _input: OutputReference,
    self: Transaction,
  ) {
    must_be_signed_by(self, bafinAddress)
  }

  else(_) {
    fail
  }
}
