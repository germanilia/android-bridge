# Business Rules — U4 Notifications

Decision rules and constraints for read-only notification mirroring. IDs (BR-x) are referenced by
NFR Design and Code Generation. Wire type: `notif.posted`.

---

## Mirroring & filtering
- **BR-1**: Every posted Android notification from an **allowed** app is mirrored to the Mac with
  `pkg`, `title`, `text`, `postedAt`, shown as a native notification + feed entry (US-3.1).
- **BR-2**: Only apps in the `AppAllowlist` mirror; the choice **persists** across restarts via
  `SecureStore` (US-3.2 / FR-9.3).
- **BR-3**: Allowlist default for an **unknown** package is **DENY** (deny-by-default). Rationale:
  noisy/unknown apps must be opted in, matching US-3.2's "don't clutter my Mac" intent and least
  privilege (SECURITY-06). The owner allows apps explicitly in U10 settings.

## Read-only (v1)
- **BR-4**: v1 provides **no** Dismiss or quick-reply from the Mac (US-3.1/FR-3.3). No Mac→phone
  action message is emitted.
- **BR-5**: The data model reserves `NotificationKey`/`NotificationAction` so US-3.3 (actions) can be
  added later **without redesign**; these carry no v1 behavior.

## Payload & size
- **BR-6**: Inbound `notif.posted` is validated against its Schema (required `pkg`,`title`,`text`,
  `postedAt`; per-field size caps) before render; violation → drop (Inherited fail-closed, U1 BR-11).
- **BR-7**: An app icon may be base64-inline only if ≤ 32 KiB (U1 BR-5); otherwise omitted in v1
  (no frame stream for icons).

## Privacy (CC-PRIV / SECURITY-03)
- **BR-8**: Notification `title`/`text` (which can contain message bodies) are **never** logged. Logs
  carry only `pkg`, `msgType`, `id`, sizes, reason — enforced by `LinkLogger` forbidden-key filter.

## Fail-closed (SECURITY-15)
- **BR-9**: A malformed/unknown inbound notification message is dropped + logged; the link stays up
  (Inherited from U1 codec + U3 router).
- **BR-10**: If notification-listener access is missing/revoked, U4 degrades gracefully — no capture,
  feature shown unavailable (U10/US-9.3); other features keep working.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-3.1 (mirror notifications) | BR-1, BR-6, BR-7 |
| US-3.2 (per-app allowlist, persists) | BR-2, BR-3 |
| US-3.3 [Later] (actions) | BR-5 (interface reserved only) |
| CC-PRIV (no PII in logs) | BR-8 |
| CC-VALID / SECURITY-05/-13/-15 | BR-6, BR-9 |
| SECURITY-06 (least privilege) | BR-3, BR-10 |
