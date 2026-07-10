# Business Logic Model — U9 Calls

Technology-agnostic flows for caller-ID, answer/decline/dial, and history. **Audio is Bluetooth HFP at
the OS level — never modeled here.** U9 maps call state ⇄ `call.*` control messages and actuates the phone.

---

## L1. Incoming call → caller-ID on Mac  (US-8.2)
1. Android observes a `RINGING` `CallEvent` (`InCallService`/`TelephonyManager`).
2. `resolveContact(number)` adds name/photo **if** contacts permission granted (else number only).
3. Build `call.incoming` via `Mappers.incomingCall(number, contactName?)` → `ConnectionManager.send`.
4. Mac shows the caller-ID popup (U11).

## L2. Answer / decline from Mac  (US-8.3)
1. User clicks Answer/Decline → Mac sends `call.action { action }` (`answer`/`decline`).
2. Android validates `action` against the **allowlist** (BR-9), then actuates via `InCallService`.
3. On answer, **audio routes via Bluetooth HFP** (already paired in onboarding) — outside the protocol.

## L3. Place a call from Mac  (US-8.4)
1. User dials/picks a contact → Mac sends `call.action { action: dial, number }`.
2. Android places the call; audio routes via Bluetooth HFP.

## L4. Call history  (US-8.5)
1. Android `loadHistory()` reads the call log → `[CallRecord]`.
2. `Mappers.callHistory(records)` serializes to parallel arrays → `call.history`.
3. Mac renders incoming/outgoing/missed with names/numbers + timestamps.

## L5. One-time Bluetooth onboarding  (US-8.1)
- Onboarding (U11) guides the user to pair the Mac as a **Bluetooth Hands-Free device once**, so call
  audio "just works" afterward. U9 only surfaces the hint/state; the pairing is an OS action.

## L6. Number normalization  `normalize(number) -> number`  *(pure)*
- Canonicalize a phone number (strip formatting, normalize country/trunk prefix) so caller-ID matching
  and de-dup are stable. Side-effect-free → testable. (Used by contact resolution + history.)

---

## Data flow
```
CallEvent(RINGING) ─▶ resolveContact ─▶ call.incoming ─(U3 mTLS)─▶ Mac popup
Mac Answer/Decline/Dial ─▶ call.action{allowlisted} ─(U3)─▶ phone actuates ─▶ audio via BT HFP (OS)
call log ─▶ callHistory(parallel arrays) ─▶ call.history ─▶ Mac history list
```

## Testable Properties (PBT-01)
- **`call.*` round-trip** *(round-trip, PBT-02)*: `decode(encode(m)) == m` for `call.incoming`,
  `call.action`, and `call.history` across generated payloads; **`call.history` preserves record count
  and order** through the parallel-array encode/decode.
- **Number normalization idempotence** *(idempotence, PBT-04 — advisory under Partial)*:
  `normalize(normalize(n)) == normalize(n)` for all generated numbers.
- **Action allowlist invariant** *(invariant, PBT-03)*: only `answer`/`decline`/`dial` are accepted; any
  other `action` is rejected.

The `Mappers` (call.incoming/action/history) and the `normalize` function are the pure, JVM-testable
surface. `InCallService`/`TelephonyManager`, contact resolution, and Bluetooth HFP are **device/OS IO**.
