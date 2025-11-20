use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Redeemer, Transaction, find_input,
}
use constants
use types/config.{Config}
use utils

validator config_mint_validator(
  tx0: ByteArray,
  index0: Int,
  config_spend_script_hash: ByteArray,
) {
  mint(_redeemer: Redeemer, policy_id: PolicyId, self: Transaction) {
    let one_time_utxo = OutputReference(tx0, index0)
    //We won't use input_present, we just need it to be there, otherwise error
    expect Some(_input_present) = find_input(self.inputs, one_time_utxo)
    let output_parameters = utils.safe_list_at(self.outputs, 0)

    and {
      //First output goes to this address
      output_parameters.address.payment_credential == Script(
        config_spend_script_hash,
      ),
      //Only 1 token of same policy
      utils.quantity_of_policy_id(self.mint, policy_id) == 1,
      //I am minting only 1 token (NFT)
      quantity_of(self.mint, policy_id, constants.config_asset_name) == 1,
      //NFT goes to the output
      quantity_of(
        output_parameters.value,
        policy_id,
        constants.config_asset_name,
      ) == 1,
    }
  }

  else(_) {
    fail
  }
}

validator config_spend_validator(owner_credential_hash: ByteArray) {
  spend(
    datum_opt: Option<Config>,
    _redeemer: Redeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    expect Some(datum) = datum_opt
    expect Some(input_contract) = find_input(self.inputs, own_ref)
    let output_contract = utils.safe_list_at(self.outputs, 0)
    expect InlineDatum(output_datum) = output_contract.datum
    //value can be anything but the type must be of correct type
    expect _casted_datum: Config = output_datum

    and {
      input_contract.output.value == output_contract.value,
      input_contract.output.address == output_contract.address,
      //Must be signed by the owner
      utils.must_be_signed_by_credential(self, owner_credential_hash),
    }
  }

  else(_) {
    fail
  }
}
