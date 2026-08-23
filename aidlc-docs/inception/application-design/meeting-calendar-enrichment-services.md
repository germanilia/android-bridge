# Services — Meeting Completion and Calendar Enrichment

## Stop and Finalize Flow

1. Stop capture and persist end time.
2. Mark meeting `Finalizing` and refresh UI immediately.
3. Drain already queued chunk transcription on the existing serial processing queue.
4. Finalize notes in the background.
5. Mark `Ready`, refresh UI, and asynchronously query EventKit.
6. If finalization cannot complete, retain media and mark `Needs Attention`.

## Calendar Enrichment Flow

1. Request EventKit read access when needed.
2. Query events overlapping saved start/end timestamps.
3. Convert results to local snapshots and run pure overlap matching.
4. Zero results: keep manual metadata unchanged.
5. One result: persist snapshot and fill only generic/empty title and empty customer.
6. Multiple results: publish candidates for inline user selection or manual entry.
7. Permission/fetch failure: show passive status and retry/settings actions; meeting remains ready.

## Second Brain Flow

1. Never run during automatic meeting completion.
2. User invokes the existing meeting-level Second Brain action.
3. Prefill saved title/customer.
4. Canonicalize customer and perform the existing idempotent transfer.
5. Keep local meeting usable if transfer fails.
