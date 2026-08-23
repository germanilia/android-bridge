# NFR Design Patterns — MCAL1

## Queue Isolation

Capture stop mutates lightweight state synchronously, then expensive processing executes on existing serial background queues. Network message routing returns before finalization starts.

## Durable State Marker

Processing state and end time are stored beside meeting media. On launch, stale finalizing markers become retryable attention states.

## Local Snapshot

Selected EventKit objects are converted to bounded Codable values. EventKit objects never cross into persistence/UI domains.

## Fail-Safe Permission Boundary

Denied or failed calendar reads return an explicit local error state and apply no metadata. Other meeting features continue.

## Conservative Enrichment

Automatic writes only fill generic/empty values. User edits always win. Ambiguity produces choices, not guesses.

## Explicit Side Effect

Second Brain remains a user-triggered side effect and is removed from automatic completion.

## Privacy by Minimization

Only event fields needed for display/matching are snapshotted. No event notes/body are imported. Sensitive data is excluded from logs.
