# Code Summary — U8 Screen Mirror (view-only v1)

**Status: PARTIAL (◐) — transport framing ready and tested; capture/encode/decode not implemented.**
Screen capture, hardware codec, and live render are device/GPU/Xcode-bound and not verifiable here.

## What exists
- Bulk framing reused from U6/U1: `core/StreamAssembler.kt` (`StreamChunker`/`StreamReassembler`, tested)
  + `FrameCodec`/`Frame` carry encoded frames; Swift equivalents in `BridgeCore/Features.swift`.
- `screen.start` / `screen.stop` are registered `MessageType`s in both protocol impls.

## Tests (passing)
- The framing round-trip is covered by `StreamTest` (Kotlin) and `MacCheck` (Swift). ✅

## Not yet implemented / not verified
- Android: `MediaProjection` capture, `MediaCodec` H.264/H.265 encoder, on-phone capture indicator,
  `ScreenMirrorPlugin`/`ScreenMirrorService`, adaptive-bitrate controller (the one pure piece, JVM-testable
  once written).
- Mac/Swift: `VideoToolbox` decode + live render view (needs Xcode).
- The ≤~80 ms latency target (NFR-3.1) is a real-device/LAN measurement — not verified here.
- Reserved [Later] control path (US-7.3) is interface-only.

**Verification: ◐ frame transport green; capture/encode/render pending + not hw-verified.**
