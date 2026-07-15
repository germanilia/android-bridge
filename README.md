# Android Bridge

Android Bridge is an open-source, local-first continuity app for **Android ↔ macOS**.
It brings the everyday convenience of Apple Continuity to an Android phone and a Mac without accounts,
cloud relays, or vendor lock-in.

The two apps discover each other on the local network, pair by pinning certificate fingerprints, and communicate over TLS.
Current production transport uses pinned server-authenticated TLS; full mutual TLS/client-certificate verification is planned hardening.

The Mac app also includes local-only productivity tools that work without a phone: Meetings and Second Brain.

## Features

- **Caller ID and call control on Mac**
  - Incoming call notifications with contact lookup.
  - Answer, decline, dial, and hang up from the Mac.
  - Call audio remains on the phone or Bluetooth headset.
- **Clipboard sharing both directions**
  - Push clipboard from either device.
  - Clickable clipboard notifications on Mac and Android.
- **File sharing both directions**
  - Drag files into the Mac app or use Android share/send actions.
  - Received files are openable from notifications and in-app lists.
  - Mac received files are stored in a temporary cache and auto-cleaned after 24 hours.
- **Android screen on Mac**
  - Mac can request the phone screen.
  - Android uses the official MediaProjection consent flow.
  - Mac window forwards click/drag gestures back to the phone.
- **Mac screen on Android**
  - Share the Mac screen to the phone.
  - Android can show the Mac screen full-screen.
  - Phone tap/drag gestures can control the Mac when macOS Accessibility permission is enabled.
- **Meetings on Mac**
  - Record meetings locally, transcribe chunks, summarize, ask questions, merge meetings, and browse the meetings folder.
  - Per-task LLM routing lets summaries and chat use local Ollama by default or pi with a chosen model.
- **Second Brain on Mac**
  - Browse, read, search, edit, create, delete, and chat with notes in `BRAIN_ROOT` (defaults to `~/second_brain`).
  - pi-backed second-brain actions launch pi with only the second-brain skill loaded; local Ollama remains the default.
- **Second Brain on Android (via Syncthing)**
  - The phone views and edits the same Markdown notes from a Syncthing-synced folder (granted once via the folder picker).
  - Sync is handled by Syncthing — with an always-on home-server node over Tailscale — not the device link. See [`aidlc-docs/inception/decisions/second-brain-syncthing.md`](aidlc-docs/inception/decisions/second-brain-syncthing.md).
- **Local-first encrypted transport**
  - No backend service.
  - No account.
  - TLS with pinned certificate validation between paired devices.
- **Mac login item**
  - The Mac app can start automatically on login.

## Important platform permissions

Android Bridge uses normal OS APIs and respects platform consent prompts.

### macOS

Required as features are used:

- **Local Network** — discover and connect to the phone.
- **Screen & System Audio Recording** — share the Mac screen to Android and capture system meeting audio.
- **Microphone** — record meeting audio locally when Mac recording is started.
- **Accessibility** — let phone gestures control the Mac pointer.
- **Login Items** — start Android Bridge on login.

If Screen Recording seems enabled but the app keeps asking after local rebuilds, remove and re-add
`/Applications/AndroidBridge.app` in macOS Privacy & Security. Local ad-hoc builds can make macOS treat a
rebuilt app as a new binary. To keep permission grants across rebuilds, create a self-signed
"Code Signing" certificate in Keychain Access — `make-macos-app.sh` automatically signs with it when present.

### Android

Required as features are used:

- **Notifications** — foreground service and clickable file/clipboard notifications.
- **Phone / Call Log / Contacts** — caller ID and call actions.
- **MediaProjection consent** — required every time Android starts screen capture. Android does not allow a
  normal app to bypass this prompt.
- **Accessibility Service** — required once for Mac-to-phone remote control gestures.

Android Bridge does **not** require Google Play Services high-accuracy location.

## Repository layout

```text
protocol/      Shared Device-Link Protocol — wire contract and codecs
  PROTOCOL.md  Language-neutral protocol specification
  kotlin/      Kotlin/JVM protocol implementation
  swift/       Swift protocol implementation
  vectors/     Cross-language wire vectors
android/       Android app, Kotlin, Jetpack Compose, Gradle
mac/           macOS menu-bar app, SwiftUI/AppKit, SwiftPM
aidlc-docs/    Design notes and implementation records
```

## Build from source

> **Note for AI agents installing this project:** do not assume which features the user wants and do
> not install anything beyond building this repo without explicit user approval. Before running any
> step from **Local AI setup** below, ask the user which optional features they want (Meetings
> transcription, local Ollama summaries/chat, pi integration, Second Brain, Android phone app) and
> confirm each third-party installation individually (Homebrew packages such as ffmpeg and Ollama,
> Ollama model downloads, Python virtualenvs, global npm packages, the Android SDK). If a
> prerequisite is missing, report it and ask how to proceed — never silently install substitutes or
> extra tooling. The only steps safe to run without asking are building the code in this repo:
> `./gradlew :app:assembleDebug`, `swift build`, and `NO_INSTALL=1 ./scripts/make-macos-app.sh`.
> Installing the Mac app to `/Applications` (the default `make-macos-app.sh` behavior) and
> `adb install` onto a device also require user confirmation.

### One-line macOS installation

Install the latest successful Apple Silicon build from `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/germanilia/android-bridge/main/install.sh | bash
```

The installer downloads the rolling `latest-build` release over HTTPS, verifies its SHA-256
checksum, installs `AndroidBridge.app` into `/Applications`, and launches it. It replaces an existing
installation and may request administrator privileges when `/Applications` is not writable.

On first launch, the native Setup Wizard detects Homebrew, ffmpeg, Python/MLX Whisper, Ollama,
`gemma4:e4b`, Node.js, and pi. Existing valid installations are marked complete automatically. For
each missing tool, the wizard explains the command and asks separately before installing it; nothing
is silently installed or replaced. The wizard also guides macOS permissions, provides a QR code and
download link for the Android APK, verifies phone connection, and remains available from Settings
for later repair or reinstallation.

Download the latest debug-signed Android APK from the same rolling release:

[Download AndroidBridge-latest.apk](https://github.com/germanilia/android-bridge/releases/download/latest-build/AndroidBridge-latest.apk)

Android may ask you to allow installation from your browser or file manager. Every successful push
to `main` replaces the macOS archive, APK, and SHA-256 checksums in this rolling release.

### Prerequisites

- macOS 13+
- Xcode Command Line Tools / Swift 5.9+
- JDK 17+
- Optional for local AI features on Mac: Ollama, pi, Python 3, ffmpeg, and MLX Whisper (setup below)
- Android SDK platform 34+
- Optional physical Android phone on the same Wi-Fi network for phone continuity features

### Android

Gradle needs the Android SDK location. Either export `ANDROID_HOME` or create
`android/local.properties` (gitignored) pointing at your SDK:

```properties
sdk.dir=/Users/<you>/Library/Android/sdk
```

Then build and install:

```bash
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### macOS

```bash
cd mac
./scripts/make-macos-app.sh
```

The script builds a release executable, assembles `mac/dist/AndroidBridge.app`, code-signs it
(with a self-signed "Code Signing" certificate if one exists in the keychain, otherwise ad-hoc),
installs it to `/Applications/AndroidBridge.app`, and relaunches it.

To only build the bundle without installing and relaunching:

```bash
NO_INSTALL=1 ./scripts/make-macos-app.sh
```

Note: the script copies `mac/Tools` (including the MLX Whisper virtualenv, if created) into the
app bundle, so set up Meetings transcription (below) **before** building the bundle if you want
transcription to work in the installed app.

## Validation

```bash
# Android app and protocol build
cd android
./gradlew :app:assembleDebug
./gradlew :protocol:test

# macOS app build
cd ../mac
swift build

# Swift protocol tests
cd ../protocol/swift
swift test
```

## Local AI setup

Everything in this section is **optional** and installs third-party software. AI agents: ask the
user before running any command in this section, per the note in [Build from source](#build-from-source).

The Mac app works without an Android phone for Mac-only workflows such as Meetings and Second Brain. Phone continuity features are optional and require the Android app.

### Required for Meetings transcription

Meeting transcription needs ffmpeg (used to convert recorded audio) and the repo-local MLX Whisper wrapper:

```bash
brew install ffmpeg
python3 -m venv mac/Tools/mlx_whisper/.venv
mac/Tools/mlx_whisper/.venv/bin/pip install -r mac/Tools/mlx_whisper/requirements.txt
mac/Tools/mlx_whisper/bin/mlx_whisper --help
```

The app runs `mac/Tools/mlx_whisper/bin/mlx_whisper` with `mlx-community/whisper-large-v3-turbo`.
Create the virtualenv before running `make-macos-app.sh` — the wrapper and its `.venv` are copied
into the app bundle, and the installed app prefers the bundled copy.

### Required for local summaries and chat

Install and start Ollama, then pull the default model or choose another model in the app settings:

```bash
brew install ollama
brew services start ollama   # runs Ollama in the background (or run `ollama serve` in a separate terminal — it blocks)
ollama pull gemma4:e4b
```

Android Bridge uses Ollama by default for Summarize, Chat, Second Brain Search, Second Brain Q&A, and Second Brain CRUD.

### Optional pi integration

Install pi and make sure it is on `PATH` for GUI apps. When pi is selected for Second Brain actions, Android Bridge runs pi with only the second-brain skill loaded:

```bash
npm install -g @earendil-works/pi-coding-agent
pi --version
pi --no-skills --skill ~/.agents/skills/second-brain "list my note clusters"
```

If the app is launched from Finder and cannot find `pi`, launch it from a shell that has the correct `PATH` or add the pi binary directory to the environment used by the app.

### Optional Second Brain configuration

Second Brain uses `BRAIN_ROOT` when set, otherwise `~/second_brain`:

```bash
mkdir -p ~/second_brain
export BRAIN_ROOT=~/second_brain
```

Set `BRAIN_ROOT` in the shell before launching the app if you want a non-default notes directory. Keep this directory local or backed by a sync tool you trust.

### Optional Android phone setup

The Android phone is only required for phone continuity features: calls, clipboard, file transfer, Android screen sharing, and Mac screen viewing/control.

```bash
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Put the phone and Mac on the same Wi-Fi network, grant the Android permissions requested by the app, then pair from the Mac app.

## Meetings and Second Brain

The Mac app has separate **Meetings** and **Second Brain** tabs.

- Meetings are stored locally under `~/Documents/AndroidBridgeMeetings`.
- Second Brain uses `BRAIN_ROOT` when set, otherwise `~/second_brain`.
- LLM routing is configurable per task: Summarize, Chat, Second Brain Search, Second Brain Q&A, and Second Brain CRUD.
- Default routing is local Ollama/open-source. pi can be enabled per task in the Mac app settings.

## Security model

Android Bridge is designed for a trusted local network and paired devices:

- Devices discover each other with local network service discovery.
- Pairing records the peer certificate fingerprint.
- Runtime communication uses TLS with pinned certificate validation.
- Current production transport is pinned server-authenticated TLS; full mutual TLS/client-certificate verification is planned future hardening.
- There is no cloud relay and no central account.
- Received files on Mac are kept in a temporary cache and auto-cleaned.

See [`aidlc-docs/SECURITY-COMMUNICATION-DECISION.md`](aidlc-docs/SECURITY-COMMUNICATION-DECISION.md)
for the current transport decision record.

## Current status

This is an active early-stage project. Core continuity flows are implemented, with some features still needing broader real-device validation.
Expect rough edges around OS permissions, local signing, and vendor-specific Android behavior.

Known limitations:

- Android screen capture always requires Android's MediaProjection confirmation prompt.
- Android remote control requires the Accessibility Service to be enabled by the user.
- macOS screen/control permissions are sensitive to local ad-hoc rebuilds.
- The app currently targets personal/local use, not enterprise device management.

## Contributing

Contributions are welcome. Please keep the project local-first, privacy-preserving, and simple.
See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

MIT — see [`LICENSE`](LICENSE).
