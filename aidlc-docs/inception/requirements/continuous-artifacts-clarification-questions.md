# Continuous Build Artifact Clarification

Your latest-build requirement is clear: every successful push to `main` replaces a rolling `latest` prerelease, and the installer always uses that build.

The Android installation format still needs one decision.

## Question 1
Which APK should phone users receive?

A) Debug-signed APK — users can download and install it immediately after allowing installation from their browser; no secret setup is needed, but it is a development build

B) Production-signed release APK — users get a normal optimized release build, but you must create a signing keystore and add its encoded contents, alias, and passwords as GitHub repository secrets

X) Other (please describe after the [Answer]: tag below)

[Answer]: A — debug-signed APK; unsigned APKs cannot be installed on Android.
