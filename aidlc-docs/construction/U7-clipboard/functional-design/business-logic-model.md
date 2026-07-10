# Business Logic Model — U7 Clipboard

Technology-agnostic flows for reading, deciding, sending, and applying clipboard text. Control rides
the U1 codec over the U3 mTLS link. No transport/mTLS logic here (U3); no codec internals here (U1).
**Default mode = MANUAL push** (Q5).

---

## L1. Local copy observed  `onLocalClipboard(text, userInitiated) -> maybe send`  *(sender)*
1. Read the local clipboard text (Android `ClipboardManager` / Mac `NSPasteboard`).
2. Decide via `ClipboardSyncPolicy.shouldSend(userInitiated)`:
   - `AUTO` → always send.
   - `MANUAL` (default) → send **only** when `userInitiated == true` (an explicit "push clipboard").
3. If sending: build `clip.update` via `Mappers.clipboard(text)`; `ConnectionService.send(clip.update)`.
4. If not sending: do nothing (no surprise sharing — BR-2).

## L2. Manual push  `pushClipboard()`  *(sender, MANUAL mode)*
1. User invokes "push clipboard" from the UI (U11/U12).
2. Read current clipboard text; call L1 with `userInitiated = true` → sends regardless of mode.

## L3. Apply inbound  `onClipUpdate(clip.update)`  *(receiver)*
1. Validate inbound `clip.update` against Schema (Inherited U1/U3 fail-closed — drop if malformed).
2. Extract `text`; set the local clipboard (Android `ClipboardManager.setPrimaryClip` /
   Mac `NSPasteboard.setString`).
3. Do not echo back — applying an inbound update must not re-trigger an outbound send (BR-4, no loop).

## L4. Set sync mode  `setSyncMode(mode)`
1. Update `ClipboardSyncPolicy.mode`; persist via Settings (U10) so the choice survives restart
   (US-6.2 / FR-9.3).
2. Default at first run = `MANUAL` (Q5).

---

## Data flow (manual push, the default)
```
user copies text → user hits "push" (userInitiated=true)
  → ClipboardSyncPolicy.shouldSend(true)=true → Mappers.clipboard(text) → clip.update
  → U3 mTLS send → peer onClipUpdate → validate → set peer clipboard
```

## Testable Properties (PBT-01)
| Property | Category | Statement |
|----------|----------|-----------|
| **Clip payload round-trip** (PBT-02) | Round-trip | `decode(encode(clip.update msg)) == msg` for arbitrary text (carried via the U1 envelope round-trip). |
| **Sync-policy decision table** (PBT-03 / oracle) | Invariant / Oracle | `shouldSend(mode, userInitiated) == (mode == AUTO) \|\| userInitiated` for all `(mode, userInitiated)` combinations. |
| **Normalization idempotence** (PBT-04, advisory) | Idempotence | if clipboard text is normalized (e.g. line-ending/whitespace), `normalize(normalize(t)) == normalize(t)`. Advisory under Partial PBT. |

`ClipboardSyncPolicy.shouldSend` and `Mappers.clipboard` are pure and JVM-testable — U7's PBT surface.
The actual `ClipboardManager`/`NSPasteboard` read/set is I/O — covered by example/integration tests,
not PBT.
