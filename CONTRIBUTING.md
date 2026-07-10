# Contributing

Thanks for helping improve Android Bridge.

## Project principles

- **Local-first**: no cloud relay, account, or analytics dependency.
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
./scripts/make-macos-app.sh
```

## Before opening a pull request

Run the relevant checks:

```bash
cd android
./gradlew :app:assembleDebug
./gradlew :protocol:test

cd ../mac
swift build

cd ../protocol/swift
swift test
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

Do not add telemetry, remote servers, or persistent content storage without opening a design discussion first.
