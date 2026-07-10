# Code Summary — U7 Clipboard

**Status: DONE (logic) — unit tests green.** The sync-decision policy (default MANUAL) and the
`clip.update` mapper are implemented in both languages and tested. OS clipboard I/O + manual-push UI live
in the shells and need a device/Xcode to verify.

## What exists
- **Kotlin** — `feature/ClipboardSync.kt`: `ClipboardSyncMode {MANUAL, AUTO}` (default **MANUAL** per Q5)
  + `ClipboardSyncPolicy.shouldSend(userInitiated)`; `feature/Mappers.clipboard(text)` → `clip.update`.
- **Swift** — `mac/Sources/BridgeCore/Features.swift`: same `ClipboardSyncPolicy` + `Mappers.clipboard`.

## Tests (passing)
- Kotlin `ClipboardSyncTest` (manual default only sends on explicit push; auto always sends) +
  `MappersTest` (`clip.update` validates). Run: `./gradlew :app:testDebugUnitTest` ✅
- Swift `MacCheck`: clipboard-default-manual + mappers-valid checks. ✅

## Not yet implemented / not verified
- `ClipboardPlugin`/`ClipboardService` wiring the policy to Android `ClipboardManager` / Mac `NSPasteboard`
  with a no-echo-loop guard; the explicit manual-push action (U11/U12); mode persistence via U10.
- Real clipboard read/set on phone + Mac and the LAN round-trip are not verified here.

**Verification: ✅ policy + mapper green both languages (`ClipboardSyncTest`/`MappersTest`/`MacCheck`).**
