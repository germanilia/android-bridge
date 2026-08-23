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

## 4. Meeting-stop responsiveness (MCAL1 — manual)

- **Target:** visible recording state clears within one second after Stop.
- Start a meeting with at least one completed chunk, press Stop, and time until the UI changes from `Recording` to `Finalizing`.
- While final title/summary work runs, switch tabs, browse another meeting, and start a new short recording. None should wait for the prior finalization queue.
- Calendar permission/query latency is excluded from local note readiness; it must appear only as passive Calendar status.

## Status / honesty
- **Runnable here:** the U1 codec micro-benchmark (CPU-only; the codecs already build and pass tests).
  No benchmark numbers are recorded yet — the harnesses above must be run on target hardware to claim
  the targets.
- **Not runnable here:** U8 latency and U6 throughput require two real devices, a 5 GHz LAN, and screen
  capture — no phone / second device on this build machine. Targets are documented for a properly
  equipped environment. (Codec micro-benchmarks themselves can run locally.)

## 5. Second Brain visible refresh

- Both visible Brain tabs use a three-second check interval.
- Mac computes Markdown metadata revision first and skips the Python tree reload when unchanged.
- Android rescans the granted SAF tree only while the Brain view is visible.
- Hardware verification should confirm scrolling/editing remains responsive with the current 79-note Mac tree and a comparable phone folder.
- If refresh exceeds one second on the phone, capture folder size and provider timing before changing the interval or adding indexing.

## 6. Update-path bounds

- Metadata is bounded to 1 MiB and manifests to 64 KiB on both clients.
- Artifact downloads stream to disk with the manifest byte count as a hard upper bound; full DMG/APK buffering is prohibited.
- On representative hardware, measure automatic discovery separately from artifact transfer and verify startup remains interactive throughout.
- CI publication time is observed but not release-gated beyond existing tests, SBOM generation, vulnerability scan, and artifact validation.
