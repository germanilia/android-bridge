# Requirements — Meeting Capture Feature Increment

## Intent Analysis

- **User request**: Add meeting/lecture capture to the Android phone app: record voice, take photos during the session, transfer one-minute audio chunks to the Mac, transcribe locally with Whisper, detect speakers, summarize with local Ollama/Gemma, and produce notes where timestamped images are inserted at the correct point in the transcript timeline. Notes can be saved locally and shared through native Mac sharing to Telegram, WhatsApp, or email where available.
- **Request type**: New feature increment on existing Android + macOS continuity app.
- **Scope estimate**: Multiple components — Android capture service/UI, protocol message types and binary streams, Mac ingestion/transcription/summarization/note assembly, Mac UI/export/share.
- **Complexity estimate**: Complex — long-running Android audio recording, resumable chunk transfer, local ML tooling integration, diarization/speaker rename flow, privacy-sensitive media handling, and timestamp alignment.
- **Requirements depth**: Comprehensive for this increment.

## Locked Decisions From Requirements Questions

| Area | Decision |
|---|---|
| v1 priority | End-to-end working pipeline first. |
| Android recording lifecycle | Recording must continue in background / screen-off using a foreground service and persistent notification. |
| Audio format target | Speech-optimized compressed audio, small enough for long meetings. |
| Offline behavior | If disconnected, keep recording locally on phone, queue chunks, and upload after reconnect. |
| Phone retention | Do not keep anything on the phone after successful Mac transfer/confirmation. |
| Mac retention | User decides whether to save or delete raw audio/images from the Mac. |
| Whisper integration | Import/localize the discovered MLX Whisper CLI implementation into this project; do not depend on the other project path. Source candidate: `/Users/iliagerman/Work/personal_projects/video_translator/.venv-mlx/bin/mlx_whisper`. |
| Speaker detection | v1 supports diarization labels and lets the user rename speakers after the meeting; notes update with renamed speakers. |
| Summarization | v1 stays local-first and can later allow configured cloud LLM. Use Ollama with available Gemma model. `ollama ls` found `gemma4:e4b` / `gemma4:latest` (same ID). |
| Output format | Markdown folder: `notes.md` plus media attachments with timestamps. |
| Sharing | Use native macOS share sheet where possible. |
| Photo placement | Insert image references at nearest transcript timestamp based on capture time. |
| Import existing media | Not in v1; only live recording and live camera capture. |
| Privacy model | Normal app sandbox/file-system storage for generated notes; pairing keys remain secure. No cloud by default. |

## Functional Requirements

### MC-FR-1 — Meeting Session Lifecycle
- MC-FR-1.1: Android app can create a new meeting/lecture recording session with a unique `meetingId`.
- MC-FR-1.2: User can start, pause/resume, and stop the session from Android.
- MC-FR-1.3: Mac shows active/incoming session status and received processing progress.
- MC-FR-1.4: Each session records metadata: title/default name, start time, end time, device ID, and processing state.

### MC-FR-2 — Android Audio Recording
- MC-FR-2.1: Android records microphone audio in a foreground service with an ongoing notification.
- MC-FR-2.2: Recording continues while the app is backgrounded or screen is off.
- MC-FR-2.3: Audio is segmented into one-minute chunks.
- MC-FR-2.4: Chunks use a speech-optimized compressed format suitable for long meetings.
- MC-FR-2.5: Each chunk includes timing metadata: meeting-relative start time, end time, wall-clock capture time, sequence number, duration, and checksum.

### MC-FR-3 — Chunk Transfer and Queueing
- MC-FR-3.1: Android sends each one-minute chunk to the Mac over the existing encrypted LAN link.
- MC-FR-3.2: If disconnected, Android queues unsent chunks and uploads them when the link reconnects.
- MC-FR-3.3: Android deletes transferred chunks only after Mac confirmation.
- MC-FR-3.4: Transfer is ordered and resumable enough to avoid duplicate notes/transcripts after reconnect.
- MC-FR-3.5: Mac persists received chunks under a meeting workspace until the user deletes raw media or exports notes.

### MC-FR-4 — Android Photo Capture During Sessions
- MC-FR-4.1: Android app can take photos during an active meeting session.
- MC-FR-4.2: Each photo is tagged with meeting-relative timestamp and wall-clock timestamp.
- MC-FR-4.3: Photos are transferred to Mac and confirmed similarly to audio chunks.
- MC-FR-4.4: Phone-side photo copies created for the session are deleted after successful Mac confirmation.
- MC-FR-4.5: Importing existing media is out of scope for v1.

### MC-FR-5 — Mac Local Transcription
- MC-FR-5.1: Mac transcribes received chunks locally using an imported project-local MLX Whisper command/tooling.
- MC-FR-5.2: The implementation must not call the `video_translator` project path at runtime.
- MC-FR-5.3: Transcription results preserve chunk timing and word/segment timing where the tool supports it.
- MC-FR-5.4: Mac can process chunks incrementally during the meeting instead of waiting for the final stop event.
- MC-FR-5.5: Failed chunk transcription is visible and retryable.

### MC-FR-6 — Speaker Detection and Rename Flow
- MC-FR-6.1: Mac performs speaker diarization/detection sufficient to label transcript segments as `Speaker 1`, `Speaker 2`, etc.
- MC-FR-6.2: User can rename speakers after the meeting.
- MC-FR-6.3: Renaming a speaker updates transcript display and generated `notes.md`.
- MC-FR-6.4: Automatic known-speaker identification from prior voice samples is out of scope for v1.

### MC-FR-7 — Local Summary and Notes Generation
- MC-FR-7.1: Mac generates notes locally from transcript using Ollama with `gemma4:e4b`/`gemma4:latest` as the initial available Gemma model.
- MC-FR-7.2: Summary generation must be local by default; optional user-configured cloud LLM can be designed for later but not required in v1.
- MC-FR-7.3: Notes include at minimum: title, date/time, summary, action items when detected, speaker-attributed transcript sections, and image references.
- MC-FR-7.4: Notes generation is repeatable after speaker renaming.

### MC-FR-8 — Timestamped Image Placement
- MC-FR-8.1: Mac inserts image references into notes at the nearest transcript timestamp based on capture time.
- MC-FR-8.2: Image file names include stable meeting ID or session slug and timestamp.
- MC-FR-8.3: If no transcript segment exists near the photo timestamp, the image is placed in the closest chronological position with its timestamp shown.

### MC-FR-9 — Save, Delete, Export, and Share
- MC-FR-9.1: Mac can save a meeting as a Markdown folder containing `notes.md`, transcript/intermediate metadata, and media attachments.
- MC-FR-9.2: User can delete raw audio and images from Mac after notes are generated.
- MC-FR-9.3: User can invoke native macOS sharing for generated notes/files where supported.
- MC-FR-9.4: Explicit Telegram/WhatsApp/email integrations are out of scope for v1 beyond native sharing.

## Protocol Requirements

### MC-PR-1 — New Meeting Capture Message Types
Add protocol registry entries for:
- `meeting.start`
- `meeting.stop`
- `meeting.audioChunk.offer`
- `meeting.audioChunk.received`
- `meeting.photo.offer`
- `meeting.photo.received`
- `meeting.processing.status`
- `meeting.notes.ready`

Payloads must be schema-validated and size-bounded before processing.

### MC-PR-2 — Binary Streams
- Audio chunks and photos larger than inline blob limits use binary frame streams.
- Control messages carry only metadata plus `streamId`.
- Existing stream chunking/reassembly logic should be reused where possible.

## Non-Functional Requirements

### MC-NFR-1 — Privacy and Locality
- No transcription, summarization, raw audio, images, transcript, or notes leave the paired devices by default.
- Ollama/Gemma and Whisper run locally on the Mac.
- Generated notes use normal app sandbox/file-system storage unless later design adds encrypted notebooks.

### MC-NFR-2 — Security Baseline Compliance
- SECURITY-01: Device-to-device transfer remains mTLS encrypted. Pairing keys remain in Keychain/Keystore.
- SECURITY-03: Logs must not include transcript text, audio content, phone/user private data, raw file paths containing sensitive names, or image content.
- SECURITY-05/13: All meeting protocol messages are untrusted input and require schema, type, size, sequence, checksum, and path validation.
- SECURITY-08/15: Only paired authenticated devices can start transfer or processing actions; malformed messages fail closed.
- SECURITY-10: Imported Whisper tooling and any diarization dependencies must be pinned/locked and documented.
- SECURITY-12: No hardcoded secrets or API keys. Ollama is local and does not require credentials.

### MC-NFR-3 — Reliability
- Android must not silently lose recorded chunks during transient disconnects.
- Mac must avoid duplicate processing when a queued chunk is resent.
- Processing failures are visible with retry controls.

### MC-NFR-4 — Performance
- One-minute chunks should begin transferring soon after each chunk closes.
- Mac can transcribe incrementally so notes are partially available before meeting end.
- Background recording should avoid unnecessary battery drain.

### MC-NFR-5 — Testability and Partial PBT
- PBT-02: New meeting capture control message encode/decode round-trips in Kotlin and Swift.
- PBT-03: Timestamp/image placement invariants and stream chunk/reassembly invariants where pure.
- PBT-07: Domain generators include valid meeting IDs, timestamps, chunk sequences, and payload metadata.
- PBT-08: PBT remains seed-reproducible and CI-compatible.
- PBT-09: Existing Kotest/SwiftCheck frameworks continue to be used.

## Out of Scope for v1

- Importing existing audio/images into a meeting.
- Cloud transcription/summarization by default.
- Automatic known-speaker identification from voice profiles.
- PDF export.
- Custom Telegram/WhatsApp/email API integrations.
- Keeping session media on the phone after confirmed Mac transfer.

## Discovered Local Dependencies

- `ollama ls` shows:
  - `gemma4:e4b` — 9.6 GB
  - `gemma4:latest` — same model ID
- Local Whisper candidates found:
  - `/Users/iliagerman/Work/personal_projects/video_translator/.venv-mlx/bin/mlx_whisper`
  - `/Users/iliagerman/Work/personal_projects/video_translator/scripts/asr_mlx.py`
  - `/Applications/TypeWhisper.app`

## Open Items for Design

- Exact Android audio codec/container choice for speech-optimized chunks.
- How to vendor/import MLX Whisper into this repo without copying a virtualenv wholesale.
- Speaker diarization implementation choice and dependency footprint.
- Mac app UI layout for active processing, speaker rename, and final notes preview.
