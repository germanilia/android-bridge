# NFR Design — U1 Protocol / Transport core

Concrete realization of the U1 NFR Requirements. U1 is a **pure, deterministic codec library**
(bytes ⇄ domain objects + validation), so the patterns here are about *correctness, fail-closed
validation, and testability* — not availability/scaling (those are U3). IDs reference
`functional-design/business-rules.md` (BR-x) and `nfr-requirements/nfr-requirements.md` (NFR-U1.x).

---

## 1. Testability pattern (NFR-U1.1) — dual-language property harness

| Concern | Pattern realized |
|---------|------------------|
| Round-trip proof | `decode(encode(m)) == m` (PBT-02) and `decodeFrame(encodeFrame(h,p)) == (h,p)` + self-delimiting framing (PBT-03), run in **both** languages. |
| Generators (PBT-07) | Domain generators over all `MessageTypes.known`, payload maps, frame headers + arbitrary byte payloads. |
| Shrinking + seeds (PBT-08) | Kotlin: Kotest shrinks + logs seed. Swift: the seeded `PropertyRunner` prints `seed` + failing iteration for replay. |
| Example complement (PBT-10) | Known-good/known-bad vectors per failure mode (unknown type, oversize, version mismatch, END_OF_STREAM). |

**Environment-forced deviation (must carry through Build & Test):** this machine has only the Swift
**Command Line Tools** (no Xcode), so **XCTest and SwiftCheck are unavailable**. The Swift side
therefore uses a **dependency-free seeded property-test harness** — `PropertyHarness.swift`
(`PRNG` SplitMix64 + `PropertyRunner`) driven by the `ProtocolCheck` executable
(`swift run ProtocolCheck`). It satisfies PBT-09's *intent* (custom generators + shrinking-lite via
minimal-iteration reporting + seeded reproducibility). On a machine with Xcode you would swap this
harness for **SwiftCheck + XCTest** with no change to the properties. Kotlin uses **Kotest Property
Testing** as originally planned.

## 2. Performance pattern (NFR-U1.2)

- **Bounded work before allocation**: `decode` rejects an oversize *declared* length (> 1 MiB) before
  allocating or parsing (BR-2) — caps worst-case CPU/memory on hostile input (anti-DoS).
- **Single-pass, copy-minimal codecs**: big-endian header read/write via index math
  (`readU32BE`/`writeU32BE`), one slice for the payload — keeps control `encode`/`decode` ≤ ~1 ms and
  a 64 KiB frame ≤ ~2 ms (target, measured not CI-gated).
- **No reflection / dynamic dispatch on the hot path**: native `Codable` / `kotlinx.serialization`.

## 3. Reliability pattern (NFR-U1.3) — total, fail-closed codecs

- **Typed total functions**: every input yields a valid typed `Message`/`Frame` or a typed
  `ProtocolError`/`ProtocolException` (BR-13). No partial/unchecked object escapes the boundary.
- **Fail-closed**: control decode/validation failure → caller drops + logs, link stays up (BR-14);
  `VERSION_MISMATCH` is the one case surfaced to U3 to reject the link (BR-7/-15); frame fault →
  abort that `streamId` only (BR-16/-17). Realized as thrown typed errors callers catch.
- **Determinism**: pure, side-effect-free → no flakiness surface; reproducible by construction.

## 4. Security pattern realization (Baseline ON)

| Rule | Status | How realized in U1 |
|------|--------|--------------------|
| SECURITY-05 (input validation) | **Compliant** | `validate()` checks version, registry membership, non-empty `id`, payload schema before any consumer sees the message (BR-10..-13). Size bound enforced pre-parse (BR-2). |
| SECURITY-13 (safe deserialization) | **Compliant** | JSON parsed into a fixed typed `Message` via an **allowlisted** `MessageTypes` registry; no polymorphic/dynamic/native deserialization of untrusted bytes. |
| SECURITY-15 (fail-closed) | **Compliant** | Drop+log on malformed, abort stream on frame fault, reject link on version mismatch (BR-2, BR-14..-17). |
| SECURITY-03 (no-PII logging) | **Compliant** | Typed errors + (in app layers) `LinkLogger` carry only `type`/`id`/`streamId`/sizes/reason — never payload, numbers, contacts, tokens (BR-18). U1 errors deliberately hold no payload content. |
| SECURITY-10 (supply chain) | **Deferred** | Pin Kotest (Gradle) + (where available) SwiftCheck exact versions; the Swift codec has **zero runtime third-party deps** (native `Codable`). Scanning + SBOM happen at Build & Test. |
| SECURITY-01/-02/-04/-06/-07/-08/-09/-11/-12/-14 | **N-A** | A pure codec library has no storage, network intermediary, web headers, IAM, auth, persistence, or alerting surface. mTLS encryption-in-transit is owned by U3. |

## 5. Maintainability / portability (NFR-U1.5)

- `protocol/PROTOCOL.md` is the canonical spec; Swift (`protocol/swift`) and Kotlin
  (`protocol/kotlin`) impls are kept in lockstep and **proven equivalent** by the shared
  cross-language wire vectors (`protocol/vectors/control-messages.jsonl`) decoded by both suites.
- Identical public API shape in both languages (`encode`/`decode`/`encodeFrame`/`decodeFrame`/
  `validate`), zero dependency on app/UI/transport layers (NFR-6.2).

## Out of scope for U1 (asserted)
Availability, scaling, throughput-under-load, rate limiting, DR/failover — **N-A** (no running
service). Connection resilience / auto-reconnect / mTLS — **U3**.

---

> **Update (2026-07-01 — Xcode 26.6 installed):** The earlier "Command Line Tools only / no XCTest / seeded-harness-instead-of-SwiftCheck" wording above is superseded. Swift tests now run via **XCTest + SwiftCheck** (`swift test`) — the PBT-09-specified framework — with the dependency-free `ProtocolCheck`/`MacCheck` harness kept only as an Xcode-free fallback. A runnable macOS `.app` is produced via `mac/scripts/make-macos-app.sh`.
