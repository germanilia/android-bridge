# Components — Meeting Capture Feature

## A. Protocol Extensions

### A1. Meeting Message Registry
- **Purpose**: Add typed `meeting.*` control messages.
- **Responsibilities**: Define schemas for session lifecycle, audio chunk offers/acks, photo offers/acks, processing status, and notes-ready events.
- **Interface**: `schemaFor(type)`, `validateMeetingPayload(type, payload)`.

### A2. Meeting Binary Streams
- **Purpose**: Carry audio chunks and photos using existing frame streams.
- **Responsibilities**: Reference `streamId` from control messages; validate payload lengths and checksums.
- **Interface**: existing `Frame`/`StreamChunker`/`StreamReassembler`.

## B. Android Components

### B1. MeetingCapturePlugin
- **Purpose**: Android feature plugin for meeting sessions.
- **Responsibilities**: Coordinate session lifecycle, recorder, photo capture, queue, transfer, and delete-on-confirm.
- **Interface**: `startSession`, `pauseSession`, `resumeSession`, `stopSession`, `capturePhoto`.

### B2. MeetingRecordingService
- **Purpose**: Foreground microphone recording service.
- **Responsibilities**: Record while backgrounded/screen-off; segment speech-optimized audio into one-minute chunks.
- **Interface**: `start`, `pause`, `resume`, `stop`, `onChunkReady`.

### B3. MeetingTransferQueue
- **Purpose**: Durable queue for audio/photo artifacts awaiting Mac confirmation.
- **Responsibilities**: Store unsent items, retry after reconnect, delete phone copies only after confirmation.
- **Interface**: `enqueueAudioChunk`, `enqueuePhoto`, `markConfirmed`, `pendingItems`.

### B4. MeetingPhotoCapture
- **Purpose**: Capture timestamped photos during active sessions.
- **Responsibilities**: Create session-associated image files and metadata.
- **Interface**: `capture(meetingId, relativeTime)`.

### B5. Android Meeting UI
- **Purpose**: Compose controls for session and photo capture.
- **Responsibilities**: Start/pause/resume/stop; show queue/connection state; expose camera action.
- **Interface**: screen/view-model over `MeetingCapturePlugin`.

## C. Mac Components

### C1. MeetingIngestionPlugin
- **Purpose**: Receive meeting control messages and binary streams.
- **Responsibilities**: Persist chunks/photos, deduplicate by meeting ID + sequence/checksum, send acknowledgements.
- **Interface**: `handleMeetingMessage`, `receiveStream`, `acknowledge`.

### C2. MeetingStore
- **Purpose**: Local filesystem workspace per meeting.
- **Responsibilities**: Store raw chunks/photos, transcript metadata, speaker names, generated notes, and export folder.
- **Interface**: `createMeeting`, `saveChunk`, `savePhoto`, `saveTranscript`, `saveNotes`, `deleteRawMedia`.

### C3. WhisperTranscriptionService
- **Purpose**: Local transcription using project-local Whisper tooling.
- **Responsibilities**: Run transcription per chunk, parse timed transcript segments, expose retryable errors.
- **Interface**: `transcribe(chunkFile) -> [TranscriptSegment]`.

### C4. SpeakerLabelService
- **Purpose**: Assign and rename speaker labels.
- **Responsibilities**: Apply diarization output when available; maintain user-provided speaker names.
- **Interface**: `label(segments)`, `renameSpeaker(old, new)`.

### C5. OllamaNotesService
- **Purpose**: Generate local summaries and notes with Gemma via Ollama.
- **Responsibilities**: Build prompt from transcript and media timeline; call local Ollama; return Markdown sections.
- **Interface**: `generateNotes(meeting) -> Markdown`.

### C6. ImagePlacementService
- **Purpose**: Place photos near nearest transcript timestamp.
- **Responsibilities**: Chronologically merge transcript segments and image references.
- **Interface**: `placeImages(segments, photos) -> [NoteBlock]`.

### C7. MeetingExportShareService
- **Purpose**: Save Markdown folder and invoke native sharing.
- **Responsibilities**: Write `notes.md`, attachments, open Finder/share sheet, delete raw media on user request.
- **Interface**: `saveMarkdownFolder`, `share`, `deleteRawMedia`.

### C8. Mac Meeting UI
- **Purpose**: SwiftUI views for sessions, progress, speaker rename, notes preview, and sharing.
- **Responsibilities**: Show processing status, allow rename/regenerate, save/delete/share.
- **Interface**: view-model over Mac meeting services.
