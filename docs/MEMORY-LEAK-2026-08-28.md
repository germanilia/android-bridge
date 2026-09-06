# Memory leak diagnosis — AndroidBridge (Aug 28, 2026)

> **Revision note.** An earlier draft of this document blamed
> `orderOut(nil)`-instead-of-`close()` across all seven panel dismissal sites,
> and blamed `ActiveCallView`'s ticking timer for the growth rate. Both were
> wrong, and the fix that followed from them would not have worked. Live heap
> inspection of a running instance disproved them. The corrected analysis is
> below.

## Symptom

macOS threw **"Your system has run out of application memory"** on a 64 GB machine.

PID 12432 (`/Applications/AndroidBridge.app`, uptime 1 d 14 h 49 m) held:

```
AndroidBridge [12432]: Footprint: 90 GB (16384 bytes per page)
  Dirty      Regions   Category
  90 GB       23053    MALLOC_SMALL
  phys_footprint_peak: 90 GB

DefaultMallocZone: 57,102,759 live allocations, 2% utilization
Writable regions: Total=91.0G written=90.4G(99%) swapped_out=90.3G(99%)
```

System swap at that moment: `used = 64895.06M` of `66560.00M`. After
`kill 12432` it dropped to `36120.00M`, then to `7755.94M`. No other process on
the machine exceeded 650 MB.

macOS's own `JetsamEvent` reports name AndroidBridge as the largest process in
**16 of 18** memory-kill events, peaking at **92,575 MB**.

## Status: relay replay amplification caused the 90 GB outage

Three independent macOS CPU-resource reports caught the process growing by
894 MB to 3.88 GB in 104 to 163 seconds. All three sampled the same hot path:

```
LinkManager.handleRelayFrame
RelayReplaySession.handle
RelayReplaySession.operationFrames
RelayFrameQueue.complete
```

The Android peer repeatedly sent the same 131-byte `sync.resume` request. The
Mac rebuilt the pending journal suffix for every request and appended every frame
to an unbounded `[Data]` queue. `RelayFrameQueue.complete()` also used
`Array.removeFirst()`, making queue draining progressively more expensive.
Homeserver logs contain 1,708,978 forwarded frames in one six-hour interval,
including 126,775 Android 131-byte frames and large batches of Mac responses.

The old process retained 57,102,759 allocations averaging about 1,670 bytes over
38.89 hours, or 408 allocations per second. The relay storm explains the
activity-dependent growth and matches the sampled allocation path. Malloc stack
logging was not enabled, so the evidence does not identify every retained block's
concrete Swift or Foundation type.

The `showToast` retain cycle below is a separate confirmed leak. Only 18
`TOAST_FIRED` events exist in the complete diagnostic log, so it cannot explain
90 GB.

## Confirmed (but minor) leak — retain cycle in `showToast`

`mac/Sources/BridgeApp/main.swift:234`:

```swift
panel.contentView = NSHostingView(rootView: ToastView(title: title, message: body) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(copyText, forType: .string)
}.onTapGesture {
    LinkManager.shared.handleNotificationClick(userInfo)
    panel.orderOut(nil)          // ← captures `panel` STRONGLY
})
```

The cycle:

```
panel ──retains──▶ contentView (NSHostingView)
                      └─retains──▶ SwiftUI rootView tree
                                      └─retains──▶ .onTapGesture closure
                                                      └─retains──▶ panel
```

The panel keeps itself alive. The 4-second dismissal does not break it:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
    panel.orderOut(nil)                          // hides it
    self.toastPanels.removeAll { $0 == panel }   // drops the array reference
}
```

`orderOut` only unmaps the window, and dropping the array reference is
irrelevant while the cycle holds a reference of its own. **Every toast ever
shown stays in memory for the life of the process.** With only 18 toasts on
record, this costs kilobytes — it is a correctness bug, not the outage.

### Why the call panels do *not* leak

`showCallPanel` (main.swift:265) and `showActiveCallPanel` (main.swift:295)
build their dismissal closure with a weak capture list:

```swift
let dismiss: () -> Void = { [weak self, weak panel] in
    panel?.orderOut(nil)
    if self?.callPanel === panel { self?.callPanel = nil }
}
```

No cycle, so those panels deallocate normally. `showToast` is the only one of
the three that captures `panel` strongly, and it is the only one that leaks.

### Verification on a live process

PID 72319, started 08:13:53, unfixed build. One toast fired at 09:06:33 (a
panel with a 4-second lifetime). At 10:50 — **1 h 44 m later** — `heap 72319`
still showed its entire view tree resident:

```
1  2560  NSKVONotifying__TtGC7SwiftUI13NSHostingView...BridgeApp9ToastView...TapGestureModifier__
1   512  SwiftUI.ViewGraphFeatureBuffer...NSHostingView<ModifiedContent<ToastView, TapGestureModifier>>
1   320  SwiftUI.AppKitNavigationBridge<ModifiedContent<ToastView, TapGestureModifier>>
1   320  SwiftUI.SharingServicePickerBridge<ModifiedContent<ToastView, TapGestureModifier>>
1   224  TooltipBridge<ModifiedContent<ToastView, TapGestureModifier>>.DynamicTooltipManager
1   192  SwiftUI.AppKitDialogBridge<ModifiedContent<ToastView, TapGestureModifier>>
```

In the same second, four `ACTIVE_CALL_PANEL` panels were created. Heap matches
for `ActiveCallView` and `IncomingCallView`: **0**. Exactly as the capture-list
difference predicts.

### Leaked toasts are inert, not self-feeding

`ToastView` (BridgeApp.swift:2492) contains no timer, animation, or
`TimelineView`. Measured on the live process holding one leaked toast:
CPU 0.0% (22 s total over 2 h 37 m) and footprint flat at 72 MB across a
3-minute sample window. A leaked toast costs a fixed allocation and then sits
there. Growth is therefore **per toast created**, not per unit of time.

## Implemented fixes

### Relay replay containment

Both peers now suppress repeated resume requests and repeated suffix replays at
the same cursor. Cursor progress permits the next suffix request. Regression
tests cover duplicate gaps and duplicate resume requests.

The Mac outbound relay queue now has a 64 MB pending-byte limit. It drains by
index instead of using `Array.removeFirst()`, releases each sent `Data` value,
and throws `RelayError.outboundQueueFull` before the queue can grow without
bound.

### Toast lifecycle

The toast tap handler captures `panel` weakly. Four seconds after creation, the
app clears `contentView`, closes the panel, and removes it by identity. At most
five toast panels remain active; a sixth closes the oldest first.

Live verification before the fix found two retained `ToastView` hosting graphs
and no `ActiveCallView` or `IncomingCallView` graphs. After installing the fix,
`heap` found none of those view types after the toast lifetime elapsed.

Repeated call-panel events remain visible in the diagnostic log, but current
evidence does not prove that repeated `.ready` callbacks create duplicate receive
loops. No connection-state change was made for that observation.

## Verification

The leak is only observable when toasts actually fire, so a short idle sample
proves nothing. Correlate toast count against footprint over hours:

```bash
AB=$(pgrep -x AndroidBridge)
while sleep 300; do
  printf '%s toasts=%s %s\n' "$(date +%H:%M:%S)" \
    "$(grep -c TOAST_FIRED /tmp/androidbridge-diag.txt)" \
    "$(footprint -p $AB | awk '/phys_footprint:/{print $2, $3}')"
done
```

Before the fix, footprint steps up with each toast and never returns. After it,
footprint should return to baseline within seconds of a toast expiring.

Direct object check — should print nothing a few seconds after a toast expires:

```bash
heap $(pgrep -x AndroidBridge) | grep ToastView
```

For symbolicated allocation stacks, relaunch with malloc stack logging (the
90 GB capture had none, which is why its `sample` output contained no
app-level allocation frames):

```bash
MallocStackLogging=1 /Applications/AndroidBridge.app/Contents/MacOS/AndroidBridge
malloc_history $(pgrep -x AndroidBridge) -highWaterMark
```

## Evidence files

- `androidbridge-footprint.txt` — `footprint -p 12432` at 90 GB
- `androidbridge-vmmap-summary.txt` — malloc zone table, 57 M live allocations
- `androidbridge-sample.txt` — `sample 12432 3`
- `androidbridge-diag.txt` — the app's own log across both instances
- `/Library/Logs/DiagnosticReports/JetsamEvent-*.ips` — 18 system memory-kill reports
