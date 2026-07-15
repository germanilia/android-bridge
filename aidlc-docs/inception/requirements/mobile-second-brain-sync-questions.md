# Mobile Second Brain Sync Requirements Questions

Please answer each question by filling the letter after the `[Answer]:` tag. If none match, choose Other and describe.

## Question 1
What should the Android app support for Second Brain nodes in this increment?

A) View-only: browse node tree and read node contents on Android

B) View + create/edit/delete nodes on Android

C) View + edit existing nodes only, no create/delete

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 2
What source of truth should resolve conflicts when both Mac and Android changed the same node while disconnected?

A) Mac wins; Android keeps a conflict copy for review

B) Android wins; Mac keeps a conflict copy for review

C) Keep both versions as conflict files and require manual merge on Mac

D) Last-write-wins using device timestamps

X) Other (please describe after [Answer]: tag below)

[Answer]: D

## Question 3
What node formats must the Android app display and sync?

A) Markdown files only (`.md`)

B) Markdown and plain text files (`.md`, `.txt`)

C) All files under Second Brain as attachments, with preview only for Markdown/text

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 4
How much of the Second Brain should be stored on Android for offline use?

A) Full tree and all supported node contents

B) Full tree, contents downloaded on demand and cached

C) Only selected folders/nodes marked for offline sync

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
When connected to Mac, how often should background sync run?

A) Every 2 minutes

B) Every 5 minutes

C) Every 10 minutes

D) Only on app open/connect plus manual refresh

X) Other (please describe after [Answer]: tag below)

[Answer]: every 2 minutes from phone to mac and vise versa and sync now button.

## Question 6
Should Android push pending local changes automatically when the Mac connection is restored?

A) Yes, automatically push all queued changes

B) Ask before pushing queued changes

C) Push view/edit metadata automatically, ask before content changes

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 7
How should the Mac app use the Second Brain skill during sync?

A) Mac skill remains the only filesystem writer/reader; Android requests operations through Mac

B) Android receives a synced local copy and Mac skill only resolves merges/conflicts

C) Mac skill indexes/searches/summarizes, but raw file sync uses app protocol directly

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 8
What search behavior is required on Android?

A) Local filename/title search only

B) Local filename/title and content search over synced nodes

C) Query Mac Second Brain skill when connected; local search when offline

X) Other (please describe after [Answer]: tag below)

[Answer]: B

## Question 9
Should Second Brain sync be encrypted and authenticated using the existing paired-device secure channel only?

A) Yes, only over existing paired secure channel

B) Allow insecure local development mode too

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 10
What UI location should this feature use on Android?

A) Add a new Second Brain tab/screen in the current Android app

B) Add it under existing Notes/Meetings area if present

C) Add a Settings toggle first; UI only after sync is enabled

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 11: Security Extensions
Should security extension rules be enforced for this feature increment?

A) Yes — enforce all SECURITY rules as blocking constraints (recommended for production-grade applications)

B) No — skip all SECURITY rules (suitable for PoCs, prototypes, and experimental projects)

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 12: Resiliency Extensions
Should the resiliency baseline be applied to this feature increment?

A) Yes — apply the resiliency baseline as directional best practices and design-time guidance

B) No — skip the resiliency baseline

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 13: Property-Based Testing Extension
Should property-based testing (PBT) rules be enforced for this feature increment?

A) Yes — enforce all PBT rules as blocking constraints

B) Partial — enforce PBT rules only for pure functions and serialization round-trips

C) No — skip all PBT rules

X) Other (please describe after [Answer]: tag below)

[Answer]: A
