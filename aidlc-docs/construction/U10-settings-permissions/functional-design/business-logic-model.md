# Business Logic Model — U10 Settings & Permissions

Technology-agnostic flows for feature toggling, permission requests, graceful degradation, and
persistence. Orchestrated by `SettingsService` (S5) + `PermissionService` (S6) over
`SettingsPermissions` (C7) and `PluginRegistry` (B6). No transport here — settings are local.

---

## L1. Toggle a feature  `setFeatureEnabled(f, on)`
1. Update the `FeatureToggle` for `f` in the in-memory `PluginRegistry` (`enable`/`disable`).
2. Recompute `EffectiveFeatureState(f)` (L4).
3. Persist the updated `SettingsSnapshot` via `SecureStore` (L5).
4. Notify the plugin via `PluginRegistry` so it activates/deactivates (US-9.2).

## L2. Request a permission  `requestPermission(p)`
1. Show the guided rationale for `p` (US-9.1) before invoking the OS prompt.
2. Invoke the platform permission API; await the user's OS-level decision.
3. Re-query `PermissionStatus` (the OS is authoritative — never cache the grant as truth).
4. Recompute effective state for every feature that requires `p` (L4).

## L3. Query permission status  `permissionStatus(p)`
Read-through to the OS each time (and on app resume), because the user may revoke a grant in System
Settings while the app runs (US-9.3). Drives the degradation decision.

## L4. Compute effective feature state  `effectiveState(f)`  *(pure)*
```
required   = FeatureRequirements[f]
allGranted = required.all { permissionStatus(it) == GRANTED }
return  !enabled(f)            -> DISABLED_BY_USER
        !allGranted           -> BLOCKED_MISSING_PERMISSION(firstMissing)
        else                  -> ACTIVE
```
A feature is **active only if** the user enabled it **and** all its required permissions are granted
(deny-by-default, SECURITY-06). This is the unit's core decision and the primary PBT surface.

## L5. Persist / restore settings
- `persist()`: serialize `SettingsSnapshot` → `SecureStore.put` (encrypted at rest, SECURITY-01/-12).
- `restore()` on launch: `SecureStore.get` → deserialize → seed `PluginRegistry`; absent → defaults
  (all features enabled). Settings survive restarts (US-9.3 / FR-9.3).

## L6. Graceful degradation  (US-9.3 / SECURITY-15 fail-closed)
When `permissionStatus` flips to `DENIED`/`RESTRICTED` for a required permission:
- the affected feature is marked `BLOCKED_MISSING_PERMISSION` and shown unavailable **with a fix-it
  hint**; its plugin stops emitting/handling traffic (fail-closed),
- **all other features keep working** — one missing grant never crashes the app or disables siblings.

---

## Data flow (toggle + degradation)
```
UI ─toggle─▶ SettingsService.setFeatureEnabled ─▶ PluginRegistry ─▶ effectiveState (L4)
                                                       │
OS perm change ─▶ PermissionService.permissionStatus ─┘ ─▶ recompute ─▶ UI (available / fix-it hint)
SettingsService ─▶ SecureStore (persist/restore)
```

## Testable Properties (PBT-01)
- **Effective-state decision — invariant / oracle (PBT-03)**: for all combinations of toggle ∈ {on,off}
  and permission sets, `effectiveState(f) == ACTIVE` **iff** `enabled(f) && allRequiredGranted(f)`;
  otherwise it reports the precise reason. A reference truth-table is the oracle.
- **Settings snapshot round-trip (PBT-02)**: `decode(encode(snapshot)) == snapshot` over generated
  snapshots (all `FeatureId`s, arbitrary toggle states + per-feature config) — pure, JVM-testable.
- **Toggle idempotence (PBT-04, advisory under Partial)**: `disable(disable(f)) == disable(f)`;
  enabling an already-enabled feature is a no-op. Non-blocking in Partial mode.
- `PluginRegistry` and the `effectiveState` function are pure and JVM-testable; OS permission APIs
  are IO (not PBT — exercised on-device).
