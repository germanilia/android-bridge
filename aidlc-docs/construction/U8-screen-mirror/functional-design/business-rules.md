# Business Rules — U8 Screen Mirror (view-only v1)

Decision rules, validation, and constraints for screen mirroring. IDs (BR-x) are referenced by NFR
Design and Code Generation. Transport/validation rules are inherited from U1/U3.

---

## Scope & capture
- **BR-1**: v1 is **view-only** — no tap/type-back input injection (US-7.3 is **[Later]**). A control
  channel seam is reserved in the design but not implemented.
- **BR-2**: Capture requires **`MediaProjection` consent each session** (US-7.2); consent denied →
  abort start, fail-closed (no silent capture).
- **BR-3**: While capture is active the phone shows a **visible CaptureIndicator** (US-7.2); it is
  cleared on `screen.stop` or stream teardown.
- **BR-4**: Either device may start or stop mirroring (`screen.start` / `screen.stop`, US-7.2).

## Encoding & framing
- **BR-5**: Frames are encoded H.264/H.265 via `MediaCodec` per `CaptureConfig.codec` (FR-7.1).
- **BR-6**: Encoded access-units are carried as **binary frames** on a screen stream — never base64-inline
  (they exceed the 32 KiB inline cap; U1 BR-5/BR-6).
- **BR-7**: Frames on a screen `streamId` are delivered in `sequence` order; a gap/dup **faults that
  stream** (drop + restart), other streams + the link stay alive (U1 BR-16/BR-17, U3 fail-closed).

## Performance
- **BR-8**: Target **end-to-end latency ≤ ~80 ms** on a healthy 5 GHz LAN with **adaptive bitrate** (NFR-3.1).
- **BR-9**: Adaptive bitrate output is always within `[min, max]` (`max = CaptureConfig.maxBitrate`);
  rising latency lowers it, a healthy link raises it.
- **BR-10**: Per-frame codec/transport work must stay well under the **~16 ms/frame @ 60 fps** budget
  (ties to the U1 codec target, NFR-U1.2).

## Recovery
- **BR-11**: After a stream fault, the renderer waits for a fresh **keyframe** (re-issue `screen.start`)
  rather than displaying partial/garbage frames.

## Privacy (CC-PRIV / SECURITY-03)
- **BR-12**: Frame contents are **never logged**; logs carry only `streamId`, sizes, codec, and
  start/stop/fault events.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-7.1 (live mirror on Mac) | BR-4..BR-10 |
| US-7.2 (start/stop + capture indicator) | BR-2, BR-3, BR-4 |
| US-7.3 (control) **[Later]** | BR-1 (seam reserved, not built) |
| NFR-3.1 (latency ≤ ~80 ms, adaptive) | BR-8, BR-9, BR-10 |
| CC-VALID (validate inbound `screen.*`) | Inherited (U1 codec + U3 router) |
| CC-PRIV (no PII in logs) | BR-12 |
| SECURITY-15 (fail-closed) | BR-2, BR-7, BR-11 |
