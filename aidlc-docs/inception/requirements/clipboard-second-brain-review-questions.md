# Clipboard and Second Brain review questions

Current code review found two separate areas:

- Clipboard runtime behavior does not match its documented manual-default policy. Mac copies are sent automatically, Android copies are sent only while the app is in the foreground, and Mac-to-Android updates do not reach the Android system clipboard.
- Second Brain file transfer belongs to Syncthing, not Android Bridge. Both apps read local folders but refresh them only on initial load or manual refresh, so Syncthing can finish while either app still shows an old tree or old note content.

Please answer every question by placing the option letter after `[Answer]:`. For Question 5, add one example path or note title and approximate creation time when possible.

## Question 1
What clipboard privacy model should both apps use?

A) Manual by default, with a persistent per-device Auto Sync toggle (recommended)

B) Fully automatic in both directions whenever each OS permits it

C) Automatic Mac-to-phone, manual phone-to-Mac

D) Manual-only with no automatic mode

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 2
How should a clipboard update arriving on Android behave?

A) Show a notification with a Copy action and retain the value in the app (recommended default)

B) Replace the Android system clipboard automatically whenever Android permits it

C) Make A or B selectable in Settings

D) Keep it only inside Android Bridge

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 3
Which clipboard payloads belong in this improvement?

A) Text only, with clear size limits and errors (recommended)

B) Text and images

C) Text plus copied files, using the existing file-transfer path

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 4
How fresh should the Second Brain views be?

A) Refresh on tab opening, app foregrounding, and detected local-folder changes; retain manual Refresh (recommended)

B) Refresh periodically while the tab is visible

C) Refresh only when the user presses Refresh

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 5
Where do new Second Brain entries fail to appear?

A) Created on phone, missing from Mac

B) Created on Mac, missing from phone

C) Created elsewhere or on the home server, missing from one or both apps

D) Multiple directions or intermittent behavior

X) Other (please describe after [Answer]: tag below)

[Answer]: D — original report says new entries are stale in both phone and Mac apps; exact example will be collected during hardware verification.

## Question 6
What sync and refresh status should Android Bridge show?

A) Local folder, last app refresh, note count, detected changes, and actionable errors on both apps (recommended)

B) Only a simple Fresh or Stale state

C) No extra status; refresh silently

X) Other (please describe after [Answer]: tag below)

[Answer]: A

## Question 7
What should happen after this review is approved?

A) Implement and test both clipboard and Second Brain fixes (recommended)

B) Produce a review and implementation plan only

C) Implement clipboard fixes only

D) Implement Second Brain fixes only

X) Other (please describe after [Answer]: tag below)

[Answer]: A
