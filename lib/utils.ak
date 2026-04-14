use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Script}
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

fn do_list_at(self: List<a>, index: Int) -> a {
  if index == 0 {
    builtin.head_list(self)
  } else {
    do_list_at(builtin.tail_list(self), index - 1)
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
