## What this changes

## Checks run

<!-- CI runs these on every PR, but please confirm locally too. -->

- [ ] `swift test --package-path mac`
- [ ] `swift test --package-path protocol/swift`
- [ ] `cd android && ./gradlew :protocol:test`
- [ ] `cd android && ./gradlew :app:testDebugUnitTest`

## Protocol changes

- [ ] Not a protocol change
- [ ] Updated `protocol/PROTOCOL.md`, both Kotlin and Swift `Model.swift`/`Model.kt`, and the wire vectors

## Security-sensitive areas touched

<!-- pairing, certificate pinning, TLS, file handling, clipboard, screen capture, remote control, OS permissions — or "none" -->
