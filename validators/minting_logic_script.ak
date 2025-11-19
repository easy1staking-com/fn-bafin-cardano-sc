// use aiken/collection/dict.{size}
// use aiken/collection/list.{length}
// use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
// use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
// use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
// use cardano/transaction.{
//   DatumHash, InlineDatum, Input, NoDatum, Output, Transaction,
// }
// use types/global_state.{GlobalStateDatum}
// use types/issuance_logic_script.{IssuanceLogicScriptWithdrawRedeemer}
// use types/power_users.{PowerUser}
// use utils.{must_be_signed_by_credential}

// validator ilc(
//   tx0: ByteArray,
//   index0: Int,
//   programmable_logic_base_script_hash: ByteArray,
//   global_state_nft_policy_id: ByteArray,
//   global_state_nft_asset_name: ByteArray,
//   issuance_policy_script_hash: ByteArray,
//   smart_token_asset_name: ByteArray,
// ) {
//   withdraw(
//     redeemer: IssuanceLogicScriptWithdrawRedeemer,
//     credential: Credential,
//     self: Transaction,
//   ) {
//     let minted_amount =
//       quantity_of(
//         self.mint,
//         issuance_policy_script_hash,
//         smart_token_asset_name,
//       )
//     expect Some(global_state_input) =
//       list.at(self.reference_inputs, redeemer.global_state_input_index)
//     expect InlineDatum(global_state_datum) = global_state_input.output.datum
//     //TODO This can be more efficient with builtins
//     expect GlobalStateDatum {
//       power_user_linked_list_policy_id,
//       can_user_burn,
//       ..
//     } = global_state_datum
//     expect Some(issuer_node_ref_input) =
//       list.at(self.reference_inputs, redeemer.issuer_node_ref_input_index)
//     expect InlineDatum(issuer_node_datum) = issuer_node_ref_input.output.datum
//     expect parsed_issuer_node_datum: NodeDatum = issuer_node_datum
//     expect Key(power_user_credential_hash) = parsed_issuer_node_datum.key
//     expect power_user_data: PowerUser = parsed_issuer_node_datum.data
//     expect Some(prev_issuer_node_ref_input) =
//       list.at(self.reference_inputs, redeemer.prev_issuer_node_ref_input_index)
//     and {
//       //Only 1 token AssetName minted
//       size(tokens(self.mint, issuance_policy_script_hash)) == 1,
//       //Must mint the correct amount
//       minted_amount == redeemer.minted_amount,
//       //Global State input must have the correct NFT
//       quantity_of(
//         global_state_input.output.value,
//         global_state_nft_policy_id,
//         global_state_nft_asset_name,
//       ) > 0,
//       if minted_amount > 0 {
//         //PowerUser can mint
//         False
//       } else {
//         or {
//           can_user_burn,
//           power_user_data.can_burn,
//         }
//       },
//       //TODO FROM HERE 
//       //The node must belong to the PowerUser list
//       ordered.prove_is_member(
//         power_user_linked_list_policy_id,
//         parsed_issuer_node_datum.key,
//         prev_issuer_node_ref_input.output,
//       ),
//       //Must be signed by the power user
//       must_be_signed_by_credential(self, power_user_credential_hash),
//       if minted_amount > 0 {
//         expect Some(smart_tokens_spend_script_output) =
//           list.at(self.outputs, redeemer.smart_tokens_spend_script_output_index)
//         and {
//           //Must be a minter
//           power_user_data.is_minter,
//           //Goes to the smart tokens spend script
//           smart_tokens_spend_script_output.address.payment_credential == Script(
//             smart_tokens_spend_script_hash,
//           ),
//           //No datum
//           smart_tokens_spend_script_output.datum == NoDatum,
//           //In output exactly how much you have minted
//           quantity_of(
//             smart_tokens_spend_script_output.value,
//             policy_id,
//             security_asset_name,
//           ) == minted_amount,
//           //Only ADA and this token
//           length(flatten(smart_tokens_spend_script_output.value)) <= 2,
//         }
//       } else {
//         //Must be a burner
//         power_user_data.is_burner
//       },
//     }
//   }

//   else(_) {
//     fail
//   }
// }
