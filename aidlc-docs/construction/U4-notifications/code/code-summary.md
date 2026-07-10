# Code Summary — U4 Notifications (read-only v1)

**Status: PARTIAL (◐).** The pure `notif.posted` mapper is implemented and tested; the
`NotificationListenerService` compiles into the APK. Capture + Mac rendering need a device/Xcode and are
not verified here.

## What exists
- `android/app/src/main/kotlin/com/androidbridge/feature/Mappers.kt` → `Mappers.notification(pkg,title,text,postedAt)`
  — pure OS→`notif.posted` mapper (no Android types), JVM-testable.
- `android/app/src/main/kotlin/com/androidbridge/android/NotificationListener.kt` — `NotificationListenerService`
  that extracts title/text/postedAt, builds the message via the mapper, and logs capture with **pkg + msgType
  only** (CC-PRIV). Registered in `AndroidManifest.xml` with the BIND permission + intent filter.

## Tests (passing)
- Kotlin `MappersTest` asserts `Mappers.notification` produces a `notif.posted` message that `validate()`
  accepts. Run: `./gradlew :app:testDebugUnitTest` ✅

## Not yet implemented / not verified
- App allowlist (`isAllowed(pkg)`) + Settings surface; wiring the captured message into a live
  `ConnectionManager.send` (depends on U3 transport); the Mac `displayNotification` renderer (U11).
- Notification-access grant + actual capture require a **real device** — not verified here.
- Reserved [Later] action path (US-3.3) is interface-only.

**Verification: ◐ mapper green (`MappersTest`); listener compiles; capture/rendering not hw-verified.**
