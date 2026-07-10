# NFR Requirements — U11 Mac App Shell (SwiftUI)

U11 is an **integration/UI unit**. Its NFRs are about responsiveness, accessibility, and native polish;
data/transport NFRs are owned by U1–U10.

---

## NFR-U11.1 Native UX & polish *(headline NFR)*
- Menu-bar-first, lightweight macOS app (NFR-4.x); windows open on demand; menu-bar status always
  reflects live `ConnectionState` (FR-2.3 / US-2.3).
- Native macOS notifications for mirrored notifications (U4) and caller-ID popups (U9) — feels like
  Continuity, not a web wrapper.

## NFR-U11.2 Accessibility (NFR-4.4)
- Keyboard navigation across all surfaces; VoiceOver labels on every interactive control; accessibility
  identifiers for UI-test selection (`data-testid` is N/A in SwiftUI).

## NFR-U11.3 Responsiveness / performance
- UI stays responsive while bulk streams (file/screen, U6/U8) run on background tasks; the screen
  surface renders within the U8 latency budget (NFR-3.1) — the shell only presents decoded frames.
- View-models update on the main actor; no blocking work on the UI thread.

## NFR-U11.4 Reliability — partial-failure isolation
- A blocked/unavailable feature (U10 degradation) renders as unavailable + fix-it hint without
  affecting other windows or crashing the app (NFR-5.2 / US-9.3).
- Connection loss surfaces as "reconnecting" in the menu bar; the UI never hangs on it (U3 owns
  reconnect).

## NFR-U11.5 Security (Baseline ON — applicable rules)
| Rule | Applies | How |
|------|---------|-----|
| SECURITY-01 (encryption in transit) | ⬇ Inherited | All data crosses the U3 mTLS link; the shell never opens its own socket. |
| SECURITY-03 (no-PII logging) | ✅ Compliant | Shell logs only UI/lifecycle events; never bodies/numbers/contacts (BR-9). |
| SECURITY-09 (generic errors) | ✅ Compliant | User-facing errors are generic; no stack traces/internal paths (BR-8). |
| SECURITY-05/-13/-15 (validation / safe-deser / fail-closed) | ⬇ Inherited | Owned by U1 codec + U3 router; the shell renders already-validated data. |
| SECURITY-10 (supply chain) | ⏳ Deferred | SPM `Package.resolved` pinning + scan + SBOM at Build & Test. |
| SECURITY-02/-04/-06/-07/-08/-11/-12/-14 | N/A | No cloud/web tier, network intermediary, server authz, rate limiting, or at-rest storage in the shell (settings persistence is U10). |

## NFR-U11.6 Maintainability / portability
- Clean MVVM separation (view ↔ view-model ↔ service); adding a feature surface = one view + view-model
  bound to an existing service (NFR-6.2/-6.3).

## Out of scope for U11 (asserted)
Wire validation, encryption, persistence, transport — owned by U1–U10. Android UI = U12.
