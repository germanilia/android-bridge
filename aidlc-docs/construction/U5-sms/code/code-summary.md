# Code Summary — U5 SMS / MMS (read-only v1)

**Status: PARTIAL (◐).** The pure `sms.received` mapper is implemented and tested; the Telephony reader,
thread-history loader, and Mac threaded UI are not yet implemented.

## What exists
- `android/app/src/main/kotlin/com/androidbridge/feature/Mappers.kt` → `Mappers.smsReceived(threadId,address,body,receivedAt)`
  — pure OS→`sms.received` mapper (no Android types), JVM-testable.

## Tests (passing)
- Kotlin `MappersTest` asserts `Mappers.smsReceived` produces a valid `sms.received` message.
  Run: `./gradlew :app:testDebugUnitTest` ✅

## Not yet implemented / not verified
- Telephony broadcast receiver / content-provider read of incoming SMS/MMS; `loadThread` history →
  `sms.thread` (US-4.2); conversation-grouping transform; MMS attachments (depends on U6 streams);
  contact resolution; send over `ConnectionManager`; Mac `renderThread`/`renderIncoming` (U11).
- Telephony/contacts reads require **SMS/contacts permissions on a real device** — not verified here.
- Reserved [Later] send (US-4.3) is interface-only.

**Verification: ◐ mapper green (`MappersTest`); Telephony read + Mac UI not yet implemented / not hw-verified.**
