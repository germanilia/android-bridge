# Component Methods — Meeting Capture

## Protocol

```text
validateMeetingPayload(type: String, payload: Map) -> ValidationResult
makeMeetingStart(meetingId: String, startedAt: Int) -> Message
makeAudioChunkOffer(metadata: AudioChunkMetadata, streamId: UInt32) -> Message
makeAudioChunkReceived(meetingId: String, sequence: Int, checksum: String) -> Message
makePhotoOffer(metadata: PhotoMetadata, streamId: UInt32) -> Message
makePhotoReceived(meetingId: String, photoId: String, checksum: String) -> Message
```

## Android

```text
MeetingCapturePlugin.startSession(title: String?) -> MeetingSession
MeetingCapturePlugin.pauseSession(meetingId: String)
MeetingCapturePlugin.resumeSession(meetingId: String)
MeetingCapturePlugin.stopSession(meetingId: String)
MeetingCapturePlugin.capturePhoto(meetingId: String) -> PhotoMetadata

MeetingRecordingService.start(session: MeetingSession)
MeetingRecordingService.pause()
MeetingRecordingService.resume()
MeetingRecordingService.stop()
MeetingRecordingService.onChunkReady(callback: (AudioChunkMetadata, File) -> Unit)

MeetingTransferQueue.enqueueAudioChunk(metadata: AudioChunkMetadata, file: File)
MeetingTransferQueue.enqueuePhoto(metadata: PhotoMetadata, file: File)
MeetingTransferQueue.pendingItems() -> List<QueuedMeetingItem>
MeetingTransferQueue.markConfirmed(itemId: String)
MeetingTransferQueue.retryPending()
```

## Mac

```text
MeetingIngestionPlugin.handle(message: Message)
MeetingIngestionPlugin.receiveAudioChunk(metadata: AudioChunkMetadata, data: Data)
MeetingIngestionPlugin.receivePhoto(metadata: PhotoMetadata, data: Data)
MeetingIngestionPlugin.ackAudioChunk(metadata: AudioChunkMetadata)
MeetingIngestionPlugin.ackPhoto(metadata: PhotoMetadata)

MeetingStore.createMeeting(metadata: MeetingMetadata) -> MeetingWorkspace
MeetingStore.saveChunk(metadata: AudioChunkMetadata, data: Data) -> URL
MeetingStore.savePhoto(metadata: PhotoMetadata, data: Data) -> URL
MeetingStore.saveTranscript(meetingId: String, segments: [TranscriptSegment])
MeetingStore.saveNotes(meetingId: String, markdown: String) -> URL
MeetingStore.deleteRawMedia(meetingId: String)

WhisperTranscriptionService.transcribe(file: URL, timing: AudioChunkTiming) -> [TranscriptSegment]
SpeakerLabelService.label(segments: [TranscriptSegment]) -> [TranscriptSegment]
SpeakerLabelService.renameSpeaker(meetingId: String, from: String, to: String)
ImagePlacementService.placeImages(segments: [TranscriptSegment], photos: [MeetingPhoto]) -> [NoteBlock]
OllamaNotesService.generateNotes(meeting: MeetingDraft) -> String
MeetingExportShareService.saveMarkdownFolder(meeting: MeetingDraft) -> URL
MeetingExportShareService.share(url: URL)
```

Detailed business rules are deferred to per-unit Functional Design.
