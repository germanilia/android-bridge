# NFR Requirements — U12 Android App Shell (Compose)

U12 is an **integration/UI unit** plus the always-on link host. NFRs cover background liveness,
responsiveness, accessibility, and portability; data/transport NFRs are owned by U1–U10.

---

## NFR-U12.1 Background link liveness *(headline NFR)*
- A **foreground service** keeps the link alive while backgrounded with an ongoing notification
  (FR-2.2 / US-2.2); `START_STICKY` so the OS restarts it.
- One shared `AppContainer` graph between UI and service — no duplicate Core/service instances.

## NFR-U12.2 Responsiveness / performance
- Compose UI stays responsive while bulk streams (file/screen, U6/U8) run on background coroutines;
  status updates via `StateFlow` on the main dispatcher.
- The shell only renders decoded frames/state; it adds no per-message work on the UI thread.

## NFR-U12.3 Reliability — partial-failure isolation
- A blocked feature (U10 degradation) renders unavailable + fix-it hint without crashing the app or
  affecting other screens (NFR-5.2 / US-9.3).
- Connection loss shows "reconnecting"; the UI never blocks on it (U3 owns retry).

## NFR-U12.4 Portability (NFR-6.1 / US-10.3)
- **Generic Android public APIs only** — no DeX/Flow/Knox; runs on any Android 13+ (minSdk 33,
  targetSdk/compileSdk 34 per `android/app/build.gradle.kts`).

## NFR-U12.5 Accessibility (NFR-4.4)
- Compose `testTag` + `contentDescription` on interactive elements; standard TalkBack support;
  touch-target sizing per Material guidelines.

## NFR-U12.6 Security (Baseline ON — applicable rules)
| Rule | Applies | How |
|------|---------|-----|
| SECURITY-01 (encryption in transit) | ⬇ Inherited | All data crosses the U3 mTLS link; the shell opens no socket of its own. |
| SECURITY-03 (no-PII logging) | ✅ Compliant | Shell logs only UI/lifecycle via `LinkLogger`; no bodies/numbers/contacts (BR-11). |
| SECURITY-09 (generic errors) | ✅ Compliant | User-facing errors are generic; no stack traces (BR-10). |
| SECURITY-06 (least privilege) | ✅ Compliant | Manifest declares only the permissions features need; routed via U10. |
| SECURITY-05/-13/-15 (validation / safe-deser / fail-closed) | ⬇ Inherited | Owned by U1 codec + U3 router; the shell renders validated data. |
| SECURITY-01/-12 (encryption at rest) | ⬇ Inherited | Settings/trust persist via `AndroidSecureStore` (U2/U10), not the shell. |
| SECURITY-10 (supply chain) | ⏳ Deferred | Gradle version catalog + lockfile + scan + SBOM at Build & Test. |
| SECURITY-02/-04/-07/-08/-11/-14 | N/A | No cloud/web tier, network intermediary, server authz, rate limiting, or cloud alerting in the shell. |

## NFR-U12.7 Maintainability
- MVVM + manual DI (`AppContainer`); adding a feature screen = one Composable + ViewModel bound to an
  existing service (NFR-6.2/-6.3).

## Out of scope for U12 (asserted)
Wire validation, encryption, persistence, transport — owned by U1–U10. Mac UI = U11.
