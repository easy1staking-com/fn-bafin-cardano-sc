use aiken/collection/dict.{size}
use aiken/collection/list.{length}
use aiken_design_patterns/linked_list/ordered.{Key, NodeDatum}
use cardano/address.{Address, Credential, Inline, Script, VerificationKey}
use cardano/assets.{PolicyId, flatten, quantity_of, tokens}
use cardano/transaction.{InlineDatum, Input, NoDatum, Output, Transaction}
use types/power_user.{PowerUser}
use types/smart_token_registry.{RegistryData}
use types/transfer_manager.{
  TransferManagerMintRedeemer, TransferManagerWithdrawRedeemer,
} as tm
use types/user_state.{UserState}
use utils.{must_be_signed_by_credential}

validator transfer_manager(
  smart_tokens_spend_script_hash: ByteArray,
  smart_tokens_linked_list_script_hash: ByteArray,
  smart_tokens_linked_list_asset_name: ByteArray,
  security_asset_name: ByteArray,
) {
  mint(
    redeemer: TransferManagerMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    //TODO increment/decrement registry.mintable_amount and ensure it stays >= 0
    expect Some(smart_tokens_node_ref_input) =
      list.at(self.reference_inputs, redeemer.smart_tokens_node_ref_input_index)
    expect InlineDatum(smart_tokens_node_datum) =
      smart_tokens_node_ref_input.output.datum
    expect parsed_smart_tokens_node_datum: NodeDatum = smart_tokens_node_datum
    expect registry_data: RegistryData = parsed_smart_tokens_node_datum.data
    expect Some(prev_smart_tokens_node_ref_input) =
      list.at(
        self.reference_inputs,
        redeemer.prev_smart_tokens_node_ref_input_index,
      )

    expect Some(smart_tokens_spend_script_output) =
      list.at(self.outputs, redeemer.smart_tokens_spend_script_output_index)
    let minted_amount = quantity_of(self.mint, policy_id, security_asset_name)
    expect Some(issuer_node_ref_input) =
      list.at(self.reference_inputs, redeemer.issuer_node_ref_input_index)
    expect InlineDatum(issuer_node_datum) = issuer_node_ref_input.output.datum
    expect parsed_issuer_node_datum: NodeDatum = issuer_node_datum
    expect power_user_data: PowerUser = parsed_issuer_node_datum.data
    expect Some(prev_issuer_node_ref_input) =
      list.at(self.reference_inputs, redeemer.prev_issuer_node_ref_input_index)
    and {
      //Only 1 token unit minted
      size(tokens(self.mint, policy_id)) == 1,
      //Must mint the correct amount
      minted_amount == redeemer.minted_amount,
      //Must belong to registry
      ordered.prove_is_member(
        smart_tokens_linked_list_script_hash,
        parsed_smart_tokens_node_datum.key,
        prev_smart_tokens_node_ref_input.output,
      ),
      //The node must belong to the poweruser list
      ordered.prove_is_member(
        registry_data.power_user_linked_list_script_hash,
        parsed_issuer_node_datum.key,
        prev_issuer_node_ref_input.output,
      ),
      //Must be related to this token
      quantity_of(
        smart_tokens_node_ref_input.output.value,
        smart_tokens_linked_list_script_hash,
        smart_tokens_linked_list_asset_name,
      ) > 0,
      //Must be signed by the minter
      must_be_signed_by_credential(self, power_user_data.credential),
      if minted_amount > 0 {
        and {
          //Must be a minter
          power_user_data.is_minter,
          //In output exactly how much you have minted
          quantity_of(
            smart_tokens_spend_script_output.value,
            policy_id,
            security_asset_name,
          ) == minted_amount,
          //Goes to the smart tokens spend script
          smart_tokens_spend_script_output.address.payment_credential == Script(
            smart_tokens_spend_script_hash,
          ),
          //Only ADA and this token
          length(flatten(smart_tokens_spend_script_output.value)) <= 2,
          //No datum
          smart_tokens_spend_script_output.datum == NoDatum,
        }
      } else {
        //Must be a burner
        power_user_data.is_burner
      },
    }
  }

  withdraw(
    redeemer: TransferManagerWithdrawRedeemer,
    credential: Credential,
    self: Transaction,
  ) {
    expect Script(security_policy_id) = credential

    expect Some(smart_tokens_node_ref_input) =
      list.at(self.reference_inputs, redeemer.smart_tokens_node_ref_input_index)
    expect InlineDatum(smart_tokens_node_datum) =
      smart_tokens_node_ref_input.output.datum
    expect parsed_smart_tokens_node_datum: NodeDatum = smart_tokens_node_datum
    expect registry_data: RegistryData = parsed_smart_tokens_node_datum.data
    expect Some(prev_smart_tokens_node_ref_input) =
      list.at(
        self.reference_inputs,
        redeemer.prev_smart_tokens_node_ref_input_index,
      )

    let global_status_ok = and {
        //The node must belong to the smart tokens registry
        ordered.prove_is_member(
          smart_tokens_linked_list_script_hash,
          parsed_smart_tokens_node_datum.key,
          prev_smart_tokens_node_ref_input.output,
        ),
        //Must be related to this token
        quantity_of(
          smart_tokens_node_ref_input.output.value,
          smart_tokens_linked_list_script_hash,
          smart_tokens_linked_list_asset_name,
        ) > 0,
        //Overall transfers of this tokens must NOT be paused
        registry_data.transfers_paused == False,
      }

    //Collect unique stake_cred that must be verified
    let inputs_user_stake_cred =
      list.unique(
        list.foldr(
          self.inputs,
          [],
          fn(input, result) {
            if quantity_of(
              input.output.value,
              security_policy_id,
              security_asset_name,
            ) > 0 {
              expect Some(Inline(stake_cred)) =
                input.output.address.stake_credential
              list.push(result, stake_cred)
            } else {
              result
            }
          },
        ),
      )

    let outputs_with_token =
      list.filter(
        self.outputs,
        fn(output) {
          quantity_of(output.value, security_policy_id, security_asset_name) > 0
        },
      )

    //As we loop through the inputs we DO NOT need to ensure that the number of actions is equal to the number of inputs
    let all_token_inputs_can_be_spent =
      list.indexed_foldr(
        inputs_user_stake_cred,
        True,
        fn(index, stake_cred, result) {
          //As all inputs must return True, if any of previous input returned False, then fail
          //The last input is not checked but will return its value at the end, so if False withdraw will fail
          expect result
          let input_credential_hash =
            when stake_cred is {
              VerificationKey(hash) -> hash
              Script(hash) -> hash
            }

          expect Some(action) = list.at(redeemer.actionsForEachInput, index)

          expect Some(user_node_ref_input) =
            list.at(self.reference_inputs, action.user_node_ref_input_index)
          expect InlineDatum(user_node_datum) = user_node_ref_input.output.datum
          expect parsed_user_node_datum: NodeDatum = user_node_datum
          expect user_state: UserState = parsed_user_node_datum.data
          expect Some(prev_user_node_ref_input) =
            list.at(
              self.reference_inputs,
              action.prev_user_node_ref_input_index,
            )

          and {
            //The node must belong to the user state list
            ordered.prove_is_member(
              registry_data.user_state_linked_list_script_hash,
              parsed_user_node_datum.key,
              prev_user_node_ref_input.output,
            ),
            parsed_user_node_datum.key == Key { key: input_credential_hash },
            //Must be signed by the user owning this utxo
            must_be_signed_by_credential(self, stake_cred),
            //User has done KYC properly
            user_state.is_kyced == True,
            //User is not blacklisted
            user_state.is_blacklisted == False,
          }
        },
      )

    let all_token_outputs_go_to_smart_tokens_spend_script =
      list.foldr(
        outputs_with_token,
        True,
        fn(output, result) {
          //As all outputs must return True, if any of previous input returned False, then fail
          //The last output is not checked but will return its value at the end, so if False withdraw will fail
          expect result

          and {
            //Stays in the smart tokens spend script
            output.address.payment_credential == Script(
              smart_tokens_spend_script_hash,
            ),
            //TODO DO WE NEED A CHECK ON THE DATUM SIZE?
            //DOS protection
            length(flatten(output.value)) <= 21,
          }
        },
      )

    and {
      global_status_ok,
      all_token_inputs_can_be_spent,
      all_token_outputs_go_to_smart_tokens_spend_script,
    }
  }

  else(_) {
    fail
  }
}
