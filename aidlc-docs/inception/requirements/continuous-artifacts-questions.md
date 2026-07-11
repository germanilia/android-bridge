# Continuous Build Artifact Questions

## Question 1
Which pushes should create compiled artifacts?

A) Every push to `main` only (recommended)

B) Every push to every branch

C) Pull requests and pushes to `main`

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Question 2
Where should artifacts from ordinary non-tag pushes be published?

A) Replace assets in a rolling `latest` prerelease so they remain directly downloadable (recommended)

B) Store them only as GitHub Actions run artifacts with retention limits

C) Create a permanent GitHub Release for every pushed commit

X) Other (please describe after the [Answer]: tag below)

[Answer]: A

## Question 3
Should the one-line macOS installer track stable tagged releases or the newest `main` build?

A) Stable tagged releases only (recommended)

B) Newest successful `main` build

C) Support both, with stable as default and an installer option for newest `main`

X) Other (please describe after the [Answer]: tag below)

[Answer]:  we always install the latest, no stable concept here

## Question 4
Which Android APK should be published?

A) Debug APK, unsigned for production distribution but immediately installable with ADB

B) Signed release APK using GitHub repository secrets

C) Both debug and signed release APKs

X) Other (please describe after the [Answer]: tag below)

[Answer]: somehitng uses can easily install on their phone
