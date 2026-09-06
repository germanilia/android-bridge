# Video Notes — Requirements Clarification Questions

Please answer each question by filling in the letter choice after the `[Answer]:` tag.
If none of the options match, choose the last option (Other) and describe your preference.

---

## What I understood from your request

Part of your message came through garbled by speech-to-text, so here is my reading:

> You want to record a video and have it saved as a **meeting**. The video becomes the
> note itself (a "video note"), the way an audio recording becomes a meeting today.
> A meeting should be able to hold **audio files, video files, and text** together.
> This matters most for notes **you record yourself on your phone**, not for
> auto-recorded Teams meetings.

## What exists today (so the questions make sense)

- A meeting is a folder on the Mac. Inside it: `media/chunk-0001.m4a` audio pieces,
  `media/photo-*.jpg` photos, `transcript.jsonl`, `notes.md`, `summary-*.md`, `chat.json`.
- The Mac recognizes only `m4a`, `3gp`, `wav` as audio and `jpg`, `jpeg`, `png` as images.
  **Video is not recognized at all right now** (`MeetingCapture.swift:696`).
- The phone records **audio only** — 60-second AAC chunks
  (`MeetingRecorderService.kt:83`) sent to the Mac as base64 inside control messages
  capped at **1 MiB each** (`protocol/PROTOCOL.md:111`). A minute of video is far
  larger than that, so video needs a different delivery path.
- The Mac transcribes locally with MLX Whisper, and `ffmpeg` is already an installed
  dependency — which means the audio track can be pulled out of a video file and
  transcribed exactly like an audio chunk.

---

## Question 1
Is my reading of your request above correct?

A) Yes, that is what I meant

B) Mostly right, but I will correct it after the [Answer] tag

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 2
Where is the video recorded?

A) On the phone — the Android app opens the camera and records a video note

B) On the Mac — record from the Mac camera or screen

C) Both phone and Mac

D) Neither — I only want to attach video files I already have (phone gallery, Teams export, downloads)

E) Phone recording plus attaching existing files, but no Mac camera recording

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 3
Should the video's speech be transcribed into the meeting?

Extracting the audio track from a video and running it through the existing Whisper
pipeline would make the summary, the transcript, and the meeting chat work on video
notes exactly as they do on audio meetings.

A) Yes — always extract the audio, transcribe it, and feed it into the transcript, summary, and chat

B) No — the video is just a file I can open and watch; no transcript from it

C) Let me choose per video when I add it

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 4
How should video and audio coexist inside one meeting?

A) A meeting can hold any mix — audio chunks, videos, photos, and text all in the same meeting

B) A video note is its own kind of meeting — recording video creates a video-only meeting

C) Both: mixed meetings are allowed, and a quick "record video note" also creates a standalone one

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 5
How should the video file travel from the phone to the Mac?

The current meeting path cannot carry it (1 MiB per message limit).

A) Reuse the existing file-transfer feature — it already does chunked binary transfer for drag-and-drop files

B) Add a new binary streaming path to the protocol, which `PROTOCOL.md` already anticipates (`streamId` frames)

C) Keep the video on the phone; send only the transcript and a thumbnail to the Mac, and let Syncthing/the relay move the file later

D) Not applicable — video is Mac-only for this increment

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 6
Should long videos be split into pieces while recording?

Audio is already chunked every 60 seconds, so a crash or a dropped link never loses
more than the last minute. Video could work the same way, or be recorded as one file
and uploaded after you stop.

A) Chunk it like audio, so a crash or dropped connection loses at most the last chunk

B) One single file per recording, uploaded when I press stop — simpler

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 7
You said a meeting must support "text". What does text mean here?

A) Typed notes I write myself into the meeting, saved and searchable alongside the transcript

B) Text or markdown files I attach to the meeting, like the photos

C) Both of the above

D) Nothing new — the existing `notes.md` and summary already cover it

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 8
How should video storage be handled? Ten minutes of 1080p video is roughly 1 GB.

A) Store the original file as-is, no size limit and no compression

B) Store the original, but warn me when a meeting folder gets large

C) Compress or downscale video on the way in to save disk space

D) Keep the original and also make a small, low-resolution copy for quick preview

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 9
Should videos be playable on the phone too?

Android already shows mirrored past meetings and their text content.

A) Yes — I want to watch meeting videos on the phone as well

B) No — playing video on the Mac is enough for now

X) Other (please describe after [Answer]: tag below)

[Answer]:

---

## Question 10: Security Extensions
Should security extension rules be enforced for this project?

A) Yes — enforce all SECURITY rules as blocking constraints (recommended for production-grade applications)

B) No — skip all SECURITY rules (suitable for PoCs, prototypes, and experimental projects)

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 11: Resiliency Extensions
Should the resiliency baseline be applied to this project?

**What this extension is.** Enabling it applies a set of **directional, design-time best practices** for building resilient systems, derived from the **AWS Well-Architected Framework (Reliability Pillar)** and resilience-review guidance. It steers requirements, design, and code toward fault tolerance, high availability, observability, and recoverability — covering 15 practice areas across business goals, change management, observability, high availability, disaster recovery, and continuous improvement.

**What this extension is NOT.** Enabling it does **not** make your workload production-ready, nor does it certify or guarantee any availability, RTO, or RPO target. It is a **starting point** that scaffolds good resiliency decisions early — it is not a substitute for a formal **AWS Well-Architected Review** of the built system.

Treat the output as a well-grounded **first draft of your resiliency posture** to build on and validate — not a finished, production-certified result.

A) Yes — apply the resiliency baseline as directional best practices and design-time guidance (recommended for business-critical workloads, as an informed starting point that you can validate and harden before go-live)

B) No — skip the resiliency baseline (suitable for PoCs, prototypes, and experimental projects where rapid iteration matters more than reliability)

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 12: Property-Based Testing Extension
Should property-based testing (PBT) rules be enforced for this project?

A) Yes — enforce all PBT rules as blocking constraints (recommended for projects with business logic, data transformations, serialization, or stateful components)

B) Partial — enforce PBT rules only for pure functions and serialization round-trips (suitable for projects with limited algorithmic complexity)

C) No — skip all PBT rules (suitable for simple CRUD applications, UI-only projects, or thin integration layers with no significant business logic)

X) Other (please describe after [Answer]: tag below)

[Answer]:
