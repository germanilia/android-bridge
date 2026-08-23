# DDP2 frontend components

## UI boundary

DDP2 extends the existing native AppKit-hosted SwiftUI dashboard. It does not create a new app shell, web view, background daemon, menu-bar replacement, or external updater UI.

- BridgeCore owns release parsing, comparison, download, integrity, and cleanup.
- `MacUpdateController` owns main-actor presentation state and operation tasks.
- SwiftUI renders consent, progress, Settings status, and guidance.
- AppKit owns DMG open and Finder reveal actions.

## Component hierarchy

```text
AppDelegate
└── DashboardView
    ├── Existing Bridge, Meetings, and Second Brain tabs
    ├── SettingsTab
    │   └── SoftwareUpdateSection
    ├── UpdateAvailableDialog
    ├── UpdateProgressDialog
    ├── UpdateGuidanceDialog
    └── UpdateErrorDialog
```

### Text alternative

`AppDelegate` constructs one update controller and passes it to the existing dashboard. The Settings tab displays current update status and a manual-check button. Dashboard-level dialogs present consent, progress, verified-open guidance, and errors so an automatic check works regardless of the selected tab.

## AppDelegate integration

### Responsibilities

- Construct production release client, downloader, update service, and one `MacUpdateController`.
- Pass the controller into `DashboardView`.
- Render the existing dashboard and start existing link services before checking for updates.
- Invoke `checkAfterLaunch()` once after the dashboard is available.
- Forward orderly application termination to controller cancellation and cleanup.

### Prohibited behavior

- Waiting synchronously for GitHub.
- Opening a URL before verification.
- Replacing or quitting the installed app.
- Recreating controllers on every window open.

## MacUpdateController

### Published state

| Property | Purpose |
|---|---|
| `state` | One `MacUpdatePresentationState` value |
| `availableUpdate` | Valid update shown by consent and Settings UI |
| `verifiedUpdate` | Verified DMG retained for open retry/reveal |
| `lastAutomaticFailure` | Safe status shown in Settings without startup alert |
| `isConsentPresented` | Derived from update-available state and prompt policy |
| `isProgressPresented` | Derived from active confirmed download |

### Actions

- `checkAfterLaunch()` schedules one quiet automatic check.
- `checkManually()` exposes progress and every result.
- `downloadUpdate()` is the only consent action that invokes artifact retrieval.
- `dismissAvailableUpdate()` returns to idle without downloading.
- `cancelDownload()` cancels and cleans the active attempt.
- `openVerifiedDMG()` passes only a verified entity to AppKit.
- `retryOpen()` reuses the still-existing verified entity.
- `revealVerifiedDMG()` selects the verified file in Finder.
- `dismissResult()` clears presentation and performs applicable cleanup.
- `applicationWillTerminate()` cancels and cleans owned work.

The controller is `@MainActor`. It maps typed domain errors to finite presentation values; it does not parse arbitrary server error strings for UI.

## SoftwareUpdateSection

Location: existing `SettingsTab`, before LLM routing.

### Content

- Section title: `Software Update`.
- Installed version from the application bundle.
- Status text for idle, checking, update available, downloading, current, or last failure.
- `Check for Updates` button.
- Available version and `Download Update` button when discovery already found one.
- Release-page link when a validated update exists.

### Interaction rules

- Manual button is enabled in idle, current, update-available, and retryable failure states.
- It is disabled while checking, downloading, or opening.
- Download button appears only for validated `MacUpdate`.
- Status is selectable only where useful; raw network responses and local paths are not shown.
- Native button labels and progress text remain understandable without color or icons.

## UpdateAvailableDialog

### Purpose

Request consent before checksum or DMG download.

### Content

- Title: `Android Bridge VERSION is available`.
- Installed and available versions.
- Statement that the app will download and verify a DMG, then open it for manual drag-to-Applications installation.
- `Download Update` primary action.
- `Later` cancel action.
- Optional validated GitHub Release page link.

### Rules

- No countdown or preselected automatic action.
- Closing and `Later` have identical no-download behavior.
- One automatic dialog per launch.
- Manual check may present the dialog again after dismissal.

## UpdateProgressDialog

### Purpose

Show confirmed checksum and DMG retrieval and verification.

### Content

- Phase text: preparing, downloading, verifying, or cleaning up.
- Determinate progress once expected-size body transfer begins.
- `Cancel` while the network task can be cancelled.

### Rules

- The main app remains usable.
- Progress never exceeds 100 percent.
- Verification does not claim success until size and both digest sources agree.
- Cancellation closes progress only after cleanup is initiated.

## UpdateGuidanceDialog

### Purpose

Explain the native manual installation after a verified DMG opens.

### Content

- Verified version.
- `Drag AndroidBridge to Applications.`
- `On first launch, Control-click AndroidBridge and choose Open.`
- Clear statement that this direct build is not Apple-notarized.
- `Done` action.

It never instructs the user to disable Gatekeeper globally.

## UpdateErrorDialog

### Typed presentations

| Presentation | Message intent | Actions |
|---|---|---|
| Connection | Stable release could not be reached | Retry, Dismiss |
| Invalid update | Published metadata could not be trusted | Retry Later, Dismiss |
| Unsupported platform | Update does not support this Mac | Dismiss |
| Integrity | Download did not match published size/checksum | Retry Download, Dismiss |
| Storage | Temporary file could not be created or cleaned | Retry, Dismiss |
| Open | Verified DMG could not be opened | Try Again, Reveal in Finder, Dismiss |

Actions are shown only when valid for the controller's retained state. An integrity failure never offers reveal or open.

## State-to-component mapping

| State | Settings | Dashboard-level presentation |
|---|---|---|
| idle | Installed version and Check button | None |
| checking automatic | Checking status | None |
| checking manual | Checking status | Progress indicator |
| update available | Available version and Download button | Consent dialog when prompt policy permits |
| downloading | Progress and disabled actions | Progress dialog |
| verified/opened | Version status | Installation guidance |
| up to date | `You’re up to date` | Manual result only |
| failed | Safe failure summary | Manual/confirmed-operation error dialog |
| idle plus automatic failure | Last-check status | None |

## Accessibility and native behavior

- Use native `Button`, `Link`, `ProgressView`, alert, and sheet semantics.
- Every icon has a text label; status is never color-only.
- Default keyboard focus goes to the safe primary action; `Later` and `Cancel` remain reachable.
- VoiceOver reads installed version, available version, current phase, and progress.
- Dialogs do not steal focus for equal-version or automatic network-failure outcomes.
- Long paths and internal digests are omitted from normal UI.

## Error and cancellation flow

1. Controller receives a typed domain result.
2. Automatic discovery stores safe status without an unsolicited error dialog.
3. Manual discovery or confirmed download maps failure to one finite presentation.
4. Controller completes scoped cleanup before enabling retry where the failed artifact could be reused incorrectly.
5. Retry starts a new clean operation, except open retry may reuse the still-valid `VerifiedMacUpdate`.

## UI verification

- Controller tests use fake release source, downloader, opener, and temporary-store boundaries.
- Verify automatic equal-version and transient-network paths present no dialog.
- Verify manual no-update and failure paths produce visible status.
- Verify `Later` performs no checksum or DMG request.
- Verify one consent produces one download.
- Verify cancellation clears active progress and partial data.
- Verify opener spy receives only a `VerifiedMacUpdate`.
- Verify integrity failure never exposes open or reveal actions.
- Compile the native SwiftUI integration on the macOS 13 package target.

## React-specific rule applicability

The synchronized React component, page-layout, and frontend typing rules are not applicable. DDP2 modifies native SwiftUI/AppKit only and preserves existing project conventions.
