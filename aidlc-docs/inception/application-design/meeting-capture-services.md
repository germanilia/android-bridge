# Services — Meeting Capture

## Android Service Layer

### MeetingCaptureCoordinator
Coordinates Android user actions with recording, photo capture, queueing, and link transfer.

**Interactions**:
1. UI calls coordinator to start/pause/resume/stop.
2. Coordinator starts `MeetingRecordingService`.
3. Recorder emits chunk metadata/files.
4. Coordinator enqueues artifacts in `MeetingTransferQueue`.
5. On connection, queue sends metadata messages and binary streams.
6. On Mac acknowledgement, queue deletes phone-side copy.

### MeetingRecordingService
Android foreground service responsible for reliable background microphone capture.

### MeetingTransferQueue
Local durable queue for pending audio/photo artifacts. It is the boundary that prevents data loss during disconnects.

## Mac Service Layer

### MeetingIngestionCoordinator
Routes `meeting.*` messages and streams into `MeetingStore`, sends acknowledgements, and triggers processing.

### MeetingProcessingPipeline
Sequential local processing pipeline:
1. Transcribe chunk with `WhisperTranscriptionService`.
2. Merge transcript segments by timestamp.
3. Apply speaker labels and user speaker-name map.
4. Place images by timestamp.
5. Generate Markdown notes with `OllamaNotesService`.

### MeetingExportCoordinator
Handles save/delete/share actions:
1. Save Markdown folder.
2. Optionally delete raw audio/images.
3. Invoke native macOS share sheet where supported.

## Orchestration Pattern

- Android owns capture and temporary phone-side storage.
- Mac owns durable meeting workspace and all ML processing.
- Protocol messages are commands/events; audio/photo bytes travel through binary streams.
- Acknowledgements are the only trigger for Android deletion.
