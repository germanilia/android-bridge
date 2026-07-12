# Fresh Mac Installation Wizard Questions

## Question 1
Which optional capabilities must the fresh-Mac setup install?

A) Everything currently supported: ffmpeg, Python/MLX Whisper, Ollama, the default local model, and pi

B) Local-only stack: ffmpeg, Python/MLX Whisper, Ollama, and the default local model; skip pi

C) Meetings stack only: ffmpeg and Python/MLX Whisper

X) Other (please describe after the [Answer]: tag below)

[Answer]:  A

## Question 2
Where should the wizard run?

A) Inside Android Bridge on first launch, with a reusable Setup screen in Settings (recommended)

B) Entirely in the terminal installation script

C) Terminal installer for dependencies plus an in-app wizard for permissions, phone pairing, and verification

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Question 3
How should third-party dependencies be installed when missing?

A) Automatically through Homebrew after one clear confirmation; install Homebrew first when missing

B) Show commands and let the user run each installation manually

C) Ask separately before installing each dependency

X) Other (please describe after the [Answer]: tag below)

[Answer]: C

## Question 4
Should setup include the Android phone app?

A) Yes — wizard shows a QR code/download link for the latest APK and guides installation and pairing

B) No — Mac dependencies and permissions only

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Question 5
How should already-installed items behave?

A) Detect valid installations and mark them complete without prompting; offer an explicit reinstall/repair action (recommended)

B) Detect and skip silently with no repair option

X) Other (please describe after the [Answer]: tag below)

[Answer]: A
