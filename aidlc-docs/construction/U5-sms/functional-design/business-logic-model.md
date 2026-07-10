# Business Logic Model — U5 SMS / MMS

Technology-agnostic flows for read-only SMS/MMS mirroring + history. No transport (U3) or codec (U1)
here — U5 maps Telephony reads to `sms.received`/`sms.thread` and renders the peer's, grouped by thread.

---

## L1. Incoming SMS/MMS (Android)  `onSmsReceived(msg) -> void`
1. Extract plain values from the Telephony message: `threadId`, `address`, `body`, `receivedAt`
   (+ MMS `attachments`). No Android types cross into core (JVM-testable mappers).
2. Build `sms.received` via `Mappers.smsReceived(threadId,address,body,receivedAt)`.
3. For MMS, attach `AttachmentRef`s: ≤ 32 KiB inline, else open a frame stream (U1 BR-5).
4. `ConnectionManager.send(message)` over mTLS.
5. Log **event only** — `msgType`, `threadId`; never `address`/`body` (CC-PRIV / BR-5).

## L2. Load thread history (Android)  `loadThread(threadId) -> SmsThread`
1. Read the conversation's messages from the Telephony content provider.
2. Apply `ConversationGrouping` (L4) / order by `receivedAt`.
3. Emit `sms.thread` to the Mac (US-4.2).

## L3. Render (Mac)  `renderIncoming(payload)` / `renderThread(thread)`
1. Receive validated `sms.received` / `sms.thread` from `MessageRouter.route()`.
2. Validate payload Schema (required fields, size caps) → drop on fail (Inherited fail-closed).
3. Resolve `address` → contact name if available (E5), else show the raw address.
4. Display in the Messages window grouped by conversation (US-4.2 / FR-4.3). **No compose box** (v1).

## L4. ConversationGrouping  `group(messages) -> threads`  *(pure)*
- Partition `list<SmsMessage>` by `threadId`; within each thread, sort by `receivedAt` ascending.
- Total message count is preserved; every message lands in exactly one thread (invariant, BR-3).

## L5. Reserved send path (US-4.3 [Later])
- `SmsSendRequest` would travel Mac→phone as a future `sms.send` type. Interface reserved (E6);
  **not** implemented — v1 is strictly read-only (BR-4).

---

## Data flow
```
phone SMS ──L1 map──▶ sms.received ──U3 mTLS──▶ Mac ──L3 validate+resolve+render──▶ thread view
open thread ──L2 read+L4 group──▶ sms.thread ──U3──▶ Mac (history)
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| SMS payload round-trip (PBT-02) | Round-trip | `decode(encode(m)) == m` for generated `sms.received`/`sms.thread` messages; payload generator covers `threadId/address/body/receivedAt`, empty + Unicode bodies. |
| Thread-grouping invariant (PBT-03) | Invariant | For any `list<SmsMessage>`: Σ messages across output threads == input count; every message appears in exactly one thread; threads keyed by `threadId`; within a thread `receivedAt` is non-decreasing. |
| Grouping idempotence (advisory) | Idempotence | `group(flatten(group(x))) == group(x)` — advisory under PARTIAL PBT. |

`Mappers.smsReceived` and `ConversationGrouping` are pure → JVM-testable with Kotest. The grouping
transform is **planned, not yet implemented**. Mac render (L3) is UI/IO → example-based only.
