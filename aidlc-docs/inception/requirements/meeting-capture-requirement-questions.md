# Meeting Capture Feature — Requirements Questions

Please answer each question by filling in the letter choice after the `[Answer]:` tag. If none of the options fit, choose `X` and describe your preference.

## Question 1
What should the first version optimize for?

A) End-to-end working pipeline: record audio on Android, send one-minute chunks to Mac, transcribe locally, generate notes, and save locally

B) Capture experience first: polished Android recording + photo capture with reliable transfer, but simple transcript/notes on Mac

C) Mac intelligence first: robust transcription, speaker detection, summaries, and note assembly, with basic Android capture UI

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
Should recording continue when the Android app is in the background or the phone screen is off?

A) Yes — use an Android foreground service with a persistent notification while recording

B) No — recording only while the app is open

X) Other (please describe after [Answer]: tag below)

[Answer]:  A

## Question 3
What audio quality/storage tradeoff should we target for one-minute chunks?

A) Speech-optimized compressed audio, smaller chunks, good for long meetings

B) Higher-quality audio, larger chunks, better transcription accuracy if network/storage allow

C) Configurable quality with a speech-optimized default

X) Other (please describe after [Answer]: tag below)

[Answer]:  A

## Question 4
What should happen if the phone loses connection to the Mac during recording?

A) Keep recording locally on the phone, queue chunks, and upload when reconnected

B) Stop recording and warn the user

C) Continue recording but only keep the latest unsent chunks to limit storage

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
Where should raw audio and images be retained after successful Mac processing?

A) Keep raw files on the Mac only; delete transferred phone copies after confirmation

B) Keep raw files on both phone and Mac until the user deletes them

C) Keep only final transcript/notes by default; raw media retention is opt-in

X) Other (please describe after [Answer]: tag below)

[Answer]: allow users t sve or delete them from mac only don't keep anyting on the phone

## Question 6
Which local transcription implementation should we integrate first?

A) Use the discovered local MLX Whisper CLI at `/Users/iliagerman/Work/personal_projects/video_translator/.venv-mlx/bin/mlx_whisper`

B) Use the discovered Python script at `/Users/iliagerman/Work/personal_projects/video_translator/scripts/asr_mlx.py`

C) Treat Whisper as an external configurable command in Mac settings, with one of the discovered implementations as the default

X) Other (please describe after [Answer]: tag below)

[Answer]: A and import it to the project dont use it from different project.

## Question 7
What is the required speaker detection behavior for v1?

A) Speaker diarization labels only, such as Speaker 1 / Speaker 2, without knowing real names

B) Allow the user to rename detected speakers after the meeting, then update the notes

C) Try to identify known speakers automatically from prior voice samples

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 8
How should summaries/notes be generated?

A) Fully local on the Mac only, even if quality is basic at first

B) Allow a user-configured cloud LLM option later, but keep v1 local-only

C) Transcript only in v1; summarization can come later

X) Other (please describe after [Answer]: tag below)

[Answer]: B use ollama gemma model (run ollama ls to see which one)

## Question 9
What output format should the saved notes support first?

A) Markdown folder: notes.md plus media attachments with timestamps

B) Single PDF export with embedded images

C) Both Markdown folder and PDF export in v1

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 10
How should sharing to Telegram / WhatsApp / email work in v1?

A) Use the native macOS share sheet for the generated notes file/folder where possible

B) Open exported files in Finder and let the user manually share them

C) Build explicit integrations for Telegram, WhatsApp, and email inside the Mac app

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 11
How should photos taken during a recording be placed in the notes?

A) Insert image references at the nearest transcript timestamp based on capture time

B) Show photos in a separate timeline section only

C) Both inline at nearest transcript timestamp and in a separate media timeline

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 12
Should the Android app also support importing existing audio/images into a meeting session?

A) No — only live recording and camera capture in v1

B) Yes — allow adding existing images only

C) Yes — allow importing both existing audio and images

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 13
What privacy model should apply to transcripts, summaries, raw audio, and images?

A) Store everything encrypted at rest on the Mac and phone where retained

B) Rely on normal app sandbox/file-system storage for generated notes, but keep pairing keys secure

C) Ask per meeting whether to save encrypted/private or normal/shareable output

X) Other (please describe after [Answer]: tag below)

[Answer]: B
