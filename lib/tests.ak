// use aiken/collection/dict
// use aiken/interval.{Finite, Interval, IntervalBound}
// use cardano/address.{Address, Inline, StakeCredential}
// use cardano/assets.{from_asset, from_asset_list}
// use cardano/transaction.{Input, NoDatum, Output, OutputReference, Transaction}
// use utils

// test is_user_allowed() {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let userTokenPolicyId = "TEST_POLICY"
//   let userTokenAssetName = "TEST_ASSET"
//   let inputOutputReference =
//     OutputReference { transaction_id: "123456789", output_index: 3 }
//   let inputAddress =
//     Address {
//       payment_credential: address.VerificationKey("payment_credential"),
//       stake_credential: Some(userStakeCredential),
//     }
//   let inputOutput =
//     Output {
//       address: inputAddress,
//       value: from_asset(userTokenPolicyId, userTokenAssetName, 1),
//       datum: NoDatum,
//       reference_script: None,
//     }
//   let input =
//     Input { output_reference: inputOutputReference, output: inputOutput }

//   common.is_user_allowed(
//     input,
//     userStakeCredential,
//     userTokenPolicyId,
//     userTokenAssetName,
//   )
// }

// test is_user_allowed_fail() fail {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let userTokenPolicyId = "TEST_POLICY"
//   let userTokenAssetName = "TEST_ASSET"
//   let inputOutputReference =
//     OutputReference { transaction_id: "123456789", output_index: 3 }
//   let inputAddress =
//     Address {
//       payment_credential: address.VerificationKey("payment_credential"),
//       stake_credential: Some(userStakeCredential),
//     }
//   let inputOutput =
//     Output {
//       address: inputAddress,
//       value: from_asset(userTokenPolicyId, userTokenAssetName, 1),
//       datum: NoDatum,
//       reference_script: None,
//     }
//   let input =
//     Input { output_reference: inputOutputReference, output: inputOutput }

//   common.is_user_allowed(
//     input,
//     Inline(address.VerificationKey("different_stake_credential")),
//     userTokenPolicyId,
//     userTokenAssetName,
//   )
// }

// test must_be_signed_by_stake_credential() {
//   let validityRange: Interval<Int> =
//     Interval {
//       lower_bound: IntervalBound { bound_type: Finite(1), is_inclusive: True },
//       upper_bound: IntervalBound { bound_type: Finite(10), is_inclusive: True },
//     }
//   let tx =
//     Transaction {
//       inputs: [],
//       reference_inputs: [],
//       outputs: [],
//       fee: 0,
//       mint: from_asset("", "", 10),
//       certificates: [],
//       withdrawals: [],
//       validity_range: validityRange,
//       extra_signatories: [
//         "stake_credential", "another_stake_credential",
//         "another_stake_credential2",
//       ],
//       redeemers: [],
//       datums: dict.empty,
//       id: "transaction_id",
//       votes: [],
//       proposal_procedures: [],
//       current_treasury_amount: None,
//       treasury_donation: None,
//     }
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   utils.must_be_signed_by_stake_credential(tx, userStakeCredential)
// }

// test must_be_signed_by_stake_credential_fail() fail {
//   let validityRange: Interval<Int> =
//     Interval {
//       lower_bound: IntervalBound { bound_type: Finite(1), is_inclusive: True },
//       upper_bound: IntervalBound { bound_type: Finite(10), is_inclusive: True },
//     }
//   let tx =
//     Transaction {
//       inputs: [],
//       reference_inputs: [],
//       outputs: [],
//       fee: 0,
//       mint: from_asset("", "", 10),
//       certificates: [],
//       withdrawals: [],
//       validity_range: validityRange,
//       extra_signatories: [
//         "another_stake_credential", "another_stake_credential2",
//       ],
//       redeemers: [],
//       datums: dict.empty,
//       id: "transaction_id",
//       votes: [],
//       proposal_procedures: [],
//       current_treasury_amount: None,
//       treasury_donation: None,
//     }
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   utils.must_be_signed_by_stake_credential(tx, userStakeCredential)
// }

// test input_contains_any_token_with_policy_id() {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let inputOutputReference =
//     OutputReference { transaction_id: "123456789", output_index: 3 }
//   let inputAddress =
//     Address {
//       payment_credential: address.VerificationKey("payment_credential"),
//       stake_credential: Some(userStakeCredential),
//     }
//   let inputOutput =
//     Output {
//       address: inputAddress,
//       value: from_asset_list(
//         [
//           Pair("a", [Pair("a", 1), Pair("b", 5)]),
//           Pair("b", [Pair("a", 7), Pair("b", 1)]),
//           Pair("c", [Pair("a", 7), Pair("b", 1)]),
//         ],
//       ),
//       datum: NoDatum,
//       reference_script: None,
//     }
//   let input =
//     Input { output_reference: inputOutputReference, output: inputOutput }
//   common.input_contains_any_token_with_policy_id(input: input, policy_id: "b")
// }

// test input_contains_any_token_with_policy_id_fail() fail {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let inputOutputReference =
//     OutputReference { transaction_id: "123456789", output_index: 3 }
//   let inputAddress =
//     Address {
//       payment_credential: address.VerificationKey("payment_credential"),
//       stake_credential: Some(userStakeCredential),
//     }
//   let inputOutput =
//     Output {
//       address: inputAddress,
//       value: from_asset_list(
//         [
//           Pair("a", [Pair("a", 1), Pair("b", 5)]),
//           Pair("c", [Pair("a", 7), Pair("b", 1)]),
//         ],
//       ),
//       datum: NoDatum,
//       reference_script: None,
//     }
//   let input =
//     Input { output_reference: inputOutputReference, output: inputOutput }
//   common.input_contains_any_token_with_policy_id(input: input, policy_id: "b")
// }

// test all_sc_inputs_from_same_user() {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let transferManagerInputs =
//     [
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//     ]
//   utils.all_sc_inputs_from_same_user(transferManagerInputs, userStakeCredential)
// }

// test all_sc_inputs_from_same_user_fail() fail {
//   let userStakeCredential = Inline(address.VerificationKey("stake_credential"))
//   let userStakeCredential2 =
//     Inline(address.VerificationKey("stake_credential2"))
//   let transferManagerInputs =
//     [
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//       build_input_with_stake_credential_from_sc(userStakeCredential2, "scHash"),
//       build_input_with_stake_credential_from_sc(userStakeCredential, "scHash"),
//     ]
//   utils.all_sc_inputs_from_same_user(transferManagerInputs, userStakeCredential)
// }

// // test validate_all_inputs_and_get_total_amount() {
// //   let inputs =
// //     []
// //   let userRefInput = False

// //   transfer_manager.test_validate_all_inputs_and_get_total_amount(
// //     inputs: inputs,
// //     transferManagerScriptHash: "transferManagerScriptHash",
// //     securityAssetName: "securityAssetName",
// //     userRefInput: userRefInput,
// //     stateManagerHash: "stateManagerHash",
// //     userStateAssetName: "userStateAssetName",
// //   )
// // }

// // fn build_input_with_stake_credential_from_user(
// //   stakeCredential: StakeCredential,
// //   userPaymentCredential: ByteArray,
// // ) {
// //   let userTokenPolicyId = "TEST_POLICY"
// //   let userTokenAssetName = "TEST_ASSET"
// //   let inputOutputReference =
// //     OutputReference { transaction_id: "123456789", output_index: 3 }
// //   let inputAddress =
// //     Address {
// //       payment_credential: address.VerificationKey(userPaymentCredential),
// //       stake_credential: Some(stakeCredential),
// //     }
// //   let inputOutput =
// //     Output {
// //       address: inputAddress,
// //       value: from_asset(userTokenPolicyId, userTokenAssetName, 1),
// //       datum: NoDatum,
// //       reference_script: None,
// //     }
// //   let input =
// //     Input { output_reference: inputOutputReference, output: inputOutput }
// //   input
// // }

// fn build_input_with_stake_credential_from_sc(
//   stakeCredential: StakeCredential,
//   scHash: ByteArray,
// ) {
//   let userTokenPolicyId = "TEST_POLICY"
//   let userTokenAssetName = "TEST_ASSET"
//   let inputOutputReference =
//     OutputReference { transaction_id: "123456789", output_index: 3 }
//   let inputAddress =
//     Address {
//       payment_credential: address.VerificationKey(scHash),
//       stake_credential: Some(stakeCredential),
//     }
//   let inputOutput =
//     Output {
//       address: inputAddress,
//       value: from_asset(userTokenPolicyId, userTokenAssetName, 1),
//       datum: NoDatum,
//       reference_script: None,
//     }
//   let input =
//     Input { output_reference: inputOutputReference, output: inputOutput }
//   input
// }
