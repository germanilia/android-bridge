# DDP2 macOS update client code-generation summary

## Result

The native Mac app now discovers only the fixed latest stable GitHub Release, validates the DDP1 contract, compares strict semantic versions, asks before downloading, verifies the canonical DMG and checksum, opens only a verified DMG, and preserves the installed app on failure.

## Created

- `mac/Sources/BridgeCore/MacUpdate.swift`
- `mac/Sources/BridgeApp/MacUpdateController.swift`
- `mac/Tests/BridgeCoreTests/MacUpdateTests.swift`

## Modified

- `mac/Sources/BridgeApp/main.swift`
- `mac/Sources/BridgeApp/BridgeApp.swift`

## Trust controls

- Fixed repository and latest-stable endpoint.
- Stable tag, schema, version code, minimum platform, canonical names, sizes, and hashes validated.
- Initial and redirected URLs restricted to clean HTTPS GitHub hosts.
- Consent precedes checksum and DMG retrieval.
- Bounded streaming download, exact size, checksum agreement, and SHA-256 required.
- Temporary paths are updater-owned and narrowly cleaned.
- A read-only DMG mount and strict code-sign verification must match the pinned distribution designated requirement before AppKit receives `VerifiedMacUpdate`.
- Automatic failures do not block startup; manual checks expose actionable status.

## Validation

- Terra initial generation: three approved checks passed.
- One focused Terra repair hardened redirects, download buffering, checksum format, path ownership, cleanup, automatic native open, and negative tests.
- Sol reviewed every DDP2 file and independently ran `swift test` and `swift build`.
- Result after independent security review: 51 XCTest tests passed, including 11 Mac updater tests, plus existing property checks; Swift build passed.
- Public distribution identity app build and mounted DMG validation passed during integrated validation.

## Remaining runtime evidence

Live update discovery and DMG opening require the first published stable Release. Fixture tests prove acceptance and rejection behavior before publication.
