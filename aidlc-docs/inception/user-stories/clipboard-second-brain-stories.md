# Clipboard and Second Brain reliability stories

## CSR-US-1: Control clipboard sharing

As the Owner-User, I want clipboard Auto Sync off by default with a persistent toggle on each device, so copying sensitive text does not share it unexpectedly.

### Acceptance criteria

- Given a fresh installation, when either app starts, then Auto Sync is off.
- Given Auto Sync is changed, when the app relaunches, then the choice persists.
- Given Auto Sync is off, when local clipboard content changes, then nothing sends automatically.
- Given either mode, when Push Clipboard is selected while connected, then current text sends.

## CSR-US-2: Copy Mac text safely on Android

As the Owner-User, I want an inbound clipboard notification with a Copy action, so I control when Mac text replaces my phone clipboard.

### Acceptance criteria

- Given connected devices, when Mac text arrives, then Android posts a private notification without showing the text.
- Given the notification, when Copy is selected, then Android writes the received text to its system clipboard.
- Given inbound text, when activity history updates, then it contains no copied content.

## CSR-US-3: See current Second Brain entries

As the Owner-User, I want each open Second Brain view to notice local Syncthing file changes, so new or edited Markdown appears without manual recovery.

### Acceptance criteria

- Given the Mac tab is visible, when a local Markdown file changes, then the tree refreshes.
- Given the Android tab is visible, when Syncthing changes the granted folder, then the tree refreshes within the visible polling interval.
- Given an editor has unsaved text, when a refresh runs, then the draft is not overwritten.
- Given manual Refresh, when selected, then both tree and selected persisted content reload.

## CSR-US-4: Understand refresh and write failures

As the Owner-User, I want folder, note count, refresh time, and errors in both apps, so I can distinguish an app-view problem from a Syncthing problem.

### Acceptance criteria

- Given a successful refresh, then the app shows folder, note count, and refresh time.
- Given a file operation fails, then the app reports failure and never claims Saved.
- Given a root setting changes on Mac, then the next refresh uses the new root.

## INVEST check

- Independent enough for focused verification.
- Negotiable UI wording, fixed behavior.
- Valuable to the Owner-User.
- Estimable within existing components.
- Small enough for one repair increment.
- Testable with unit/build checks plus connected-phone verification.
