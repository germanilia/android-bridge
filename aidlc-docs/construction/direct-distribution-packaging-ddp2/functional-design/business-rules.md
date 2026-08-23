# DDP2 business rules

## Version and platform rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-V01 | Installed, Release, and manifest versions use strict canonical `MAJOR.MINOR.PATCH`. | Invalid version; no update |
| DDP2-V02 | Release tag equals `v` plus manifest version. | Invalid Release metadata |
| DDP2-V03 | Manifest version code equals the DDP1 derivation. | Invalid manifest |
| DDP2-V04 | Update exists only when available version is numerically greater than installed version. | Equal/older reports current |
| DDP2-V05 | Schema 1 requires macOS minimum `13.0`; host must satisfy the minimum. | Unsupported platform |
| DDP2-V06 | DDP2 runs only on the existing Apple Silicon/macOS 13+ product target. | Build/runtime boundary violation |

## Release-selection rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-R01 | Discovery uses only the fixed `germanilia/android-bridge` latest-stable endpoint. | Reject request/source |
| DDP2-R02 | Drafts, prereleases, rolling tag `latest-build`, and malformed stable tags are never updates. | Invalid Release metadata |
| DDP2-R03 | Asset names in one Release are unique. | Duplicate asset |
| DDP2-R04 | Exactly one schema manifest, canonical versioned DMG, and matching checksum asset must exist in the same Release. | Missing or duplicate asset |
| DDP2-R05 | Manifest Mac name and size equal the selected Release asset name and size. | Asset metadata mismatch |
| DDP2-R06 | Aliases are ignored by update discovery; only the versioned canonical DMG is selected. | No fallback selection |
| DDP2-R07 | Manifest Android fields must be structurally valid even though DDP2 does not install Android artifacts. | Invalid complete schema |

## Metadata and URL rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-M01 | Manifest schema and descriptor key sets are exact; unknown or missing fields fail closed. | Invalid manifest |
| DDP2-M02 | SHA-256 is exactly 64 lowercase hexadecimal characters. | Invalid manifest/checksum |
| DDP2-M03 | All network requests and redirects use HTTPS with no embedded credentials or non-default port. | Untrusted URL |
| DDP2-M04 | Initial asset URLs bind exact repository, stable tag, and filename. | Untrusted URL |
| DDP2-M05 | Redirects are inspected and limited to fixed GitHub-controlled hosts. | Untrusted redirect |
| DDP2-M06 | HTTP success and configured response-size bounds are mandatory. | Network or bounds failure |
| DDP2-M07 | Response bodies and arbitrary URLs are not included in user-visible or diagnostic errors. | Safe generic diagnostic |

## Consent and download rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-D01 | Automatic discovery may fetch Release JSON and manifest only. | No update artifact side effect |
| DDP2-D02 | The checksum and DMG are fetched only after explicit `Download Update` consent. | Download blocked |
| DDP2-D03 | Every attempt owns a new unique temporary directory and newly created destination file. | Storage failure |
| DDP2-D04 | Checksum text exactly names the canonical DMG and equals the manifest digest. | Checksum metadata mismatch |
| DDP2-D05 | Download streams to disk and stops before accepting byte `expectedSize + 1`. | Download too large |
| DDP2-D06 | Final file size equals manifest and GitHub asset size. | Size mismatch |
| DDP2-D07 | Streamed local SHA-256 equals both manifest and checksum digest. | Digest mismatch |
| DDP2-D08 | A file path is not verified merely because it has a `.dmg` extension or came from GitHub. | Native handoff blocked |
| DDP2-D09 | Download cancellation is distinct from failure and never reports success. | Cancelled state and cleanup |

## Native handoff rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-O01 | AppKit receives only `VerifiedMacUpdate`, never `ReleaseAsset` or a raw downloaded URL. | Programming contract violation |
| DDP2-O02 | Opening the DMG does not replace, terminate, move, or alter the installed application. | Operation prohibited |
| DDP2-O03 | Successful open shows drag-to-Applications and Control-click then Open guidance plus the non-notarized limitation. | Guidance remains visible |
| DDP2-O04 | Open failure retains the verified path for current retry/reveal actions. | Actionable open error |
| DDP2-O05 | Dismissal or later cleanup deletes updater-owned verified data, not the installed app or user data. | Cleanup scoped to owned path |

## Startup and UI rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-U01 | Normal startup, dashboard rendering, and link services do not wait for update discovery. | Update task remains isolated |
| DDP2-U02 | At most one automatic check and one automatic prompt occur per app launch. | Duplicate call ignored |
| DDP2-U03 | Equal/newer installed version and transient automatic network failure show no launch dialog. | Settings status only |
| DDP2-U04 | Manual check always shows checking followed by update, current, or actionable failure status. | Visible manual result |
| DDP2-U05 | `Later` downloads nothing and permits a later manual check. | Return to idle |
| DDP2-U06 | Duplicate check/download actions are disabled while their operation is active. | Existing operation retained |
| DDP2-U07 | Progress is derived from validated expected size and received bytes. | Indeterminate only before body starts |
| DDP2-U08 | User-facing text identifies installed and available versions without claiming notarization or silent installation. | Corrected safe copy |

## Cleanup and preservation rules

| ID | Rule | Failure |
|---|---|---|
| DDP2-C01 | Partial and rejected attempt directories are removed immediately. | Cleanup error is reported safely |
| DDP2-C02 | Startup stale cleanup targets only updater-created directory names under the system temporary root. | General temp data untouched |
| DDP2-C03 | A new attempt cleans the controller's previous verified update first. | New attempt blocked if cleanup fails |
| DDP2-C04 | App termination cancels owned tasks and removes owned temporary artifacts where filesystem state permits. | Safe cleanup diagnostic |
| DDP2-C05 | Every discovery, download, validation, open, and cleanup failure leaves the installed app, privacy grants, settings, meetings, Second Brain, and paired-device data unchanged. | Current installation preserved |

## Error-presentation mapping

| Failure group | Automatic behavior | Manual or confirmed-update behavior | Safe next action |
|---|---|---|---|
| Network unavailable | Quiet; record Settings status | Show connection failure | Retry later |
| Invalid installed version | Quiet; record Settings status | Show local-version failure | Reinstall current stable DMG or retry after correction |
| Invalid Release/manifest | Quiet; block update | Show invalid update metadata | Do not download; retry later |
| Unsupported platform | Quiet; block update | Show unsupported update | Keep current installation |
| Missing/duplicate asset | Quiet; block update | Show incomplete Release | Retry after maintainer correction |
| Untrusted URL/redirect | Quiet; security log | Show download blocked | Do not bypass verification |
| Checksum/size/digest mismatch | Not applicable before consent | Delete attempt; show integrity failure | Retry later; do not open file |
| Cancellation | Not applicable before consent | Return to available or idle without failure claim | Check again later |
| Temporary storage failure | Quiet only if discovery cleanup | Show storage failure | Free space and retry |
| DMG open failure | Not applicable | Keep verified file for retry/reveal | Retry, reveal, or dismiss |

## Security baseline compliance

| Rule | DDP2 design status | Evidence |
|---|---|---|
| SECURITY-09 | Compliant | macOS 13+ Apple Silicon and existing locked Swift dependency set |
| SECURITY-10 | Compliant | No new framework; existing lock file remains authoritative |
| SECURITY-13 | Compliant | Same-Release binding, checksum agreement, exact size, and streamed SHA-256 before open |
| SECURITY-15 | Compliant | Typed fail-closed states, scoped cleanup, and no installed-app mutation |
| SECURITY-06 | N/A | DDP2 has no publication or permission-bearing CI job |
| SECURITY-12 | N/A | DDP2 reads public metadata and uses no secret |

Other security baseline rules remain not applicable because DDP2 introduces no datastore, account, hosted service, cloud network, or authentication boundary.

## Requirement traceability

| Requirement | Rules |
|---|---|
| FR-03 runtime guidance | DDP2-O02 through DDP2-O05, DDP2-U08 |
| FR-05 semantic comparison | DDP2-V01 through DDP2-V04 |
| FR-06 Mac update check | DDP2-R01 through DDP2-R07, DDP2-D01 through DDP2-D09, DDP2-U01 through DDP2-U08 |
| FR-08 integrity | DDP2-M01 through DDP2-M07, DDP2-D04 through DDP2-D08 |
| NFR-01 security | DDP2-M01 through DDP2-M07, DDP2-D02 through DDP2-D08 |
| NFR-02 reliability | DDP2-C01 through DDP2-C05 |
| NFR-03 usability | DDP2-U01 through DDP2-U08 and error mapping |
| NFR-04 compatibility | DDP2-V05, DDP2-V06, DDP2-C05 |
| NFR-05 maintainability | Fixed native boundaries and no external updater framework |
| AC-06 through AC-08 | Stable discovery, explicit consent, native-handoff gate, and rejection tests |
