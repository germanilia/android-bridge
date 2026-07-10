# Business Logic Model — U8 Screen Mirror (view-only v1)

Technology-agnostic flows for capture, encode, stream, decode, render, and adaptive bitrate. Transport
(mTLS, framing, reassembly) is U3/U1 — U8 turns the phone screen into an `EncodedFrame` stream and back.

---

## L1. Start mirroring  `startMirror(config)`  (initiated from either app)
1. Requesting side sends `screen.start` with the negotiated `CaptureConfig` + a fresh `streamId`.
2. Android obtains **`MediaProjection`** consent (per-session, US-7.2) — denial aborts, fail-closed.
3. Android shows the **CaptureIndicator** while capture runs (US-7.2).
4. Android opens encoder (**`MediaCodec`** H.264/H.265 per `config.codec`) and `ConnectionManager.openStream(streamId)`.

## L2. Capture + encode loop  (Android)
1. `MediaProjection` → virtual display → encoder input surface.
2. Encoder emits access-units → wrap each as a U1 `Frame` (`streamId`, monotonic `sequence`, bytes).
3. Send frames over the stream; mark the final frame `END_OF_STREAM` on stop.
4. The **AdaptiveBitrateController** (L5) reconfigures encoder bitrate from link-health signals.

## L3. Receive + decode + render  (Mac)
1. U3 delivers ordered frames for `streamId` (gap/dup faults the stream — fail-closed, U1 BR-17).
2. Feed access-units to the platform decoder; render to the live view (U11 window).
3. A missing keyframe after a fault → request restart (re-issue `screen.start`); no partial garbage shown.

## L4. Stop mirroring  `stopMirror(streamId)`
1. Either side sends `screen.stop { streamId }`.
2. Android stops `MediaCodec` + `MediaProjection`, closes the stream, hides the CaptureIndicator.
3. Mac tears down the decoder/view.

## L5. Adaptive bitrate  `adjust(signal) -> bitrate`  *(pure)*
1. Input: a link-health signal (observed latency / throughput / queue depth).
2. Latency above target or throughput falling → decrease `current` toward `min`.
3. Healthy link → increase `current` toward `max` (`= config.maxBitrate`).
4. Always clamp result to `[min, max]`. Side-effect-free → trivially testable.

---

## Data flow (one session)
```
screen.start ─▶ MediaProjection+MediaCodec ─▶ EncodedFrame* ─(U3 mTLS stream)─▶ Mac decoder ─▶ live view
            ▲                                                                                  │
   AdaptiveBitrateController ◀──────────────── link-health signal ◀─────────────────────────────┘
screen.stop ─▶ stop encoder/projection, close stream, hide CaptureIndicator
```

## Testable Properties (PBT-01)
- **AdaptiveBitrateController bounds** *(invariant, PBT-03)*: for any input signal, `min ≤ adjust(signal) ≤ max`.
- **AdaptiveBitrateController direction** *(invariant, PBT-03)*: latency above target never increases the
  bitrate; a healthy signal never decreases it (monotone response in each direction).
- **screen.start / screen.stop round-trip** *(round-trip, PBT-02)*: `decode(encode(m)) == m` for both
  control payloads across generated `CaptureConfig`/`streamId` values (inherits U1 codec round-trip).

The **AdaptiveBitrateController** is the pure, JVM-testable surface (primary PBT target). `MediaProjection`,
`MediaCodec`, and the Mac decoder are **hardware/codec IO** — exercised on-device, not via PBT.
