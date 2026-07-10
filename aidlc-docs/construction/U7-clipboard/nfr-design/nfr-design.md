# NFR Design — U7 Clipboard

Concrete patterns realizing the U7 NFRs and the applicable Security Baseline rules. Infrastructure
Design is **skipped** for this project (local P2P, no cloud).

---

## Security pattern realization (Baseline ON)
| Rule | Realization in U7 | Status |
|------|-------------------|--------|
| SECURITY-01 (encryption in transit) | `clip.update` travels only the U3 mTLS LAN session (FR-6.3); no other path. | Inherited (U3) |
| SECURITY-05 (input validation) | Inbound `clip.update` validated against its Schema (`text` present, size-capped) before the local clipboard is touched (BR-7). | Compliant |
| SECURITY-13 (safe deserialization) | Parsed via the U1 allowlisted registry; no unsafe/native deserialization of peer bytes. | Inherited (U1) |
| SECURITY-15 (fail-closed) | Malformed inbound → drop + log security event, keep link (BR-7); applying inbound never re-sends (no echo loop, BR-4). | Compliant |
| SECURITY-03 (no-PII logging) | `LinkLogger` forbidden-fields set already drops `text`/`body`; U7 logs only event name + mode + `userInitiated` (BR-9). | Compliant |
| SECURITY-06 (least privilege) | Clipboard access requested only when the Clipboard feature is enabled (U10); no broader grants. | Compliant |
| SECURITY-12 (encryption at rest) | U7 persists no clipboard content; only the sync-mode setting persists via U10. | N/A (content) / Deferred (setting → U10) |
| SECURITY-10 (supply chain) | No new runtime deps; pinning + scan + SBOM at Build & Test. | Deferred (Build&Test) |
| SECURITY-02 / -04 / -07 / -08 / -09 / -11 / -14 | No cloud/web tier, server auth, network intermediary, or alerting. | N/A |

## Privacy pattern (the headline design choice)
- **Default MANUAL push (Q5)**: the policy default is `MANUAL`, so the privacy-preserving behavior is
  the out-of-the-box behavior — clipboard content leaves a device **only** on an explicit user push
  (BR-1/BR-2). `AUTO` is a deliberate opt-in. This realizes NFR-1 (data locality) at the feature level.

## Reliability patterns
- **No echo loop**: applying an inbound `clip.update` sets a guard so the resulting local-clipboard
  change does not itself produce an outbound send (BR-4).
- **Fail-closed apply**: validate before touching the OS clipboard; malformed input is dropped, not
  applied (BR-7).
- **Graceful degradation**: missing clipboard access → feature shown unavailable with a fix-it hint
  (U10), no crash; other features unaffected (NFR-5.2).

## Misuse / abuse consideration (SECURITY-11 design intent)
- A malicious peer cannot silently exfiltrate the local clipboard (sync is inbound-apply only on the
  receiver; outbound requires local policy + push). Oversized `clip.update` is rejected by the U1
  1 MiB cap; large content belongs to U6, not the clipboard.

## Performance pattern
- Single small control message per push; no batching/coalescing needed. Cost bounded by the U1
  control codec (≤ ~1 ms), negligible against any UI interaction.

## Logical components (no infrastructure)
`ClipboardPlugin` (C4) + `ClipboardService` (S5) on each app, depending only on `ConnectionService`
and the pure `ClipboardSyncPolicy`. Sync-mode persistence delegated to U10. No external infrastructure
components — local P2P.
