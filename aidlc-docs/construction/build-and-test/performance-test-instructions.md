# Performance Test Instructions — android_bridge

Performance targets are **measured, not CI-gated** (decision E-Q3). Two layers matter: the U1 codec
micro-benchmark (runs today, pure CPU) and the U8 screen-mirroring end-to-end latency (needs
hardware).

---

## 1. Codec micro-benchmark (U1 — runs on this machine)
**Targets (NFR-U1.2):** on an M1 Mac / modern Android phone —
- control `encode` + `decode` ≤ **~1 ms** per message;
- `encodeFrame` + `decodeFrame` ≤ **~2 ms** per 64 KiB frame.

**Rationale:** keeps codec work far under the ~16 ms/frame budget at 60 fps screen mirroring (U8).

**How to measure (lightweight, not a CI gate):**
- **Swift:** add a timing loop in/near `ProtocolCheck` — encode then decode a representative `Message`
  and a 64 KiB `Frame` N=10k times, report mean/p99 (`swift build -c release` first; measure the
  release build).
- **Kotlin:** a JMH harness or a simple warm-up + averaged loop over `MessageCodec`/`FrameCodec`;
  measure on a release build, after JIT warm-up.
- **Anti-DoS check (BR-2):** confirm an oversize *declared* length is rejected before allocation —
  decode time for a hostile 4-byte oversize prefix stays O(1), not proportional to the claimed size.

## 2. Screen-mirroring latency (U8 — needs hardware)
**Target (NFR-3.1):** end-to-end latency ≤ **~80 ms** on a healthy 5 GHz LAN, with adaptive bitrate
sustaining a smooth frame rate.
- **Method:** display a high-resolution timer on the phone, mirror to the Mac, photograph both
  screens together, and read the delta; repeat across bitrates and confirm the adaptive controller
  keeps latency near target as available throughput changes.
- **Pure-logic part testable now:** the adaptive-bitrate controller invariant (output bitrate stays
  within [min,max], reacts in the correct direction) is a PBT target (PBT-03) once that controller is
  implemented — independent of hardware.

## 3. File-transfer throughput (U6 — needs hardware)
- Transfer a large file over the LAN both directions; confirm it saturates the link (not Bluetooth,
  FR-5.4) and that progress is monotonic. The chunk/reassemble correctness is already PBT-covered;
  throughput is the hardware-bound measurement.

## Status / honesty
- **Runnable here:** the U1 codec micro-benchmark (CPU-only; the codecs already build and pass tests).
  No benchmark numbers are recorded yet — the harnesses above must be run on target hardware to claim
  the targets.
- **Not runnable here:** U8 latency and U6 throughput require two real devices, a 5 GHz LAN, and screen
  capture — no phone / second device on this build machine. Targets are documented for a properly
  equipped environment. (Codec micro-benchmarks themselves can run locally.)
