# NFR Requirements — U9 Calls

U9 is a **control + metadata feature** over the U3 mTLS session, plus an **OS-level Bluetooth HFP audio
path that is outside the protocol entirely**. Transport guarantees are inherited from U1/U3; U9 owns
call observation, actuation, contact resolution, history, and the BT onboarding hint.

---

## NFR-U9.1 Privacy *(headline NFR)*
- **No PII in logs**: phone numbers and contact names are never logged (NFR-1, CC-PRIV, BR-11).
- Call metadata travels only over the **encrypted mTLS link** (NFR-1.2, Inherited U3); audio stays on the
  device-local Bluetooth HFP channel (NFR-1.1 — nothing leaves the two devices).

## NFR-U9.2 Responsiveness
- Caller-ID popup and answer/decline actuation should feel **seamless** (FR-8 intent, NFR-4.2): control
  messages are tiny JSON envelopes, well under the U1 ≤ ~1 ms codec target; perceived latency is the link RTT.

## NFR-U9.3 Testability
- Pure surfaces property-tested: `call.*` round-trip incl. `call.history` count/order preservation (PBT-02),
  number-normalization idempotence (PBT-04 advisory), action-allowlist invariant (PBT-03).
- Telephony/InCallService, contact resolution, and Bluetooth HFP are device/OS IO — **on-device manual testing**.

## NFR-U9.4 Reliability / correctness
- Missing telephony/contacts permission degrades gracefully (number-only caller-ID, feature unavailable) —
  no crash (NFR-5.2, BR-7/BR-8, U10).
- Inbound `call.*` validated + dropped fail-closed (BR-10, Inherited).

## NFR-U9.5 Security (Baseline ON — applicable rules)
| Rule | Applies to U9 | How |
|------|---------------|-----|
| SECURITY-01 (encrypt in transit) | Inherited (U3) | `call.*` metadata rides the mTLS session. |
| SECURITY-05 (input validation) | ✅ | `call.*` payloads validated; `call.action` allowlisted (BR-9). |
| SECURITY-13 (safe deserialization) | Inherited (U1) | Allowlisted registry; no dynamic deserialization. |
| SECURITY-15 (fail-closed) | ✅ | Bad action/permission missing → reject/degrade, never actuate blindly. |
| SECURITY-03 (no-PII logging) | ✅ | Numbers + contact names never logged (BR-11). |
| SECURITY-06 (least privilege) | ✅ | Requests only phone/InCallService + contacts read; deny-by-default. |
| SECURITY-01/-12 (at rest) | ✅ / Deferred | Cached call history (if persisted) goes through SecureStore (Keychain/Keystore). |
| SECURITY-10 (supply chain) | Deferred | Pin deps; scan + SBOM at Build & Test. |
| SECURITY-02/-04/-07/-08/-09/-11/-14 | N/A | No cloud/web tier; mTLS is the authZ boundary (U3). |

## Out of scope for U9 (asserted)
Call audio transport (Bluetooth HFP, OS level), encryption/framing/validation (U1/U3), cloud — **N/A**.
