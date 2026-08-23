# Direct distribution packaging questions

Current repo already publishes a rolling macOS ZIP and debug-signed Android APK through GitHub Releases. The macOS build is not Apple-notarized, and the Android artifact is not production release-signed. macOS Gatekeeper and Android's "Install unknown apps" consent cannot be bypassed without an app marketplace or device management.

Fill each `[Answer]:` tag with one option letter. Use `X` when none fits.

## Question 1
Which release model should the prepared repo support?

A) Versioned stable GitHub Releases only, built from tags

B) Versioned stable releases plus the existing rolling `latest-build` prerelease (recommended)

C) Keep only the rolling `latest-build` prerelease

X) Other (please describe after the [Answer]: tag below)

[Answer]:

## Question 2
What should be the primary macOS download format?

A) Apple-signed and notarized DMG with drag-to-Applications installation (recommended)

B) Apple-signed and notarized PKG with the standard macOS installer

C) Keep the current ZIP plus terminal installer as the primary path

X) Other (please describe after the [Answer]: tag below)

[Answer]: I preffer to have cli installatoin, github or npm

## Question 3
What Apple signing and notarization capability will the release use?

A) An active Apple Developer Program account and Developer ID credentials are available

B) The account and credentials are not ready yet, but the repo should be prepared for them

C) No paid Apple account; accept Gatekeeper warnings for direct downloads

X) Other (please describe after the [Answer]: tag below)

[Answer]: C

## Question 4
How should public Android APKs be signed?

A) Create a dedicated long-lived release keystore and store its values in GitHub Actions secrets (recommended)

B) Use an existing long-lived Android release keystore

C) Continue publishing debug-signed APKs

X) Other (please describe after the [Answer]: tag below)

[Answer]: no public it will be installed manually we nvever publish ot hte market.

## Question 5
Which Android versions should the public package support?

A) Keep the current Android 13 and newer requirement

B) Expand support to Android 10 and newer, accepting extra compatibility work

C) Support only the latest Android version

X) Other (please describe after the [Answer]: tag below)

[Answer]: what ever is sage to support based on the features.

## Question 6
Is the normal direct-APK installation flow acceptable?

A) Yes. User downloads the APK, allows "Install unknown apps" for that source once, then taps Install (recommended without a marketplace)

B) No. Distribution is limited to privately managed devices using ADB or mobile-device management

X) Other (please describe after the [Answer]: tag below)

[Answer]: a but apk is optional not all users will want it

## Question 7
How should updates work after initial installation?

A) Users manually download each new stable release

B) Apps check GitHub Releases and show an update prompt that opens the direct download (recommended)

C) Only document the latest download links; no update checks or prompts

X) Other (please describe after the [Answer]: tag below)

[Answer]: app checks and silently updates and let's the user know about failures

## Question 8
Which Mac hardware should the first public package support?

A) Apple Silicon only, matching the current app and local ML tooling (recommended)

B) Produce a universal Apple Silicon and Intel package

X) Other (please describe after the [Answer]: tag below)

[Answer]: we don't create actual mac app, it will be a service running on th emachine servie ui

## Question 9
Should security extension rules remain enforced for this distribution work?

A) Yes, enforce all security rules as blocking constraints (recommended for public releases)

B) No, disable security rules for this increment

X) Other (please describe after the [Answer]: tag below)

[Answer]: a

## Question 10
Should the resiliency baseline be applied to this distribution work?

A) Yes, apply resiliency design guidance

B) No, keep it disabled for this local app distribution increment (recommended)

X) Other (please describe after the [Answer]: tag below)

[Answer]: b

## Question 11
Should property-based testing rules remain partially enforced?

A) Yes, retain partial enforcement for pure functions and serialization round trips

B) No, disable property-based testing rules for this distribution-only increment (recommended)

C) Yes, enforce the full property-based testing baseline

X) Other (please describe after the [Answer]: tag below)

[Answer]: b
