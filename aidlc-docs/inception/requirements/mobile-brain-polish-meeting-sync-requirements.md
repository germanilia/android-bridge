# Mobile Brain Polish and Meeting Content Sync Requirements

## Intent
Polish the Android Second Brain from the supplied Pixel screenshot and make Mac meeting text available on the phone without moving or copying meeting audio.

## Second Brain UX
- Render Second Brain inside the normal Android Bridge shell with the global header and tab bar always visible; it must behave like the other tabs rather than replacing the entire app screen.
- Use a clear, left-aligned in-tab hierarchy instead of a title squeezed between Back and Refresh.
- Reduce visual density problems: compact controls, restrained primary action, consistent spacing, readable indentation, and grouped list surfaces.
- Display human-readable note titles instead of raw Markdown filename slugs.
- Give folders, notes, expansion state, counts, refresh progress, empty state, and selected state clear affordances.
- Preserve dirty-edit confirmation, search, note creation, editing, links, and single-flight refresh.
- Inside Brain, Back moves editor to preview and preview to library; Back from the library selects the Bridge tab instead of exiting the app.

## Meeting Content Sync
- Mac meeting title, date, company, summary, transcript, questions, processing state, and audio-file count sync through the existing Second Brain Syncthing folder.
- Meeting audio bytes, audio filenames, and absolute Mac paths must never be written into the synced projection.
- Audio files remain in the configured/default Mac meeting workspace.
- Generated meeting notes live only under an Android Bridge-owned Second Brain directory and are updated atomically.
- Existing meetings are backfilled; stale generated notes are removed when their Mac meeting no longer exists.
- Android has one `Meetings` tab, not a `Notes` tab.
- In-person capture controls and all past Mac/phone meeting content appear together in that one Meetings experience.
- The unified meeting list opens content in the existing Markdown reader.
- Generated meeting notes state that recordings remain on the Mac.

## Delivery
- Bump `VERSION` from `0.1.1` to `0.1.2`.
- Preserve the phone's existing debug signing identity and app data during `adb install -r`.
- Publish the public APK with the dedicated release signer.

## Non-Goals
- No protocol message or hosted-service change.
- No audio, photo, or other media synchronization.
- No change to the Mac meeting storage root.

## Acceptance Criteria
- Screenshot comparison shows a cleaner header, controls, typography, surfaces, and tree hierarchy.
- Meeting projection tests prove text is mirrored while audio names/data/paths are absent.
- Existing Mac meetings appear alongside in-person/phone meetings in the Android Meetings tab after Syncthing refresh.
- Android and Swift tests/builds pass, version `0.1.2` installs on the Pixel 9a, and stable `v0.1.2` publishes successfully.
