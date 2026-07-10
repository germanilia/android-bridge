# Domain Entities — U5 SMS / MMS

Technology-agnostic domain model for read-only SMS/MMS mirroring + history (US-4.1, US-4.2).
Builds on U1's `Message`/registry and U3's router. Wire types: `sms.received`, `sms.thread`.

---

## E1. SmsMessage
One incoming text, carried in a `sms.received` payload.

| Field | Type | Notes |
|-------|------|-------|
| `threadId` | integer | Conversation id the message belongs to (groups history, E3). |
| `address` | string | Sender phone number / short code (PII — never logged, BR-5). |
| `body` | string | Message text (PII — never logged). |
| `receivedAt` | integer (epoch ms) | Delivery time; orders messages within a thread. |
| `attachments` | list<AttachmentRef>, optional | MMS parts (FR-4.1). Large blobs go via frame stream (U1 BR-5). |

Matches the live `Mappers.smsReceived(threadId,address,body,receivedAt)` payload (`feature/Mappers.kt`).

## E2. AttachmentRef
MMS part descriptor: `{ mime, size, streamId? | inlineB64? }`. ≤ 32 KiB may inline; larger uses a
binary frame stream (U1 BR-5 / U6 mechanism). v1 carries metadata + bytes; no editing.

## E3. SmsThread
A conversation's history, carried in a `sms.thread` payload (US-4.2 / FR-4.3).

| Field | Type | Notes |
|-------|------|-------|
| `threadId` | integer | Stable conversation key. |
| `participant` | string | Address (resolved to a contact name on the Mac if contacts perm granted). |
| `messages` | list<SmsMessage> | Ordered by `receivedAt` ascending (BR-3). |

## E4. ConversationGrouping (pure transform)
Groups a flat `list<SmsMessage>` into `list<SmsThread>` keyed by `threadId`. Defined here as the
domain concept; it is a **pure function** and the primary U5 invariant PBT target (PBT-03).

## E5. Contact (optional, read-only)
`{ number, displayName?, photo? }` — name resolution on Android needs contacts read (FR-8.7 shared
perm). Optional; absence degrades to showing the raw `address`.

## E6. SmsSendRequest (reserved — US-4.3 [Later])
`{ address, body }` for a future `sms.send` type. Modeled to keep Mac-side send open (FR-4.4); **not**
built in v1.

---

## Relationships
```
Telephony provider ──read──▶ SmsMessage ──sms.received──▶ Mac
list<SmsMessage> ──ConversationGrouping(E4)──▶ list<SmsThread> ──sms.thread──▶ Mac (grouped view)
SmsMessage.address ──resolve(optional)──▶ Contact   (SmsSendRequest reserved for [Later])
```

## Out of scope for U5
- Envelope/codec → **U1**; transport/router → **U3**; perms/toggle → **U10**; thread UI → **U11/U12**.
- **RCS** is explicitly out of scope (SMS/MMS only, FR-4.5). **Sending** is [Later] (US-4.3).
