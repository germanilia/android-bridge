# Background clipboard automation questions

Android 10 and newer intentionally block ordinary background apps—even foreground services—from reading another app's clipboard. Android Bridge therefore cannot automatically send phone copies while closed using safe standard APIs. The realistic safe improvement is automatic receipt from the Mac plus automatic phone sending whenever Android Bridge is visible.

Reference: [Android secure clipboard handling](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling?hl=en).

## Question 1
How should clipboard text received from the Mac behave on Android?

A) When Auto Sync is enabled, copy it immediately with no Android Bridge notification; when Auto Sync is disabled, keep the Copy notification but make it expire after eight seconds (recommended)

B) Always copy it immediately, even when Auto Sync is disabled

C) Never copy automatically; keep the Copy notification but make it expire after eight seconds

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 2
How should phone-to-Mac sending handle Android's platform restriction?

A) Keep the safe standard implementation: auto-send while Android Bridge is focused, plus explicit silent Share actions when it is in the background; do not add invasive or unreliable background workarounds (recommended)

B) Add a separate Android Bridge keyboard and require making it the default keyboard so it can read clipboard data in the background

X) Other (please describe after [Answer]: tag below)

[Answer]:

## Question 3
What explicit phone-to-Mac sharing flow should be added?

A) Add a no-display Android Bridge Share target for text, one file, or multiple files, plus a `Share with Mac` text-selection action; text replaces the Mac clipboard, while received files are saved and placed on the Mac clipboard for immediate paste (recommended)

B) Make the existing Android Bridge Share target silent for text and files, but do not place received files on the Mac clipboard or add a text-selection action

X) Other (please describe after [Answer]: tag below)

[Answer]:
