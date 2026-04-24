use aiken/builtin
use aiken/collection/pairs
use aiken/crypto.{verify_ed25519_signature}
use aiken/interval.{Finite}
use aiken/primitive/bytearray
use cardano/transaction.{Transaction}
use types/global_state.{GlobalStateDatum}
use types/kyc_proof.{
  KycProof, issuer_vkey_length, offset_network_id, offset_security_policy_id,
  offset_user_kyc_tier, offset_user_pkh, offset_valid_until_ms, payload_length,
  signature_length, tier_invalid, width_security_policy_id, width_user_pkh,
  width_valid_until_ms,
}

/// Verify a KYC proof for a specific expected PKH + security token + network.
///
/// Returns True iff:
///   1. Payload / signature / vkey all have the expected byte lengths.
///   2. Payload's embedded user_pkh matches `expected_user_pkh`.
///   3. Payload's embedded user_kyc_tier is not the invalid sentinel (0x00).
///   4. Payload's embedded valid_until_ms >= tx validity-range upper bound.
///   5. Payload's embedded security_policy_id matches `security_policy_id`.
///   6. Payload's embedded network_id matches `network_id`.
///   7. Proof's issuer_vkey is present in `gs_datum.trusted_entity_vkeys`.
///   8. The Ed25519 signature verifies under `proof.issuer_vkey` over `payload`.
///
/// Any failure returns False. Pure function — all state flows through
/// arguments. Callers typically compose many verify_kyc_proof results with
/// `and` in a fold over inputs.
pub fn verify_kyc_proof(
  proof: KycProof,
  expected_user_pkh: ByteArray,
  gs_datum: GlobalStateDatum,
  security_policy_id: ByteArray,
  network_id: Int,
  tx: Transaction,
) -> Bool {
  let payload = proof.payload
  let signature = proof.signature
  let issuer_vkey = proof.issuer_vkey

  // 1. Structural lengths. Short-circuit if malformed — subsequent slices
  // would otherwise risk out-of-bounds panics.
  let lengths_ok = and {
      bytearray.length(payload) == payload_length,
      bytearray.length(signature) == signature_length,
      bytearray.length(issuer_vkey) == issuer_vkey_length,
    }

  // 2–6. Payload field checks (guarded).
  let fields_ok =
    if lengths_ok {
      let payload_user_pkh =
        bytearray.slice(payload, offset_user_pkh, width_user_pkh)
      let payload_tier = builtin.index_bytearray(payload, offset_user_kyc_tier)
      let payload_ttl =
        bytearray.to_int_big_endian(
          bytearray.slice(payload, offset_valid_until_ms, width_valid_until_ms),
        )
      let payload_policy =
        bytearray.slice(
          payload,
          offset_security_policy_id,
          width_security_policy_id,
        )
      let payload_network =
        builtin.index_bytearray(payload, offset_network_id)

      let ttl_ok =
        when tx.validity_range.upper_bound.bound_type is {
          Finite(tx_upper) -> tx_upper <= payload_ttl
          _ -> False
        }

      and {
        payload_user_pkh == expected_user_pkh,
        payload_tier != tier_invalid,
        ttl_ok,
        payload_policy == security_policy_id,
        payload_network == network_id,
      }
    } else {
      False
    }

  // 7. Issuer membership in TEL.
  let issuer_ok = pairs.has_key(gs_datum.trusted_entity_vkeys, issuer_vkey)

  // 8. Ed25519 signature (only invoked when prior gates pass — saves gas on
  // the sad path where lengths/membership already failed).
  let sig_ok =
    if lengths_ok && issuer_ok {
      verify_ed25519_signature(issuer_vkey, payload, signature)
    } else {
      False
    }

  and {
    lengths_ok,
    fields_ok,
    issuer_ok,
    sig_ok,
  }
}
