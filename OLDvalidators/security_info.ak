//There is an instance of this SC for each real world security.
//This SC produces a utxo with a NFT that should never leave this SC.
//The datum contains the security information.
use aiken/collection/dict.{keys}
use aiken/collection/list.{length}
use aiken/crypto.{sha2_256}
use aiken/primitive/bytearray
use cardano/address.{Address}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{Output, OutputReference, Transaction}
use common.{is_user_allowed}
use types.{
  SecurityInfoDatum, SecurityInfoMintRedeemer, SecurityInfoSpendRedeemer,
}
use utils.{
  get_inputs_from_sc, get_outputs_to_sc, get_own_hash, must_be_signed_by,
  must_be_signed_by_stake_credential,
}

validator security_info(bafinAddress: Address, issuerManagerHash: ByteArray) {
  mint(
    redeemer: SecurityInfoMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    expect Some(securityInfoOutput) =
      list.at(self.outputs, redeemer.securityInfoOutputIndex)
    expect Some(input) = list.head(self.inputs)
    let inputUtxoId =
      sha2_256(
        bytearray.push(
          input.output_reference.transaction_id,
          input.output_reference.output_index,
        ),
      )
    and {
      must_be_signed_by(self, bafinAddress),
      quantity_of(self.mint, policy_id, inputUtxoId) == 1,
      quantity_of(securityInfoOutput.value, policy_id, inputUtxoId) == 1,
    }
  }

  spend(
    _datumOpt: Option<SecurityInfoDatum>,
    redeemer: SecurityInfoSpendRedeemer,
    input: OutputReference,
    self: Transaction,
  ) {
    let ownScriptHash = get_own_hash(input, self.inputs)
    expect Some(issuerRefInput) =
      list.at(self.reference_inputs, redeemer.issuerTokenRefInputIndex)
    expect Some(issuerAssetName) =
      list.head(keys(tokens(issuerRefInput.output.value, issuerManagerHash)))
    expect Some(actualSecurityInfoInput) =
      list.at(
        get_inputs_from_sc(self.inputs, ownScriptHash),
        redeemer.currentSecurityInfoIndex,
      )
    expect Some(securityInfoAssetName) =
      list.head(
        keys(tokens(actualSecurityInfoInput.output.value, ownScriptHash)),
      )
    //Expect only 1 output to sc
    expect [output] = get_outputs_to_sc(self.outputs, ownScriptHash)
    and {
      input == actualSecurityInfoInput.output_reference,
      must_be_signed_by_stake_credential(self, redeemer.issuerStakeCredential),
      is_user_allowed(
        issuerRefInput,
        redeemer.issuerStakeCredential,
        issuerManagerHash,
        issuerAssetName,
      ),
      quantity_of(output.value, ownScriptHash, securityInfoAssetName) == 1,
      length(flatten(output.value)) <= 5,
    }
  }

  else(_) {
    fail
  }
}
