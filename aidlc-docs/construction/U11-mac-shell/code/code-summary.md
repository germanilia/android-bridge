# Code Summary — U11 Mac App Shell (SwiftUI)

**Status: DONE — a runnable `AndroidBridge.app` is produced and launches.** The SwiftUI app and shared
Swift core build via SwiftPM; `mac/scripts/make-macos-app.sh` assembles a Mach-O arm64, ad-hoc-signed
`.app` (verified: launches then quits cleanly). Logic is verified by `swift test` (XCTest + SwiftCheck)
with `MacCheck` kept as an Xcode-free smoke runner. (Xcode 26.6 is installed.)

## What exists
- `mac/Sources/BridgeApp/BridgeApp.swift` — `@main` SwiftUI app: `AppModel` (`ObservableObject`) +
  `ContentView` rendering device identity + fingerprint, **paste-QR pairing**, paired-device list with
  unpair, and per-feature `Toggle`s. Mirrors the Android shell.
- `mac/Sources/BridgeCore/` — shared core (Core.swift, Pairing.swift, Features.swift) consumed by the app.
- `mac/Package.swift` — `BridgeCore` library + `AndroidBridge` (SwiftUI app) + `MacCheck` executables;
  path-depends on `protocol/swift`.

## Build / test (passing)
- `cd mac && swift build` → compiles + links `BridgeCore`, the `AndroidBridge` SwiftUI executable, and `MacCheck`. ✅
- `cd mac && swift test` → 10 XCTest tests incl. a SwiftCheck stream round-trip property (100 cases). ✅
- `cd mac && swift run MacCheck` → 13 core checks (Xcode-free fallback). ✅
- `mac/scripts/make-macos-app.sh` → `mac/dist/AndroidBridge.app`; `open dist/AndroidBridge.app` launches it. ✅

## Not yet implemented / not verified
- Menu-bar `MenuBarExtra`, separate feature windows (Messages/Files/Screen/Calls), drag-and-drop receive,
  caller-ID popup, full onboarding sequencing; Keychain-backed `SecureStore` (app uses `InMemorySecureStore`);
  the live `NWBrowser`/`NWConnection` mTLS transport (U3).
- Distribution signing/notarization (the `.app` is ad-hoc signed for local launch, not notarized).

**Verification: ✅ `swift test` (XCTest+SwiftCheck) green; runnable `AndroidBridge.app` builds and launches.**
