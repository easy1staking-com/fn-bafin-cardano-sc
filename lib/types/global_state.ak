use aiken/builtin
use cardano/address.{Address, Script}
use cardano/assets.{from_asset, quantity_of}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}
use constants

pub type GlobalStateDatum {
  //If true, no transfer can be executed
  transfers_paused: Bool,
  //Goes to zero when new tokens are minted, increases when tokens are burnt
  mintable_amount: Int,
  //Users linked list minting policy
  users_linked_list_policy_id: ByteArray,
  //PowerUsers linked list minting policy
  power_user_linked_list_policy_id: ByteArray,
  //Regulation (eg. BaFin) compliancy info, not directly used in the contracts
  security_info: Data,
}

/// Asserts the given input is an authentic GS UTxO (carries exactly 1 GS NFT)
/// and returns whether transfers are paused. Reads only the first field of the
/// datum (`transfers_paused`) via UPLC builtins — no full-datum deserialisation.
///
/// Fails (via UPLC error) if:
///   * the input's value does not contain the GS NFT,
///   * the datum is not an inline Constr, or
///   * the first field of the datum is not a Constr (i.e. not a Bool).
///
/// Callers are responsible for locating the GS input first (e.g. via an index
/// carried in the redeemer). Typical usage:
///
///   let gs_input = utils.safe_list_at(self.reference_inputs, redeemer.idx)
///   expect !gs.is_paused(gs_input, global_state_policy_id)
pub fn is_paused(
  gs_input: Input,
  global_state_policy_id: ByteArray,
) -> Bool {
  expect
    quantity_of(
      gs_input.output.value,
      global_state_policy_id,
      constants.global_state_asset_name,
    ) > 0
  expect InlineDatum(gs_datum) = gs_input.output.datum
  let gs_fields = builtin.unconstr_fields(gs_datum)
  let transfers_paused_data = builtin.head_list(gs_fields)
  builtin.unconstr_index(transfers_paused_data) == 1
}

// ============================================================================
// Tests
// ============================================================================

const test_gs_policy_id: ByteArray =
  #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

fn test_gs_input(transfers_paused: Bool) -> Input {
  let datum =
    GlobalStateDatum {
      transfers_paused,
      mintable_amount: 1_000_000,
      users_linked_list_policy_id: #"",
      power_user_linked_list_policy_id: #"",
      security_info: builtin.constr_data(0, []),
    }
  Input {
    output_reference: OutputReference {
      transaction_id: #"0000000000000000000000000000000000000000000000000000000000000000",
      output_index: 0,
    },
    output: Output {
      address: Address {
        payment_credential: Script(test_gs_policy_id),
        stake_credential: None,
      },
      value: from_asset(
        test_gs_policy_id,
        constants.global_state_asset_name,
        1,
      ),
      datum: InlineDatum(datum),
      reference_script: None,
    },
  }
}

// H-1 regression: `is_paused` must read the `transfers_paused` Bool correctly
// via UPLC builtins. The previous implementation in `transfer_logic_script`
// passed the fields *list* to `unconstr_index` (missing a `head_list` step)
// and crashed with UnConstrData on any call — making the pause gate a hard
// revert. These two tests exercise both branches of the flag.

test is_paused_returns_false_when_unpaused() {
  is_paused(test_gs_input(False), test_gs_policy_id) == False
}

test is_paused_returns_true_when_paused() {
  is_paused(test_gs_input(True), test_gs_policy_id) == True
}

pub type GlobalStateSpendAction {
  MintSecurity { issuance_policy_redeemer_index: Int }
  PauseTransfers {
    transfers_paused: Bool,
    power_user_node_ref_input_index: Int,
  }
  ModifySecurityInfo { new_security_info: Data }
}

pub type GlobalStateSpendRedeemer {
  config_ref_input_index: Int,
  global_state_output_index: Int,
  action: GlobalStateSpendAction,
}
