# Direct distribution packaging clarification questions

Several answers did not select an option, and two requested behaviors conflict with current platform limits. Fill each `[Answer]:` tag with one option letter.

## Clarification 1
Question 1 was left empty. Which release model should the repo use?

A) Versioned stable GitHub Releases only

B) Versioned stable releases plus the existing rolling `latest-build` prerelease (recommended)

C) Keep only the rolling `latest-build` prerelease

X) Other (please describe after the [Answer]: tag below)

[Answer]: B

## Clarification 2
Your answers prefer CLI installation and say the Mac side should run as a service with UI. Which Mac product architecture do you mean?

A) Keep the existing native menu-bar and SwiftUI app, install it by CLI, and let it run in the background or at login (recommended, no rewrite)

B) Replace the native Mac app with a background daemon and browser-based local web UI (major rewrite)

C) Replace the native Mac app with a headless background service and no UI

X) Other (please describe after the [Answer]: tag below)

[Answer]: im sory native mac app wno paid account so whatever can be done there.

## Clarification 3
Which CLI installation channel should be primary on Mac?

A) Existing `curl -fsSL .../install.sh | bash` command hosted on GitHub (recommended, smallest change)

B) An npm package installed with `npm install -g`

C) A Homebrew tap installed with `brew install`

D) GitHub shell installer plus an npm wrapper

X) Other (please describe after the [Answer]: tag below)

[Answer]: no cli native app as I have installed here.

## Clarification 4
Every APK must be cryptographically signed, including APKs installed manually outside a marketplace. Which signing method should direct Android downloads use?

A) A dedicated long-lived release keystore, kept out of Git and supplied to GitHub Actions through secrets (recommended)

B) The current debug key, which can change and can break future updates

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Clarification 5
"Whatever is safe" maps to the current Android 13 minimum because existing permission and background-service behavior is already designed for it. Confirm support range.

A) Keep Android 13 and newer (recommended)

B) Expand to Android 10 and newer, with added compatibility implementation and testing

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Clarification 6
How should Mac updates behave?

A) Check GitHub Releases, verify the artifact, install it automatically in the background, and notify only on failure or required action

B) Check GitHub Releases and ask before downloading or installing

C) No update checker; users rerun the CLI installer manually

X) Other (please describe after the [Answer]: tag below)

[Answer]: B

## Clarification 7
Android blocks ordinary sideloaded apps from installing APK updates silently. Which feasible Android update behavior should the optional phone app use?

A) Check GitHub Releases, download a verified APK, then open Android's required installation confirmation (recommended)

B) Show an update notification that opens the browser download page

C) No update checker; users download updates manually

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Clarification 8
Which Mac hardware should the CLI-installed service and UI support initially?

A) Apple Silicon only, matching the current code and local ML tooling (recommended)

B) Apple Silicon and Intel through a universal build, with additional compatibility work

X) Other (please describe after the [Answer]: tag below)

[Answer]: we support only silicon for now
