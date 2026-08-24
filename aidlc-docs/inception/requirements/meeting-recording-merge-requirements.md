# Meeting Recording Merge Requirements

## Intent

Add a Mac meeting action that combines a meeting's saved audio chunks into one playable recording.

## Requirements

- The action is available when a completed meeting has at least two source audio chunks.
- Source chunks remain unchanged; the generated file is additional, replaceable output.
- Source order follows the meeting's existing deterministic audio-file order.
- The generated file is `media/merged-recording.m4a` and is replaced atomically after a successful export.
- A previous `merged-recording.m4a` is never included as an input.
- Export uses native macOS media APIs and does not require FFmpeg or network access.
- Failure leaves source files and any prior successful merged recording unchanged and surfaces a user-visible event.
- Success refreshes the meeting and reveals the merged recording in Finder.
- Tests cover fewer-than-two inputs, deterministic source selection, and successful native audio export.

## Scope

Mac meeting storage and meeting-detail UI only. No source deletion, destructive conversion, Android audio merge, transcript merge changes, or relay behavior changes.
