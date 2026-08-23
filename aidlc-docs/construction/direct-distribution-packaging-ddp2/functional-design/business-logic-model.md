# DDP2 business logic model

## Fixed trust inputs

- Repository: `germanilia/android-bridge`.
- Discovery endpoint: `https://api.github.com/repos/germanilia/android-bridge/releases/latest`.
- Update channel: latest stable Release only.
- Manifest schema: DDP1 schema 1.
- Supported runtime: macOS 13 or newer on Apple Silicon.
- Native handoff: open a verified DMG with AppKit; never replace the running application.

No runtime setting can change the repository, channel, manifest URL, expected digest, or approved download hosts.

## Stable discovery

### Inputs

- Installed `CFBundleShortVersionString`.
- Fixed Release endpoint.
- Injected release client for testability.

### Algorithm

1. Parse the installed version strictly before making an update decision.
2. Request the fixed latest-stable endpoint asynchronously.
3. Require HTTP success and a bounded JSON response.
4. Decode the Release with exact required field types.
5. Require `draft == false`, `prerelease == false`, and a strict stable tag.
6. Require unique asset names and exactly one `release-manifest.json` asset.
7. Validate the manifest URL against the fixed repository, tag, asset name, HTTPS policy, and approved GitHub hosts.
8. Fetch and strictly decode the bounded manifest.
9. Require schema 1 and exact top-level and descriptor keys.
10. Require manifest version, derived version code, and Release tag to agree.
11. Require macOS minimum `13.0` and confirm the running host meets it.
12. Derive the exact versioned DMG and checksum names from the manifest version.
13. Locate exactly one same-Release asset for each derived name.
14. Require manifest name and size to equal the selected DMG asset metadata.
15. Validate release-page and download URLs as same-repository, same-tag HTTPS URLs.
16. If available version is greater than installed version, return `MacUpdate`.
17. Otherwise return `upToDate`; a downgraded or equal Release never prompts.

Discovery downloads metadata only. It does not create an update directory or download the checksum or DMG.

## URL and redirect validation

### Initial URLs

- API URL is compiled into the client.
- Release page must be an HTTPS `github.com` URL for the fixed repository and tag.
- Manifest, checksum, and DMG initial URLs must be HTTPS `github.com` Release download URLs for the fixed repository, exact tag, and exact asset filename.
- URLs with credentials, a non-default port, query mutation, fragment, encoded path traversal, or a mismatched repository/tag/name are rejected.

### Redirects

- Redirects may remain on HTTPS GitHub-controlled release-asset hosts only.
- Each redirect is inspected before following it.
- Redirects to HTTP, credentials-bearing URLs, non-default ports, or non-approved hosts are rejected.
- The final response URL must remain inside the approved host policy.

The concrete approved-host set and bounded response sizes are fixed during DDP2 NFR Design; they are not user configurable.

## Automatic check

1. Complete normal application startup and render the dashboard.
2. Schedule exactly one launch check through `MacUpdateController`.
3. Set state to `checking(manual: false)` without blocking the main thread.
4. Run stable discovery in an asynchronous task owned by the controller.
5. If a newer version exists, present one update-available dialog.
6. If current is equal/newer, return to idle without a dialog.
7. If a transient network failure occurs, return to idle and retain safe status for Settings.
8. If trusted metadata is invalid, block update use, record the failure for Settings, and do not show an unsolicited startup error dialog.

Dismissal suppresses another automatic prompt for the current launch. A manual check remains available.

## Manual check

1. The Settings action invokes the same discovery path with `manual: true`.
2. Show visible checking state and disable duplicate check/download actions.
3. If a newer version exists, present the same consent dialog.
4. If current is equal/newer, show an explicit up-to-date result.
5. Show any network, metadata, compatibility, or storage failure with a safe retry action.

If a manual request arrives during an automatic check, it promotes the existing check to visible/manual presentation instead of starting duplicate network work.

## Consent and download

### Preconditions

- A validated `MacUpdate` exists.
- No download is already active.
- The user selects `Download Update`.

### Algorithm

1. Create one unique updater-owned directory under the system temporary directory.
2. Fetch the checksum asset after consent.
3. Require a bounded UTF-8 file containing exactly lowercase SHA-256, two spaces, canonical DMG name, and newline.
4. Require checksum digest to equal the manifest digest.
5. Start the DMG download into a newly created file in the owned directory.
6. If `Content-Length` exists, require it to equal the expected size before accepting body bytes.
7. Stream bytes to disk; never buffer the full DMG in memory.
8. Stop immediately if received bytes exceed the manifest size.
9. Report progress as received bytes divided by expected bytes.
10. On completion, require a regular file with exact expected size.
11. Compute SHA-256 by streaming the local file.
12. Require local digest to equal both manifest and checksum digests.
13. Return `VerifiedMacUpdate` and discard any untrusted intermediate state.

The service does not open the file. The controller performs the native handoff only with `VerifiedMacUpdate`.

## Cancellation and cleanup

- User cancellation cancels the owned task and removes the partial file and owned directory.
- Network, size, checksum, digest, or storage failure removes all files created for that attempt.
- Cleanup failure is surfaced on a manual path and logged safely; it never converts a failed artifact into a verified one.
- A previous verified DMG is cleaned before a new update attempt.
- A verified DMG is retained for the current interaction when opening fails so the user can retry or reveal it.
- Verified temporary data is removed on explicit dismissal, before the next attempt, and during orderly app termination.
- Startup performs a narrow stale-directory cleanup for updater-owned directory names only; it never recursively cleans the general temporary directory.

## Verified DMG handoff

1. Reconfirm the verified file exists as a regular file at its owned path.
2. Ask AppKit to open the DMG.
3. If opening succeeds, present guidance: drag AndroidBridge to Applications, then Control-click and choose Open on first launch because the build is not notarized.
4. Keep the current app running and unchanged.
5. If opening fails, show `Try Again`, `Reveal in Finder`, and `Dismiss` actions. Do not replace, move, mount manually, or delete the installed app.

`Reveal in Finder` is available only for a still-existing `VerifiedMacUpdate` path.

## State transition table

| Current state | Event | Next state | Required side effect |
|---|---|---|---|
| idle | automatic launch check | checking automatic | Start one asynchronous metadata task |
| idle | manual check | checking manual | Show progress and start metadata task |
| checking | newer stable release | update available | Present consent when appropriate |
| checking | equal/newer installed | idle or up to date | Automatic quiet; manual explicit |
| checking | failure | idle or failed | Automatic records; manual presents |
| update available | later | idle | No artifact download |
| update available | consent | downloading | Create owned temporary directory; fetch checksum and DMG |
| downloading | valid complete file | verified | Enable verified native handoff only |
| downloading | cancel or failure | idle or failed | Cancel task and remove attempt directory |
| verified | open succeeds | opened | Open DMG and show installation instructions |
| verified | open fails | failed with verified path | Offer retry, reveal, or dismiss |
| failed | retry check | checking manual | Start clean discovery |
| failed with verified path | retry open | verified then open | Reuse only the same verified file |
| opened | dismiss guidance | idle | Remove the retained updater-owned DMG when safe |
| any active state | app termination | terminal | Cancel work and clean owned temporary files |

## Text flow alternative

The app renders normally, then performs one stable metadata check. A newer version produces a consent prompt. Consent triggers checksum and bounded DMG retrieval into a unique temporary directory. Exact size and SHA-256 verification create a verified-update value. Only that value can reach AppKit's open operation. Every rejection or cancellation deletes updater-owned partial data and leaves the installed app untouched.

## Concurrency rules

- One controller owns one discovery task and one download task.
- Repeated automatic calls while active are ignored.
- Manual check during automatic discovery reuses that discovery and changes presentation intent to manual.
- Check actions are disabled during download or verified-file handoff.
- UI state mutation occurs on the main actor; network, hashing, and filesystem work do not block it.
- Completion from a cancelled or superseded task cannot overwrite newer presentation state.

## Verification model

Example-based Swift tests cover:

- Strict semantic parsing and numeric ordering.
- Stable Release selection and same-release asset binding.
- Exact schema, tag, version code, minimum platform, size, digest, and URL rejection.
- Equal, older, and newer Release decisions.
- No DMG request before consent.
- Valid checksum and streamed DMG acceptance.
- Malformed checksum, excess bytes, wrong size, wrong digest, cancellation, and cleanup.
- Automatic quiet behavior versus manual status/error behavior.
- Duplicate invocation serialization.
- Native opener spy proves unverified paths never reach AppKit.
