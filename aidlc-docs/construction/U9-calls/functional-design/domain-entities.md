# Domain Entities — U9 Calls

Technology-agnostic domain model for phone-call control on the Mac. **Call audio rides Bluetooth HFP at
the OS level and is NEVER a protocol message** (P2 decision, FR-8.4) — the link carries only call
metadata + control. Android observes/actuates calls; Mac shows caller-ID, controls, and history.

---

## E1. CallInfo (caller-ID)
Incoming-call identity surfaced on the Mac (`call.incoming`).

| Field | Type | Notes |
|-------|------|-------|
| `number` | string | Caller's number (E.164-ish; never logged — CC-PRIV). |
| `contactName` | string, optional | Resolved if contacts permission granted (US-8.2, FR-8.7). |
| `photo` | binary/uri, optional | Contact photo if available. |

## E2. CallEvent
Observed call-state change from `InCallService`/`TelephonyManager`: `{ state ∈ {RINGING, ACTIVE,
DIALING, DISCONNECTED}, number? }`. Drives `call.incoming` and Mac UI state.

## E3. CallAction (control message, `call.action`)
Action the Mac asks the phone to perform. `payload`: `{ action, number? }` (mirrors `Mappers.callAction`).

| `action` | Meaning | Story |
|----------|---------|-------|
| `answer` | Answer the ringing call | US-8.3 |
| `decline` | Decline/reject the ringing call | US-8.3 |
| `dial` | Place a call to `number` | US-8.4 |

`action` is restricted to this **allowlist** (no arbitrary actuation; see business-rules BR-9).

## E4. CallRecord + call.history
One history entry `{ number, type ∈ {incoming, outgoing, missed}, timestamp }` (US-8.5). The
`call.history` payload uses **parallel arrays** `{ numbers[], types[], timestamps[] }` (per
`Mappers.callHistory`) — index `i` is one record.

## E5. Contact
Resolution input/output: `resolveContact(number) -> Contact?` `{ name, photo? }` (needs contacts perm).

## E6. call.incoming (control message)
`payload`: `{ number, contactName? }` (mirrors `Mappers.incomingCall`) → Mac caller-ID popup.

---

## Relationships
```
CallEvent(RINGING) ──maps to──▶ call.incoming ──▶ Mac caller-ID popup
Mac controls ──▶ call.action {answer|decline|dial} ──▶ phone actuates (InCallService)
CallRecord* ──serialize──▶ call.history (parallel arrays) ──▶ Mac history list
audio ════ Bluetooth HFP (OS level) ════  ✗ never a protocol message
```

## Out of scope for U9 (owned elsewhere)
- **Call audio** → Bluetooth HFP at the OS level (FR-8.4); one-time BT pairing guided by onboarding (U11).
- Validation/transport of `call.*` → U1 codec + U3 router (fail-closed).
- Mac caller-ID popup / controls / history windows → **U11** Mac shell.
- Per-feature toggle + permission prompts → **U10**.
