# User Stories — Meeting Capture Feature

## Scope Summary

- **Persona**: Owner-User.
- **Story structure**: Epics grouped by user journey.
- **Acceptance criteria**: Standard Given/When/Then format.
- **Tags**: `[v1]` in scope; `[Later]` deferred but documented for architectural runway.

---

## Epic 1 — Start and Manage a Meeting Session on Android

### MC-US-1.1 — Start a meeting recording `[v1]`
As the Owner-User, I want to start a meeting recording from the Android app so that I can capture a lecture or meeting without using a separate recorder.

**Acceptance Criteria**
- Given the phone app is paired with the Mac, when I start a meeting session, then the app creates a unique meeting session with a start time.
- Given recording starts, when the session is active, then the phone shows an ongoing recording state.
- Given recording starts, when the Mac is connected, then the Mac can show the active session status.

### MC-US-1.2 — Continue recording in background `[v1]`
As the Owner-User, I want recording to continue when the app is backgrounded or the screen is off so that I do not lose meeting audio.

**Acceptance Criteria**
- Given a recording is active, when I leave the app, then recording continues.
- Given a recording is active, when the screen turns off, then recording continues.
- Given recording is active, then Android shows a foreground service notification.

### MC-US-1.3 — Pause, resume, and stop recording `[v1]`
As the Owner-User, I want to pause, resume, and stop a session so that I control what is captured.

**Acceptance Criteria**
- Given a recording is active, when I pause it, then audio capture stops and the session remains open.
- Given a session is paused, when I resume it, then audio capture continues with correct timing metadata.
- Given I stop the session, when pending chunks are transferred, then the Mac can complete processing and notes generation.

---

## Epic 2 — Audio Chunking and Reliable Transfer

### MC-US-2.1 — Send one-minute audio chunks `[v1]`
As the Owner-User, I want the phone to send one-minute audio chunks to the Mac so that transcription can begin before the meeting ends.

**Acceptance Criteria**
- Given recording is active, when one minute of audio is captured, then the phone closes a chunk and prepares it for transfer.
- Given the Mac is connected, when a chunk is ready, then the chunk is sent over the encrypted link.
- Given a chunk is sent, then its metadata includes meeting ID, sequence, start time, end time, and checksum.

### MC-US-2.2 — Queue chunks while disconnected `[v1]`
As the Owner-User, I want the phone to keep recording and queue chunks if the Mac disconnects so that transient network loss does not lose meeting audio.

**Acceptance Criteria**
- Given recording is active, when the Mac disconnects, then recording continues locally on the phone.
- Given chunks are queued, when the Mac reconnects, then unsent chunks are uploaded in sequence.
- Given a chunk is confirmed by the Mac, then the phone can delete its local copy.

### MC-US-2.3 — Avoid duplicate processing `[v1]`
As the Owner-User, I want resent chunks to be recognized so that notes do not contain duplicate transcript text.

**Acceptance Criteria**
- Given a chunk was already received, when the phone retries it, then the Mac recognizes the duplicate by meeting ID and sequence/checksum.
- Given a duplicate chunk is detected, then the Mac does not transcribe it twice.
- Given duplicate handling occurs, then no transcript duplicate appears in the final notes.

---

## Epic 3 — Capture Timestamped Photos During a Session

### MC-US-3.1 — Take a photo during a meeting `[v1]`
As the Owner-User, I want to take photos from the Android app during recording so that whiteboards, slides, or notes are attached to the session.

**Acceptance Criteria**
- Given a meeting session is active, when I take a photo, then the photo is associated with the current meeting.
- Given a photo is captured, then it includes meeting-relative timestamp and wall-clock timestamp.
- Given the Mac is connected, then the photo is transferred to the Mac.

### MC-US-3.2 — Delete phone photo copies after Mac confirmation `[v1]`
As the Owner-User, I want session photos removed from the phone after successful transfer so that private meeting artifacts do not remain there.

**Acceptance Criteria**
- Given a photo is transferred, when the Mac confirms receipt, then the phone deletes the session-local photo copy.
- Given the Mac has not confirmed receipt, then the phone keeps the photo queued for retry.
- Given the user stops the session, then unconfirmed photos remain queued until confirmed or explicitly discarded.

---

## Epic 4 — Mac Local Transcription and Speaker Labels

### MC-US-4.1 — Transcribe chunks locally with Whisper `[v1]`
As the Owner-User, I want the Mac to transcribe audio locally so that private meeting audio does not go to a cloud service.

**Acceptance Criteria**
- Given a chunk is received, when the Mac processes it, then transcription runs locally using the project-local Whisper integration.
- Given transcription succeeds, then transcript segments are associated with meeting timestamps.
- Given transcription fails, then the Mac shows a retryable processing failure.

### MC-US-4.2 — Process meeting incrementally `[v1]`
As the Owner-User, I want the Mac to process chunks while the meeting is still running so that notes can be ready soon after the meeting ends.

**Acceptance Criteria**
- Given chunks arrive during a meeting, when each chunk is received, then the Mac can transcribe it before the session stops.
- Given partial transcript exists, when more chunks arrive, then the Mac appends them in chronological order.
- Given the session stops, then remaining queued chunks are processed before final notes are marked ready.

### MC-US-4.3 — Show speaker labels `[v1]`
As the Owner-User, I want transcript segments labeled by detected speaker so that the notes are easier to read.

**Acceptance Criteria**
- Given transcript processing completes, when speaker detection runs, then transcript segments include speaker labels such as Speaker 1 and Speaker 2.
- Given speaker labels are unavailable for a segment, then the transcript still shows the text with a neutral/unknown label.
- Given speaker labels exist, then notes generation can use them.

### MC-US-4.4 — Rename speakers after the meeting `[v1]`
As the Owner-User, I want to rename detected speakers so that notes use meaningful names.

**Acceptance Criteria**
- Given detected speaker labels exist, when I rename Speaker 1, then all matching transcript segments update.
- Given speaker names are changed, when notes are regenerated, then `notes.md` uses the updated names.
- Given I save the meeting, then speaker rename metadata is retained with the meeting output.

---

## Epic 5 — Generate Timestamped Notes with Images

### MC-US-5.1 — Generate local summary and notes `[v1]`
As the Owner-User, I want the Mac to generate meeting notes from the transcript so that I get a useful summary without manual note taking.

**Acceptance Criteria**
- Given a transcript is available, when notes are generated, then the Mac uses local Ollama/Gemma by default.
- Given notes generation completes, then notes include a summary, transcript sections, and action items when detected.
- Given local summarization fails, then the transcript remains available and the failure is visible.

### MC-US-5.2 — Insert photos near matching transcript times `[v1]`
As the Owner-User, I want photos inserted near the transcript time where they were taken so that images have the right meeting context.

**Acceptance Criteria**
- Given photos have meeting-relative timestamps, when notes are generated, then each photo reference appears near the closest transcript timestamp.
- Given no exact transcript segment exists at the photo time, then the image appears in the closest chronological position.
- Given an image is inserted, then the notes show its timestamp.

### MC-US-5.3 — Regenerate notes after edits `[v1]`
As the Owner-User, I want notes to update after speaker renames so that the final Markdown reflects my corrections.

**Acceptance Criteria**
- Given I rename a speaker, when I regenerate notes, then all updated speaker names appear in `notes.md`.
- Given image attachments already exist, when notes regenerate, then image references remain intact.
- Given transcript order is unchanged, then regenerated notes preserve chronological order.

---

## Epic 6 — Save, Delete, and Share Meeting Outputs

### MC-US-6.1 — Save a Markdown meeting folder `[v1]`
As the Owner-User, I want to save a meeting as a Markdown folder so that I can keep notes and attachments locally.

**Acceptance Criteria**
- Given notes are ready, when I save the meeting, then the Mac creates a folder containing `notes.md` and media attachments.
- Given media is saved, then file names include stable meeting/timestamp information.
- Given the folder is saved, then it can be opened from Finder.

### MC-US-6.2 — Delete raw media from Mac `[v1]`
As the Owner-User, I want to delete raw audio/images from the Mac after notes are ready so that I control local retention.

**Acceptance Criteria**
- Given notes are generated, when I choose to delete raw media, then the Mac removes raw audio and selected retained media according to the UI choice.
- Given raw media is deleted, then generated notes remain available if already saved.
- Given deletion completes, then the Mac does not silently keep hidden extra raw copies.

### MC-US-6.3 — Share notes through macOS sharing `[v1]`
As the Owner-User, I want to use the native Mac share sheet so that I can send notes through apps like Telegram, WhatsApp, or email where supported.

**Acceptance Criteria**
- Given a notes output is ready, when I choose Share, then the macOS sharing UI opens for the generated file/folder where supported.
- Given an app supports the shared output, then I can send it through that app.
- Given sharing is unavailable for a target app, then the saved output remains accessible in Finder.

---

## Later Stories

### MC-US-L1 — Cloud LLM option `[Later]`
As the Owner-User, I want to configure a cloud LLM provider optionally so that I can choose higher-quality summaries when privacy tradeoffs are acceptable.

**Acceptance Criteria**
- Given cloud summary is disabled by default, when I do nothing, then notes remain local-only.
- Given I explicitly configure a cloud provider later, then the app explains what data may leave the Mac.

### MC-US-L2 — PDF export `[Later]`
As the Owner-User, I want to export a single PDF so that I can share polished notes with embedded images.

**Acceptance Criteria**
- Given notes and attachments exist, when I export PDF, then images and transcript sections are included.
- Given PDF export completes, then the output is shareable through the Mac share sheet.

### MC-US-L3 — Explicit chat/email integrations `[Later]`
As the Owner-User, I want direct Telegram, WhatsApp, and email integrations so that sharing is one-click inside the app.

**Acceptance Criteria**
- Given integrations are configured, when I choose a target, then the app prepares the notes for that target.
- Given credentials or app access is missing, then the app fails safely without losing saved notes.

---

## INVEST Check

- **Independent**: Stories are grouped by journey but each has a discrete user outcome.
- **Negotiable**: Implementation choices such as codec, diarization library, and UI layout remain design decisions.
- **Valuable**: Each story maps to capture, processing, review, or sharing value for the Owner-User.
- **Estimable**: Stories are scoped to visible capabilities with clear acceptance criteria.
- **Small**: Larger flows are split into recording, queueing, photo capture, transcription, notes, and sharing stories.
- **Testable**: Given/When/Then criteria support unit, integration, and manual hardware validation tests.

## Persona Mapping

| Epic | Persona |
|---|---|
| Epic 1 — Start and Manage a Meeting Session on Android | Owner-User |
| Epic 2 — Audio Chunking and Reliable Transfer | Owner-User |
| Epic 3 — Capture Timestamped Photos During a Session | Owner-User |
| Epic 4 — Mac Local Transcription and Speaker Labels | Owner-User |
| Epic 5 — Generate Timestamped Notes with Images | Owner-User |
| Epic 6 — Save, Delete, and Share Meeting Outputs | Owner-User |
| Later Stories | Owner-User |
