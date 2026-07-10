# Business Rules — U5 SMS / MMS

Decision rules and constraints for read-only SMS/MMS mirroring. IDs (BR-x) referenced by NFR Design
and Code Generation. Wire types: `sms.received`, `sms.thread`.

---

## Mirroring & history
- **BR-1**: Each incoming SMS/MMS is delivered to the Mac in real time with `address` (sender),
  `body`, `receivedAt`, and MMS `attachments` (US-4.1 / FR-4.1).
- **BR-2**: The Mac can browse conversation history (US-4.2): a thread is requested and returned as
  `sms.thread`.
- **BR-3**: Messages are organized **by conversation/thread** (FR-4.3): grouped by `threadId`, ordered
  by `receivedAt` ascending; grouping preserves total message count and assigns each message to exactly
  one thread.

## Read-only (v1) & scope
- **BR-4**: v1 is **read-only** — no compose/send from the Mac (US-4.3 [Later] / FR-4.4). No `sms.send`
  message is emitted; `SmsSendRequest` is reserved (interface only) so send can be added without redesign.
- **BR-5'**: **RCS is out of scope** — SMS/MMS via Telephony APIs only (FR-4.5).

## Attachments & size
- **BR-6**: MMS attachment ≤ 32 KiB may be base64-inline (U1 BR-5); larger uses a binary frame stream
  (U6 mechanism). Declared length must match actual bytes (U1 BR-4).
- **BR-7**: Inbound `sms.received`/`sms.thread` are validated against their Schema (required fields,
  size caps) before render; violation → drop (Inherited fail-closed, U1 BR-11).

## Privacy (CC-PRIV / SECURITY-03)
- **BR-5**: Message `body`, sender `address` (phone number), and resolved contact names are **never**
  logged. Logs carry only `msgType`, `threadId`, `id`, sizes, reason (`LinkLogger` forbidden-key filter).

## Permissions & degradation (SECURITY-06 / SECURITY-15)
- **BR-8**: U5 requests only **SMS read** (mandatory) and **contacts read** (optional, for name
  resolution, FR-8.7). Least privilege; nothing else.
- **BR-9**: If SMS permission is missing/revoked, mirroring is disabled and shown unavailable (US-9.3);
  if contacts is denied, threads still work using raw addresses (graceful degradation).

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-4.1 (incoming SMS/MMS) | BR-1, BR-6, BR-7 |
| US-4.2 / FR-4.3 (history, threaded) | BR-2, BR-3 |
| US-4.3 [Later] (send) | BR-4 (interface reserved only) |
| FR-4.5 (no RCS) | BR-5' |
| CC-PRIV (no PII in logs) | BR-5 |
| CC-VALID / SECURITY-05/-13/-15 | BR-7 |
| SECURITY-06 (least privilege) | BR-8, BR-9 |
