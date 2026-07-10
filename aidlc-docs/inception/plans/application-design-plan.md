# Application Design Plan — android_bridge

Role: Software architect. This plan defines **how** we'll produce the high-level component & service design (component boundaries, interfaces/method signatures, service orchestration, dependencies). Detailed business logic comes later in per-unit Functional Design.

Source: `requirements.md` (FR/NFR) + `user-stories/stories.md` (epics E1–E10).
Locked context: SwiftUI Mac · Kotlin/Compose Android · local mTLS over LAN · Bluetooth HFP for call audio · generic Android 13+ · security ON · PBT partial.

Please answer **Q1–Q4** (fill the letter after each `[Answer]:`), then approve. Generation starts only after approval.

---

## Proposed Architecture (default recommendation)

- **Three logical components**: (1) **Mac app** (SwiftUI), (2) **Android app** (Kotlin/Compose + foreground service), (3) a **shared Device-Link Protocol** (the contract between them — message schemas + transport framing), mirrored in each codebase.
- **One secure connection, multiplexed**: a single **mutual-TLS** session over the LAN carries all control traffic as **typed, length-prefixed messages**; bulk data (file transfer, screen frames) uses **binary stream framing** on the same session (or a secondary stream) to avoid blocking small control messages.
- **Feature-plugin layout**: each capability (notifications, SMS, files, clipboard, mirroring, calls) is a **self-contained module/"plugin"** on both sides, plugged into a shared core (connection, pairing, message router). This keeps features independent (INVEST/units) and is contributor-friendly.
- **Service layer per app**: a small set of services orchestrate the plugins — e.g., `ConnectionService`, `PairingService`, `MessageRouter`, plus per-feature services.
- **Wire format**: control = **length-prefixed JSON** messages (simple, debuggable, easy round-trip PBT); bulk = **raw binary frames** with a small header. One documented schema is the source of truth.

---

## Execution Checklist (runs after approval)
- [x] `components.md` — component definitions, responsibilities, interfaces (Mac app, Android app, shared protocol; feature plugins within each)
- [x] `component-methods.md` — method signatures + I/O types for core + per-feature components (business rules deferred to Functional Design)
- [x] `services.md` — service definitions + orchestration (ConnectionService, PairingService, MessageRouter, per-feature services)
- [x] `component-dependency.md` — dependency matrix, communication patterns, data-flow diagram (validated Mermaid)
- [x] `application-design.md` — consolidated design doc
- [x] Validate completeness & consistency against FR/NFR + stories

---

## Questions

### Q1 — Connection & multiplexing model
A) **Single mTLS session, multiplexed typed messages + binary stream framing for bulk** (recommended) — one connection, simplest trust model, channels for control vs. file/screen

B) **One control connection + separate on-demand connections** for high-bandwidth features (file/screen) — more sockets, more code, isolates big transfers

C) Let it emerge during Functional Design

X) Other (describe after [Answer]:)

[Answer]:

### Q2 — Shared protocol: how is the schema maintained?
A) **One documented schema, hand-implemented in each language** (Swift + Kotlin), control msgs = length-prefixed JSON (recommended — simplest, no codegen toolchain, easy to read/test)

B) **Language-neutral IDL with codegen** (e.g., Protobuf) generating Swift + Kotlin types — more upfront tooling, stricter contract, binary-efficient

C) JSON now, revisit Protobuf later if perf demands it

X) Other (describe after [Answer]:)

[Answer]:

### Q3 — Feature module organization
A) **Feature-plugin modules on a shared core** (recommended) — each feature isolated on both sides; great for units + open-source contributions

B) **Layered monolith per app** — features as internal layers, fewer module boundaries

C) Hybrid — plugins for the big features (mirroring, calls, files), inline for small ones (clipboard)

X) Other (describe after [Answer]:)

[Answer]:

### Q4 — LAN discovery mechanism
A) **mDNS / Bonjour** (recommended) — native: Apple `Network`/`NWBrowser` on Mac, `NsdManager` on Android; zero-config

B) **UDP broadcast** — simple, self-rolled, but more edge cases on some networks

C) mDNS primary with UDP-broadcast fallback — most robust, more code

X) Other (describe after [Answer]:)

[Answer]:

---

## My recommendation in one line
Q1 = A · Q2 = A · Q3 = A · Q4 = A (reply "go" to accept all).

---

## Answers (recorded 2026-06-27)
- **Q1 = A** — Single mTLS session, multiplexed typed messages + binary stream framing for bulk
- **Q2 = A** — One documented schema, length-prefixed JSON, hand-implemented per language
- **Q3 = A** — Feature-plugin modules on a shared core
- **Q4 = A** — mDNS / Bonjour discovery

(User response: "go" — accepted all recommendations. No ambiguities.)
