# Security Policy

Android Bridge is a local-first continuity app. Security reports are welcome.

## Supported versions

The `main` branch is the active development line.

## Reporting a vulnerability

Please open a private security advisory on GitHub if available, or contact the maintainer directly.
Do not publish exploit details before there is a fix or mitigation.

## Security expectations

Android Bridge should:

- communicate only with paired devices;
- use pinned TLS for device-to-device traffic;
- avoid cloud relays and third-party analytics;
- avoid logging private content such as clipboard text, SMS bodies, phone numbers, and file contents;
- store received files only where the user expects, with cleanup for temporary cache storage;
- require explicit platform permission for screen capture and remote control.

## Non-goals

Android Bridge does not try to bypass Android MediaProjection consent, Android Accessibility consent, or macOS privacy permissions.
