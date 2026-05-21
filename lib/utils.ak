use aiken/builtin.{head_list, tail_list}
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId, Value, quantity_of, tokens}
use cardano/transaction.{InlineDatum, Input, Output, Transaction}

pub fn must_be_signed_by_credential(
  transaction: Transaction,
  credential_hash: ByteArray,
) {
  or {
    list.has(transaction.extra_signatories, credential_hash),
    pairs.has_key(transaction.withdrawals, Script(credential_hash)),
  }
}

pub fn safe_list_at(self: List<a>, index: Int) -> a {
  expect index >= 0
  do_list_at(self, index)
}

fn do_list_at(elems: List<a>, at: Int) -> a {
  if at >= 2 {
    do_list_at(tail_list(tail_list(elems)), at - 2)
  } else {
    head_list(
      if at == 1 {
        tail_list(elems)
      } else {
        elems
      },
    )
  }
}

/// Returns the quantity of all tokens with the policyId
pub fn quantity_of_policy_id(value: Value, policyId: PolicyId) {
  dict.foldl(tokens(value, policyId), 0, fn(_k, v, result) { v + result })
}

pub fn get_config_as_data_list(
  config_ref_input: Input,
  config_nft_policy_id: ByteArray,
  config_nft_asset_name: ByteArray,
) {
  expect
    quantity_of(
      config_ref_input.output.value,
      config_nft_policy_id,
      config_nft_asset_name,
    ) > 0
  expect InlineDatum(output_datum) = config_ref_input.output.datum
  builtin.unconstr_fields(output_datum)
}

pub fn expect_inline_datum(output: Output) -> Data {
  expect InlineDatum(d) = output.datum
  d
}

pub fn derive_issuance_policy_id_from_registry_node(
  ref_inputs: List<Input>,
  registry_policy_id: ByteArray,
  credential: Credential,
  // The index of the registry node field which is taken into account for check
  registry_node_field_index: Int,
) -> PolicyId {
  expect Script(hashed_params) = credential

  // Finding the registry node utxo among the reference inputs.
  // Assuming there aren't many reference inputs, a linear search should be fine.
  expect Some(registry_ref_input) =
    list.find(
      ref_inputs,
      fn(input) {
        assets.has_any_nft_strict(input.output.value, registry_policy_id)
      },
    )
  // rename in the redeemer type
  // ensuring it actually has the registry NFT is the critical check 
  expect
    assets.has_any_nft_strict(
      registry_ref_input.output.value,
      registry_policy_id,
    )
  let registry_raw: Data = expect_inline_datum(registry_ref_input.output)
  let registry_fields: List<Data> = builtin.unconstr_fields(registry_raw)
  let reg_hashed_params: ByteArray =
    builtin.un_b_data(list.at(registry_fields, registry_node_field_index))
  // Checking if the hashed params in the registry match the hashed params provided in the redeemer
  // Which if it's the case the key of the node_registry is the issuance_policy_id
  expect reg_hashed_params == hashed_params
  builtin.un_b_data(builtin.head_list(registry_fields))
}
