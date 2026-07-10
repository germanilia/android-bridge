# Domain Entities — U4 Notifications

Technology-agnostic domain model for read-only notification mirroring (US-3.1, US-3.2).
Builds on U1's `Message`/registry and U3's router. Wire type: `notif.posted`.

---

## E1. NotificationPayload
The mirrored content of one Android notification, carried in a `notif.posted` message payload.

| Field | Type | Notes |
|-------|------|-------|
| `pkg` | string | Source app package id (e.g. `com.whatsapp`). Drives allowlist + Mac grouping. |
| `title` | string | Notification title (may be empty). |
| `text` | string | Notification body text (may be empty). |
| `postedAt` | integer (epoch ms) | When the phone posted it (US-3.1 timestamp). |
| `icon` | string (base64), optional | Small app icon ≤ 32 KiB inline (U1 BR-5); larger/absent → omitted in v1. |

Matches the live `Mappers.notification(pkg,title,text,postedAt)` payload (`feature/Mappers.kt`).

## E2. AppAllowlist
Per-app mirroring policy (US-3.2 / FR-3.4). Persisted via `SecureStore` (survives restart, FR-9.3).

| Field | Type | Notes |
|-------|------|-------|
| `allowed` | set<string> | Package ids permitted to mirror. |
| `default` | AllowlistDefault | `DENY` for an unknown package (see BR-3). |

## E3. NotificationKey
Stable identity of a posted notification (`pkg` + platform key/id). Lets a future [Later] action
(US-3.3) reference a specific notification for dismiss/quick-reply — defined now, unused in v1.

## E4. NotificationAction (reserved — US-3.3 [Later])
`{ key: NotificationKey, action: DISMISS | REPLY, text? }`. Modeled to keep the protocol/data model
open per FR-3.3; **not** built in v1 (no Mac→phone path wired).

---

## Relationships
```
StatusBarNotification (Android OS) ──extract──▶ NotificationPayload ──(allowlist filter)──▶ notif.posted Message ──U3 link──▶ Mac feed
NotificationKey ◀──identifies── NotificationPayload   (NotificationAction reserved for [Later])
```

## Out of scope for U4 (owned elsewhere)
- Envelope/codec/validation → **U1**. Transport/router → **U3**. Per-feature toggle + permission
  prompts → **U10**. Mac feed window chrome → **U11**. Android settings UI → **U12**.
