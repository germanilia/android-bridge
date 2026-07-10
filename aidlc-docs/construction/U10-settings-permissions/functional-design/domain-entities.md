# Domain Entities — U10 Settings & Permissions

Technology-agnostic domain model for per-feature toggles, OS-permission state, and graceful
degradation. Cross-cuts U4–U9; implemented natively per platform (Swift on Mac, Kotlin on Android).
The `FeatureId` enum mirrors the real Kotlin scaffold in `core/PluginRegistry.kt`.

---

## E1. FeatureId (registry enum)
The set of toggleable feature plugins (FR-9.2).

`NOTIFICATIONS`, `SMS`, `FILES`, `CLIPBOARD`, `SCREEN`, `CALLS`

Single source of truth shared by `PluginRegistry` (B6) and `SettingsPermissions` (C7).

## E2. Permission
An OS permission a feature depends on, namespaced per platform.

| Field | Type | Notes |
|-------|------|-------|
| `id` | PermissionId (enum) | e.g. `NOTIFICATION_ACCESS`, `READ_SMS`, `READ_CONTACTS`, `SCREEN_CAPTURE`, `FOREGROUND_SERVICE`, `BLUETOOTH` (Android); `NOTIFICATIONS`, `LOCAL_NETWORK`, `BLUETOOTH` (macOS). |
| `platform` | Platform | `mac` / `android`. |
| `rationale` | string (i18n key) | Why the feature needs it — shown in the guided prompt (US-9.1). |

## E3. PermissionStatus
`GRANTED` · `DENIED` · `NOT_DETERMINED` · `RESTRICTED`. Queried from the OS; never persisted as
truth (the OS is authoritative — we re-query on resume).

## E4. FeatureToggle
User intent for a feature: `{ feature: FeatureId, enabled: bool }`. Default `enabled = true`
(matches `PluginRegistry` default). Persisted in `SettingsSnapshot`.

## E5. FeatureRequirements
Static map `FeatureId → [PermissionId]` — the minimal permission set each feature needs
(least privilege, SECURITY-06). E.g. `NOTIFICATIONS → [NOTIFICATION_ACCESS]`,
`CALLS → [BLUETOOTH, READ_CONTACTS, ...]`, `SMS → [READ_SMS, READ_CONTACTS]`.

## E6. EffectiveFeatureState (derived — not stored)
Computed availability of a feature: `effectiveState(f) = enabled(f) AND allGranted(requirements(f))`.
Values: `ACTIVE` · `DISABLED_BY_USER` · `BLOCKED_MISSING_PERMISSION(permId)` (drives the fix-it
hint, US-9.3). Recomputed whenever a toggle or permission changes.

## E7. SettingsSnapshot (persisted)
Serializable record of all user-controlled settings: feature toggles + per-feature config that other
units own (e.g. clipboard sync mode, file destination, notification allowlist references). Persisted
via `SecureStore` (B5) so it survives restarts (US-9.3 / FR-9.3) and is encrypted at rest
(SECURITY-01/-12).

---

## Relationships
```
FeatureId ──requires──▶ [Permission] ──has──▶ PermissionStatus
FeatureToggle(FeatureId) ─┐
                          ├─▶ EffectiveFeatureState  (derived)
PermissionStatus ─────────┘
SettingsSnapshot ──contains──▶ [FeatureToggle] (+ per-feature config owned by U4–U9)
```

## Out of scope for U10 (owned elsewhere)
- The *behavior* gated by each toggle → the feature units (U4–U9).
- Concrete OS permission APIs (`NotificationListenerService` grant, `MediaProjection` consent,
  `ClipboardManager`, `TCC`/`CBCentralManager`) → invoked here but defined by the platform.
- UI of the Settings screen / prompts → U11 (Mac) and U12 (Android) shells.
