# Code Summary — U9 Calls (control on Mac, audio via Bluetooth HFP)

**Status: PARTIAL (◐) — call mappers implemented and tested; telephony/actuation/HFP not implemented.**
Call audio rides Bluetooth HFP at the OS level — never the protocol.

## What exists
- `android/app/src/main/kotlin/com/androidbridge/feature/Mappers.kt` →
  `incomingCall(number,contactName?)`→`call.incoming`, `callAction(action,number?)`→`call.action`,
  `callHistory(records)`→`call.history` (parallel arrays). Pure, JVM-testable.
  Swift equivalents in `BridgeCore/Features.swift` (`incomingCall`, `callAction`).
- `core/LinkLogger.kt` forbids `number`/`contact` field keys in logs (CC-PRIV).

## Tests (passing)
- Kotlin `MappersTest` (call.incoming / call.action validate); Swift `MacCheck` mappers-valid check. ✅

## Not yet implemented / not verified
- Android: `InCallService`/`TelephonyManager` call-state observation, answer/decline/dial actuation,
  contact resolution, call-log reader, `CallPlugin`/`CallService`.
- Mac: caller-ID popup, controls, history view, one-time BT-HFP onboarding hint (U11).
- Telephony + Bluetooth HFP require a **real phone + BT pairing** — not verifiable here.

**Verification: ◐ call mappers green (`MappersTest`/`MacCheck`); telephony/actuation/HFP/Mac UI pending + not hw-verified.**
