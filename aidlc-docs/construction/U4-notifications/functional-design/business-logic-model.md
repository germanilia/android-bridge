# Business Logic Model — U4 Notifications

Technology-agnostic flows for capturing, filtering, mirroring, and rendering notifications
(read-only v1). No transport here (U3) and no envelope/codec (U1) — U4 maps an OS notification to a
`notif.posted` message and renders the peer's.

---

## L1. Capture (Android)  `onNotificationPosted(sbn) -> void`
1. Extract **plain values** from `StatusBarNotification`: `pkg`, `title`, `text`, `postedAt`
   (no Android types cross into core — keeps mappers JVM-testable).
2. If `pkg` is not allowed by the **AppAllowlist** (L3) → drop, do not send (US-3.2).
3. Build `notif.posted` via `Mappers.notification(pkg,title,text,postedAt)`.
4. Hand to `ConnectionManager.send(message)` over the mTLS link.
5. Log a capture **event only** — `pkg` + `msgType`, never `title`/`text` (CC-PRIV / BR-5).

## L2. Render (Mac)  `displayNotification(payload) -> void`
1. Receive `notif.posted` from `MessageRouter.route()` (already validated, U3/U1).
2. Validate payload Schema (required `pkg`,`title`,`text`,`postedAt`; size caps) → on fail drop (BR-6).
3. Render as a native macOS notification + entry in the notifications feed (US-3.1).
4. v1 shows **no** Dismiss/Reply control (US-3.3 [Later]).

## L3. Allowlist filter  `isAllowed(pkg) -> bool`
- `pkg ∈ allowed` → true; else → `default` (**DENY** in v1, BR-3).
- Pure predicate; the policy set is loaded once from `SecureStore` and mutated by U10 settings.

## L4. Reserved action path (US-3.3 [Later])
- A `NotificationAction` would travel Mac→phone as a future `notif.action` type and resolve via
  `NotificationKey`. Interface reserved (E3/E4); **not** implemented — no v1 behavior.

---

## Data flow (one mirror)
```
phone notif ──L1 extract+filter──▶ notif.posted ──U3 mTLS send──▶ Mac ──L2 validate+render──▶ feed
                     └─ denied pkg ──▶ dropped (no send)
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| Notif payload round-trip (PBT-02) | Round-trip | `decode(encode(m)) == m` for generated `notif.posted` messages (envelope verified in U1; here the **payload generator** covers `pkg/title/text/postedAt` incl. empty/Unicode strings). |
| Allowlist filter invariant (PBT-03) | Invariant | For any package set + policy, `filter(input)` ⊆ `input` and equals exactly `{p ∈ input : isAllowed(p)}`; count never grows. |
| Filter idempotence (advisory) | Idempotence | `filter(filter(x)) == filter(x)` — advisory under PARTIAL PBT, not blocking. |

The mapper (`Mappers.notification`) and the allowlist predicate are pure → JVM-testable with Kotest.
Mac render (L2) is UI/IO → no PBT (example-based only).
