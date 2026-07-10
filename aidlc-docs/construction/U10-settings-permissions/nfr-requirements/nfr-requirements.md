# NFR Requirements — U10 Settings & Permissions

U10 is a **cross-cutting control plane**: local toggle state, OS-permission queries, derived effective
state, and persistence. No network or bulk data — most service-oriented NFRs live in U3, not here.

---

## NFR-U10.1 Usability / guided setup *(headline NFR)*
- Every permission request is preceded by a plain-language rationale (US-9.1 / NFR-4.x); the user is
  routed to the exact OS setting to grant it.
- A blocked feature always shows a **fix-it hint** naming the missing permission (US-9.3), never a bare
  "unavailable".

## NFR-U10.2 Reliability — partial-failure isolation
- A denied/revoked permission degrades **only** the affected feature; siblings keep working, no crash
  (NFR-5.2 / US-9.3). This is the unit's primary reliability guarantee.
- Effective-state computation is **total + pure** (every toggle×permission combo yields a defined
  state) → deterministic, no flakiness surface.

## NFR-U10.3 Security (Baseline ON — applicable rules)
| Rule | Applies | How |
|------|---------|-----|
| SECURITY-06 (least privilege) | ✅ Compliant | Each feature requests only its `FeatureRequirements`; active iff toggle on **and** perms granted (BR-4/-7). |
| SECURITY-15 (fail-closed) | ✅ Compliant | Missing/revoked permission → feature inactive + isolated; plugin stops emitting (BR-9/-10). |
| SECURITY-01/-12 (encryption at rest) | ✅ Compliant | `SettingsSnapshot` persisted via `SecureStore` (Keychain / Keystore+EncryptedSharedPreferences), never plaintext (BR-12). |
| SECURITY-03 (no-PII logging) | ✅ Compliant | Toggle/permission logs carry only FeatureId/PermissionId + result (BR-13). |
| SECURITY-05/-13 (input validation / safe deser) | ⬇ Inherited | Inbound wire validation is U1 codec + U3 router; U10 reads no untrusted wire input. |
| SECURITY-09 (hardening / generic errors) | ✅ Compliant | Permission failures surface as generic fix-it hints, no internal detail. |
| SECURITY-10 (supply chain) | ⏳ Deferred | Pinning + scan + SBOM at Build & Test. |
| SECURITY-02/-04/-07/-08/-11/-14 | N/A | No cloud/web tier, no network intermediary, no server-side authz/rate-limit/alerting in a local control plane. |

## NFR-U10.4 Maintainability / portability
- `FeatureId` + `FeatureRequirements` are the single source of truth shared by both platforms;
  adding a feature = adding an enum case + its requirement set (NFR-6.2).
- The effective-state function is platform-agnostic pure logic; only the OS permission adapters differ
  per platform.

## NFR-U10.5 Testability (PBT Partial)
- Effective-state invariant/oracle PBT (PBT-03) over all toggle×permission combos.
- Settings-snapshot round-trip PBT (PBT-02).
- Example tests pin each feature's degradation message and the persistence round-trip across restart.

## Out of scope for U10 (asserted)
Throughput, availability, scaling, rate limiting — **N/A** (local control plane). Transport security =
U3; per-feature behavior gated by toggles = U4–U9.
