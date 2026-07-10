# Security Communication Decision

**Date**: 2026-07-02T10:57:38Z
**Status**: Approved for implementation

## Problem

The running Android Bridge app used plaintext TCP between the Mac and Android phone. That exposed clipboard contents, transferred files, call metadata, SMS metadata, and notifications to passive LAN sniffing.

## Approved Easiest Secure Solution

Use the Mac as a TLS server and Android as a pinned TLS client:

```text
Android app  ->  TLS encrypted socket  ->  Mac app
```

## Security Properties

- LAN traffic is encrypted with TLS.
- The Mac presents a self-signed certificate.
- Android pins the advertised Mac certificate fingerprint when the user pairs.
- Android refuses to connect if the Mac certificate fingerprint differs from the pinned fingerprint.
- Existing Device-Link protocol messages continue to run inside the encrypted socket.

## Tradeoffs

This is not full mutual TLS yet.

- Android verifies the Mac at the TLS layer.
- Mac does not yet verify an Android client certificate at the TLS layer.
- This is still a major improvement over plaintext and is the smallest implementation that protects data from passive LAN observers.

## Process

1. Review current communication code.
2. Confirm plaintext usage in Android `PlainLink` and Mac `NWConnection(..., using: .tcp)`.
3. Choose pinned TLS client/server as smallest secure increment.
4. Disable plaintext active connection path.
5. Build and install both apps after implementation.

## Future Hardening

- Full mutual TLS with client certificate verification on Mac.
- Explicit pairing confirmation code/QR instead of trusting Bonjour-advertised fingerprints.
- Remove or quarantine demo plaintext transport from production builds.
