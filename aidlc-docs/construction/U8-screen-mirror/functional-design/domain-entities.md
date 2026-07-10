# Domain Entities — U8 Screen Mirror (view-only v1)

Technology-agnostic domain model for live screen mirroring. Android captures + encodes; Mac decodes +
renders. View-only in v1 (US-7.3 control is **[Later]** — a control-channel seam is reserved, not built).
Frames ride the U1 `FrameCodec`/binary streams over the U3 mTLS session.

---

## E1. CaptureConfig
Negotiated capture parameters (mirrors `ScreenMirrorPlugin.CaptureConfig`, component-methods C5).

| Field | Type | Notes |
|-------|------|-------|
| `maxBitrate` | int (bps) | Upper bound for the adaptive controller (E6). |
| `codec` | enum {H264, H265} | `MediaCodec` encoder selection (FR-7.1). |
| `targetLatencyMs` | int | End-to-end latency goal; default ~80 ms (NFR-3.1). |

## E2. EncodedFrame
One encoded video access-unit emitted by the encoder, carried as a U1 `Frame` payload on a screen stream.

| Field | Type | Notes |
|-------|------|-------|
| `streamId` | u32 | The screen stream's id (U1 `FrameHeader`). |
| `sequence` | u32 | Monotonic per stream; ordering enforced by U3 reassembly. |
| `bytes` | binary | Encoded NAL units; **always framed**, never base64-inline (U1 BR-5, >32 KiB). |
| `keyframe` | bool | Whether this access-unit is an IDR/keyframe (decoder sync point). |

## E3. screen.start (control message)
Request to begin mirroring. `payload`: `{ codec, maxBitrate, targetLatencyMs, streamId }`. Validated
against its registered Schema (SECURITY-05). `screen.start`/`screen.stop` are registered `MessageType`s.

## E4. screen.stop (control message)
Request to end mirroring for a `streamId`. `payload`: `{ streamId }`.

## E5. CaptureIndicator
On-phone state shown while `MediaProjection` capture is active (US-7.2). Not a wire entity — a local
UI/OS affordance toggled by capture start/stop.

## E6. AdaptiveBitrateController
Pure controller that maps a link-health signal to an encoder bitrate (NFR-3.1).

| Field | Type | Notes |
|-------|------|-------|
| `min` | int (bps) | Floor; output never below this. |
| `max` | int (bps) | Ceiling; output never above this (`= CaptureConfig.maxBitrate`). |
| `current` | int (bps) | Current target; clamped to `[min, max]`. |

`adjust(signal) -> bitrate`: rising latency / falling throughput lowers `current`; healthy link raises it,
always within `[min, max]`. This is the unit's pure, JVM-testable surface (PBT target, see business-logic-model).

---

## Relationships
```
screen.start ──opens──▶ screen stream (streamId) ──carries──▶ EncodedFrame (U1 Frame)*
AdaptiveBitrateController ──drives──▶ encoder bitrate ──bounded by──▶ CaptureConfig.maxBitrate
screen.stop ──closes──▶ screen stream ──toggles──▶ CaptureIndicator off
```

## Out of scope for U8 (owned elsewhere)
- Binary framing/ordering/reassembly → **U1** (`FrameCodec`) + **U3** (`StreamReassembler`).
- mTLS transport of the stream → **U3**.
- Input injection (tap/type back into the phone) → **[Later]** US-7.3 (Accessibility/ADB), not built.
- The Mac render window + start/stop controls → **U11** Mac shell.
