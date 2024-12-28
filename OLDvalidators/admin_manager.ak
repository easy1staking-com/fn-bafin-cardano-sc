//There is an instance of this SC for each issuer.
//This SC produces admin tokens that should never leave this SC.
//If there's a utxo with user stakeCredentials it means the user is an admin for that issuer's security.
use aiken/collection/list.{length}
use aiken/crypto.{sha2_256}
use aiken/primitive/bytearray
use cardano/assets.{PolicyId, flatten, quantity_of}
use cardano/transaction.{Output, OutputReference, Transaction}
use common.{input_contains_any_token_with_policy_id, is_user_allowed}
use types.{
  AdminManagerDatum, AdminManagerMintRedeemer, AdminManagerSpendRedeemer,
}
use utils.{is_output_to_sc, must_be_signed_by_stake_credential}

validator admin_manager(issuerManagerHash: ByteArray) {
  mint(
    redeemer: AdminManagerMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    expect Some(issuerRefInput) =
      list.at(self.reference_inputs, redeemer.issuerRefInputIndex)
    expect Some(refInputStakeCredential) =
      issuerRefInput.output.address.stake_credential
    expect Some(adminManagerOutput) =
      list.at(self.outputs, redeemer.adminManagerOutputIndex)
    expect Some(input) = list.head(self.inputs)
    let inputUtxoId =
      sha2_256(
        bytearray.push(
          input.output_reference.transaction_id,
          input.output_reference.output_index,
        ),
      )
    and {
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      refInputStakeCredential == redeemer.issuerStakeCredential,
      input_contains_any_token_with_policy_id(issuerRefInput, issuerManagerHash),
      quantity_of(self.mint, policy_id, inputUtxoId) == 1,
      quantity_of(adminManagerOutput.value, policy_id, inputUtxoId) == 1,
      is_output_to_sc(adminManagerOutput, policy_id),
      length(flatten(adminManagerOutput.value)) <= 5,
    }
  }

  spend(
    datumOpt: Option<AdminManagerDatum>,
    redeemer: AdminManagerSpendRedeemer,
    _input: OutputReference,
    self: Transaction,
  ) {
    expect Some(issuerRefInput) =
      list.at(self.reference_inputs, redeemer.issuerRefInputIndex)
    expect Some(datum) = datumOpt
    and {
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerManagerHash,
        datum.issuerAssetName,
      ),
    }
  }

  else(_) {
    fail
  }
}
