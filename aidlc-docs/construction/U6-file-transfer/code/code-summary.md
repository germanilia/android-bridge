# Code Summary — U6 File Transfer

**Status: PARTIAL (◐) — transport primitive done and tested.** The chunk/reassemble core is implemented
in both languages with round-trip property tests; the transfer feature (plugin/service, file I/O, UIs)
is not yet implemented and end-to-end transfer is not verified here (needs two devices).

## What exists
- **Kotlin** — `core/StreamAssembler.kt`: `StreamChunker.chunk(streamId, data, 64 KiB)` → ordered frames
  with trailing `END_OF_STREAM`; `StreamReassembler.accept` enforcing ordering (gap/dup/wrong-stream fault).
- **Swift** — `mac/Sources/BridgeCore/Features.swift`: same `StreamChunker`/`StreamReassembler`.
- Reuses U1 `Frame`/`FrameCodec` for bulk framing.

## Tests (passing)
- Kotlin `StreamTest`: **PBT-03 round-trip** (chunk→reassemble over arbitrary payloads), END_OF_STREAM on
  last frame, fault on sequence gap. Run: `./gradlew :app:testDebugUnitTest` ✅
- Swift `MacCheck`: chunk/reassemble round-trip (300 property cases) + gap fault. ✅

## Not yet implemented / not verified
- `FileTransferPlugin`/`FileTransferService`: offer/accept handshake, streamId allocation, progress,
  destination resolution + atomic temp+rename write; Android share-sheet/receive; Mac drag-and-drop + progress UI.
- Actual file transfer over the LAN requires the U3 transport + two devices — not verified here.

**Verification: ◐ chunk/reassemble round-trip green both languages; transfer feature pending + not hw-verified.**
