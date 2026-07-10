# Business Rules — U9 Calls

Decision rules, validation, and constraints for call control. IDs (BR-x) are referenced by NFR Design
and Code Generation. Transport/validation are inherited from U1/U3.

---

## Audio (the defining constraint)
- **BR-1**: **Call audio is carried by Bluetooth HFP at the OS level — NEVER a protocol message**
  (P2 decision, FR-8.4). Android exposes no API for live cellular call audio without root.
- **BR-2**: Onboarding guides a **one-time Bluetooth Hands-Free pairing** of the Mac so calls "just
  work" afterward (US-8.1, FR-8.5). U9 surfaces the hint/state only; pairing is an OS action.

## Control & metadata
- **BR-3**: Incoming calls surface on the Mac as caller-ID (`call.incoming`) with number and, if contacts
  permission is granted, resolved name + photo (US-8.2, FR-8.7).
- **BR-4**: The Mac can **answer / decline** a ringing call (US-8.3) and **dial** a number/contact
  (US-8.4) via `call.action`; the phone actuates the action.
- **BR-5**: Call **history** shows incoming/outgoing/missed with names/numbers + timestamps (US-8.5).
- **BR-6**: `call.history` is serialized as **parallel arrays** (`numbers[]/types[]/timestamps[]`);
  index `i` is one record, count + order preserved.

## Permissions & resolution
- **BR-7**: Contact-name resolution requires **contacts read** permission (FR-8.7); absent it, caller-ID
  shows the number only (graceful degradation, U10).
- **BR-8**: Call observation/actuation requires phone/`InCallService` permissions; absent them the
  feature is shown unavailable (U10, SECURITY-15).

## Safety
- **BR-9**: `call.action.action` is restricted to an **allowlist** `{answer, decline, dial}` — an unknown
  action is rejected (no arbitrary actuation from a wire message; SECURITY-05/-13).
- **BR-10**: Inbound `call.*` messages are validated against their Schema and **dropped fail-closed** on
  any violation (Inherited from U1 codec + U3 router).

## Privacy (CC-PRIV / SECURITY-03)
- **BR-11**: **Phone numbers and contact names are NEVER logged.** `LinkLogger` carries only event names,
  `call.*` type, and non-PII fields. (`LinkLogger` already forbids `number`/`contact` keys.)

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-8.1 (one-time BT setup) | BR-2 |
| US-8.2 (caller-ID) | BR-3, BR-7 |
| US-8.3 (answer/decline) / US-8.4 (dial) | BR-4, BR-9 |
| US-8.5 (history) | BR-5, BR-6 |
| FR-8.4 (audio via HFP) | BR-1 |
| CC-VALID (validate inbound) | BR-9, BR-10 (Inherited U1/U3) |
| CC-PRIV (no PII in logs) | BR-11 |
| SECURITY-15 (fail-closed) | BR-8, BR-9, BR-10 |
