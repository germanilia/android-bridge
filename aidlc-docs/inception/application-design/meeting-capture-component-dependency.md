# Component Dependencies — Meeting Capture

## Dependency Matrix

| Component | Depends On | Used By |
|---|---|---|
| Meeting Message Registry | Existing protocol envelope/registry | Android/Mac meeting plugins |
| Meeting Binary Streams | Existing frame codec | Audio/photo transfer |
| Android MeetingCapturePlugin | RecordingService, PhotoCapture, TransferQueue, LinkManager | Android UI |
| MeetingRecordingService | Android foreground service + MediaRecorder platform APIs | MeetingCapturePlugin |
| MeetingPhotoCapture | Android camera/activity result platform APIs | MeetingCapturePlugin |
| MeetingTransferQueue | Android app-private files, LinkManager | MeetingCapturePlugin |
| MeetingIngestionPlugin | MessageRouter, MeetingStore | Mac processing/UI |
| MeetingStore | Mac filesystem | Ingestion, processing, export |
| WhisperTranscriptionService | Project-local Whisper executable | MeetingProcessingPipeline |
| SpeakerLabelService | Transcript segments | Processing/UI |
| OllamaNotesService | Local Ollama CLI/API | Notes generation |
| ImagePlacementService | Transcript segments + photo metadata | Notes generation |
| MeetingExportShareService | MeetingStore, macOS sharing | Mac UI |

## Data Flow

1. Android starts session and sends `meeting.start`.
2. Android records one-minute chunk.
3. Android sends `meeting.audioChunk.offer` with stream ID and metadata.
4. Android streams audio bytes over existing binary frames.
5. Mac stores chunk, deduplicates, verifies checksum, and sends `meeting.audioChunk.received`.
6. Android deletes confirmed phone-side copy.
7. Mac transcribes chunk locally and updates processing state.
8. Android captures photo and sends `meeting.photo.offer` + stream.
9. Mac stores photo, acknowledges, and later places it near nearest transcript timestamp.
10. Mac generates notes with local Ollama/Gemma.
11. User renames speakers, regenerates notes, saves Markdown folder, and shares.

## Communication Patterns

- **Control path**: typed JSON messages over existing mTLS link.
- **Bulk path**: binary frame streams referenced by stream IDs.
- **Deletion safety**: Mac acknowledgement is required before Android deletes artifacts.
- **Processing path**: Mac-local only; no network calls except local Ollama endpoint/process.

## Security Notes

- Meeting messages are untrusted until schema-validated.
- Checksums verify stream payload integrity before acknowledgement.
- Logs must include IDs/state only, never transcript/audio/image content.
