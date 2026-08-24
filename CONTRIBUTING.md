# Contributing

Thanks for helping improve Android Bridge.

## Project principles

- **Local-first**: the local network is the primary transport. The optional relay in `relay/` is
  self-hosted by the user — never a vendor-operated service — and the apps must work fully
  without it. No account and no analytics dependency, ever.
- **Privacy-preserving**: do not log message contents, clipboard text, phone numbers, SMS bodies, or file contents.
- **Explicit consent**: respect Android and macOS permission prompts.
- **Small changes**: prefer focused pull requests with a clear user-visible outcome.
- **Cross-platform protocol discipline**: update both Kotlin and Swift protocol code when changing wire messages.

## Development setup

```bash
# Android
cd android
./gradlew :app:assembleDebug

# macOS
cd mac
swift build
```

`mac/scripts/make-macos-app.sh` is **not** part of routine development: by default it installs into
`/Applications/AndroidBridge.app` and relaunches the app. It also requires a code-signing identity —
set `CODESIGN_IDENTITY` to your own self-signed "Code Signing" certificate. To build the bundle
without touching `/Applications`:

```bash
NO_INSTALL=1 CODESIGN_IDENTITY="<your identity>" ./scripts/make-macos-app.sh
```

## Before opening a pull request

Run the relevant checks:

CI runs these on every pull request. Run them locally first:

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :protocol:test
./gradlew :app:testDebugUnitTest

cd ../mac
swift test

cd ../protocol/swift
swift test

# Only if you changed the relay server
cd ../../relay
./gradlew test
```

If you changed protocol messages, also update:

- `protocol/PROTOCOL.md`
- `protocol/kotlin/src/main/kotlin/com/androidbridge/protocol/Model.kt`
- `protocol/swift/Sources/DeviceLinkProtocol/Model.swift`
- protocol vectors/tests when applicable

## Security-sensitive changes

Please call out any change that affects:

- pairing
- certificate pinning
- TLS setup
- file handling
- clipboard handling
- screen capture
- remote control / input injection
- OS permissions

Relay changes need extra care: the relay terminates TLS, so it sees forwarded frames. State plainly in
the pull request what a relay operator can observe after your change.

Do not add telemetry, third-party-hosted servers, or persistent content storage without opening a design
discussion first.
