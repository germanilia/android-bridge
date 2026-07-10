# Business Rules — U10 Settings & Permissions

Decision rules and constraints for toggles, permissions, and degradation. IDs (BR-x) are referenced
by NFR Design and Code Generation.

---

## Feature toggles (FR-9.2 / US-9.2)
- **BR-1**: Every feature in `FeatureId` (NOTIFICATIONS, SMS, FILES, CLIPBOARD, SCREEN, CALLS) is
  independently enable/disable-able; toggling one never affects another.
- **BR-2**: Default state = **all features enabled** (mirrors `PluginRegistry` default). First run with
  no persisted snapshot uses defaults.
- **BR-3**: A toggle change takes effect immediately (plugin activates/deactivates) and is persisted
  before the change is reported complete.

## Permissions & least privilege (FR-9.1 / SECURITY-06)
- **BR-4**: A feature requests **only** the OS permissions in its `FeatureRequirements` set — never a
  broader grant (least privilege).
- **BR-5**: Each permission request is preceded by a **guided rationale** explaining why it's needed
  (US-9.1) before the OS prompt is shown.
- **BR-6**: `PermissionStatus` is always read from the OS (and re-read on resume); a previously granted
  permission is **never assumed** still granted — the user may revoke it in System Settings.

## Effective state & deny-by-default (US-9.3 / SECURITY-06/-15)
- **BR-7**: A feature is **active iff** `enabled(f)` **and** every required permission is `GRANTED`
  (deny-by-default). Any missing/denied permission → feature inactive.
- **BR-8**: When inactive due to a permission, the feature is surfaced as unavailable with a
  **fix-it hint** identifying the missing permission (US-9.3).

## Graceful degradation / fail-closed (US-9.3 / NFR-5.2 / SECURITY-15)
- **BR-9**: A revoked or denied permission disables **only** the affected feature; all other features
  continue to work — **no crash** (partial-failure isolation).
- **BR-10**: A blocked feature's plugin stops emitting and stops handling its message types
  (fail-closed); it does not silently send with a missing permission.

## Persistence (FR-9.3 / US-9.3)
- **BR-11**: `SettingsSnapshot` is persisted via `SecureStore` and restored on launch, so all toggles
  and per-feature config survive restarts.
- **BR-12**: Settings are **encrypted at rest** (Keychain / Keystore + EncryptedSharedPreferences) —
  SECURITY-01/-12; never written as plaintext.

## Privacy (CC-PRIV / SECURITY-03)
- **BR-13**: Permission events and toggle changes logged via `LinkLogger` carry only the
  `FeatureId`/`PermissionId` and result — **never** message bodies, numbers, or contacts.

## Property-based testing (PBT partial)
- **BR-14 (PBT-03)**: `effectiveState(f)` equals `enabled(f) && allRequiredGranted(f)` for all
  toggle×permission combinations (invariant/oracle).
- **BR-15 (PBT-02)**: `decode(encode(SettingsSnapshot)) == SettingsSnapshot` for all generated snapshots.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-9.1 (guided permission grants) | BR-4, BR-5 |
| US-9.2 (independent feature toggles) | BR-1, BR-2, BR-3 |
| US-9.3 (graceful degradation, persistence) | BR-7..BR-12 |
| SECURITY-06 (least privilege) | BR-4, BR-7 |
| SECURITY-15 (fail-closed) | BR-9, BR-10 |
| SECURITY-01/-12 (encryption at rest) | BR-12 |
| CC-PRIV / SECURITY-03 | BR-13 |
