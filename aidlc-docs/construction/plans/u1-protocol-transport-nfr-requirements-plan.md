# NFR Requirements Plan — U1 Protocol / Transport core

Role: Software architect. Determine non-functional requirements + tech-stack choices for U1.
Security Baseline is **ON (blocking)**; PBT is **Partial** (PBT-02/-03/-07/-08/-09 enforced).

**Unit**: U1 Protocol/Transport core — pure codec/validation layer (no I/O, no UI, no network — that's U3).
**Action**: Answer **Q1–Q4** (`[Answer]:`), then approve. Generation starts only after approval.

---

## Plan checkboxes (executed 2026-06-30)
- [x] Generate `aidlc-docs/construction/U1-protocol-transport/nfr-requirements/nfr-requirements.md`
- [x] Generate `aidlc-docs/construction/U1-protocol-transport/nfr-requirements/tech-stack-decisions.md`
- [x] Confirm PBT framework selection (PBT-09) for Swift + Kotlin
- [x] Confirm Security Baseline applicability for U1 (which SECURITY rules apply / N/A)

---

## Context — what NFRs actually matter for U1
U1 is a **pure, deterministic library**: bytes ⇄ domain objects + validation. So:
- **No availability/scaling/network NFRs** (no service, no I/O) — those live in U3.
- **Performance** matters only because screen-mirror frames (64 KiB) flow through `decodeFrame`
  at video rates — the codec must be cheap enough to never be the bottleneck.
- **Security** that applies: SECURITY-05/-13 (validation/safe-deserialization — designed in U1),
  SECURITY-15 (fail-closed — designed in U1), SECURITY-03 (no-PII in any codec logging),
  SECURITY-10 (pin the test-framework deps).
- **Testability** is the headline NFR: round-trip + invariant PBT (PBT-02/-03) with good generators.

---

## Questions

### Q1 — PBT framework per language (PBT-09, mandatory)
- **A) Swift → SwiftCheck · Kotlin → Kotest Property Testing** (recommended) — the standard PBT libs for each; both support custom generators, shrinking, and seeds.
- B) Swift → swift-testing's built-in + hand-rolled generators · Kotlin → Kotest — fewer deps on Swift side, but weaker shrinking.
- C) Defer the Swift choice to Code Generation; lock Kotest now.
- X) Other (describe)

[Answer]:

### Q2 — Unit test runner per language
- **A) Swift → swift-testing (modern) · Kotlin → JUnit5 + Kotest runner** (recommended) — current-gen runners; SwiftCheck/Kotest plug in cleanly.
- B) Swift → XCTest (older, ubiquitous) · Kotlin → JUnit5 + Kotest.
- C) Other (describe)

[Answer]:

### Q3 — Codec performance target (sanity bound, not a hard SLA)
- **A) Control encode/decode ≤ ~1 ms; 64 KiB frame encode/decode ≤ ~2 ms on M1 / modern phone** (recommended) — keeps the codec far below the ~16 ms/frame budget at 60 fps; measured, not gated in CI.
- B) No numeric target — "just don't be the bottleneck", verified by eye if mirroring lags.
- C) Stricter (≤0.5 ms control, ≤1 ms frame) — tighter, may over-constrain the JSON path.
- X) Other (describe)

[Answer]:

### Q4 — Supply-chain handling for U1's test deps (SECURITY-10)
- **A) Pin exact versions via SPM `Package.resolved` (Swift) + Gradle version catalog & lockfile (Kotlin); dependency scanning + SBOM folded into Build & Test** (recommended) — satisfies SECURITY-10 without per-unit CI now.
- B) Pin versions now and also stand up dependency scanning in CI as part of U1.
- X) Other (describe)

[Answer]:

---

## Recommendation in one line
Q1=A · Q2=A · Q3=A · Q4=A  (reply **"go"** to accept all).

---

## Answers (recorded 2026-06-30)
- **Q1 = A** — Swift → SwiftCheck · Kotlin → Kotest Property Testing.
- **Q2 = A** — Swift → swift-testing · Kotlin → JUnit5 + Kotest runner.
- **Q3 = A** — codec perf target: ≤~1 ms control, ≤~2 ms per 64 KiB frame (M1/modern phone); measured, not CI-gated.
- **Q4 = A** — pin exact versions (SPM `Package.resolved` + Gradle version catalog/lockfile); scanning + SBOM at Build & Test.

(User response: "go" — accepted all recommendations. No ambiguities.)
