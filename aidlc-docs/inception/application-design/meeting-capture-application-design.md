# Application Design — Meeting Capture Feature

## Overview

Meeting Capture adds a new cross-device feature plugin. Android captures audio/photos and Mac receives, processes, summarizes, saves, and shares. The feature uses the existing mTLS link and binary stream framing.

## Artifacts

- `meeting-capture-components.md` — component definitions.
- `meeting-capture-component-methods.md` — high-level method interfaces.
- `meeting-capture-services.md` — service orchestration.
- `meeting-capture-component-dependency.md` — dependency/data-flow mapping.

## Core Design

- Add `MeetingCapturePlugin` on Android and `MeetingIngestionPlugin` on Mac.
- Add `meeting.*` protocol messages and PBT coverage.
- Use Android foreground service for background recording.
- Use phone-side queue with confirmation-based deletion.
- Use Mac-local workspace for durable storage and processing.
- Use project-local Whisper tooling and local Ollama/Gemma for processing.
- Use Markdown folder export and native macOS sharing.

## Compliance Summary

### Security
- Applicable: SECURITY-01, SECURITY-03, SECURITY-05, SECURITY-08, SECURITY-10, SECURITY-12, SECURITY-13, SECURITY-15.
- N/A: cloud/web-specific SECURITY-02, SECURITY-04, SECURITY-07.
- No blocking findings at application-design level.

### PBT
- Enforced: PBT-02, PBT-03, PBT-07, PBT-08, PBT-09.
- New protocol messages and pure timestamp placement logic are PBT targets.
- No blocking findings at application-design level.
