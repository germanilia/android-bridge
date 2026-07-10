# Meeting Capture — Code Generation Summary

## Implemented

### Protocol
- Added `meeting.*` message types to Swift and Kotlin protocol registries.
- Updated `protocol/PROTOCOL.md` with meeting session, audio chunk, photo, processing status, and notes-ready messages.
- Existing PBT covers new message types through `MessageTypes.known` generators.

### Android
- Added `MeetingRecorderService` foreground microphone recorder.
- Records speech-optimized AMR-WB `.3gp` audio in one-minute chunks.
- Sends `meeting.start`, `meeting.stop`, and `meeting.audioChunk.offer` messages.
- Adds camera preview capture for in-session photos and sends `meeting.photo.offer`.
- Deletes phone-side audio/photo files after Mac acknowledgement messages.
- Added RECORD_AUDIO/CAMERA and foreground microphone permissions.
- Added Android UI section for Start recording, Stop, and Take meeting photo.

### Mac
- Added `MeetingCapture.swift` with:
  - `MeetingStore`
  - `WhisperTranscriptionService`
  - `OllamaNotesService`
  - `NotesBuilder`
  - transcript/photo models
- Mac receives audio/photo messages, stores them in `Documents/AndroidBridgeMeetings`, transcribes chunks, writes `notes.md`, acknowledges receipt, and sends notes-ready status.
- Added Mac UI button to open the meetings folder.
- Added project-local MLX Whisper wrapper under `mac/Tools/mlx_whisper/`.

### Tests
- Added Android mapper test for meeting audio chunk messages.
- Added Mac notes/image placement test.
- Existing protocol PBT validates new message types via registry generator coverage.

## Current Operational Notes

- Whisper runs only when `mac/Tools/mlx_whisper/bin/mlx_whisper` is executable and Python deps from `mac/Tools/mlx_whisper/requirements.txt` are installed.
- If Whisper is unavailable, the Mac still saves chunks and writes placeholder transcript lines so the pipeline remains end-to-end testable.
- Ollama summary uses local `ollama run gemma4:e4b`; if unavailable, notes fall back to a local default summary.
- v1 transfers audio/photos as base64 in control messages. AMR-WB chunks are expected to stay under the 1 MiB control-message limit. Larger future media should move to binary stream messages.

## Verification Results

- `cd protocol/swift && swift test` — passed.
- `cd android && ./gradlew :protocol:test --no-daemon` — passed.
- `cd mac && swift test` — passed.
- `cd android && ./gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon` — passed.
