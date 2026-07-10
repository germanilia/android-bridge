# Domain Entities — U7 Clipboard

Technology-agnostic domain model for text clipboard sync between the paired devices. Clipboard
payloads ride U1 **control messages** over the U3 mTLS link. **Default sync mode = MANUAL push**
(locked decision Q5 / US-6.2). Implemented later in Swift (`mac/Plugins/Clipboard`) and Kotlin
(`android/.../feature` + plugin). Concepts only, not code.

---

## E1. ClipboardContent
The synced unit. v1 is text-only.

| Field | Type | Notes |
|-------|------|-------|
| `text` | string | UTF-8 clipboard text. Size-capped by the U1 control message limit (1 MiB). |

(Non-text clipboard data — images/files — is out of scope for v1; large content would route via U6
file transfer, not the clipboard.)

## E2. ClipboardSyncMode
Enum controlling when a local copy is pushed to the peer (FR-6.2). Mirrors the real
`feature/ClipboardSync.kt`:

| Value | Behavior |
|-------|----------|
| `MANUAL` | **Default (Q5).** Only an explicit user "push clipboard" sends. Privacy-first. |
| `AUTO` | Opt-in. Any local clipboard change syncs automatically. |

## E3. ClipUpdate — `clip.update`
Control message carrying clipboard text to the peer. Payload: `{ text }`. Built by `Mappers.clipboard`
(real scaffold). On receipt the peer applies it to its own clipboard.

## E4. PushTrigger
The cause of a send: `userInitiated: bool`. In `MANUAL` mode only `userInitiated = true` sends; in
`AUTO` mode any local change sends (the policy decision, E5).

## E5. ClipboardSyncPolicy (decision rule)
Pure decision: `shouldSend(userInitiated) -> bool`. `AUTO → true`; `MANUAL → userInitiated`. Mirrors
the real `ClipboardSyncPolicy` scaffold; this is U7's main pure-logic surface.

---

## Relationships
```
local copy ──PushTrigger──▶ ClipboardSyncPolicy.shouldSend ──true──▶ Mappers.clipboard ──clip.update──▶ peer ──apply──▶ peer clipboard
                                                          └──false──▶ (no send)
ClipboardSyncMode ──parameterizes──▶ ClipboardSyncPolicy
```

## Out of scope for U7 (owned elsewhere)
- Control codec, validation, fail-closed drop → **U1**.
- mTLS session + send → **U3**.
- The sync-mode toggle UI + persistence → **U10 settings** and **U11/U12** shells.
- Non-text clipboard / large blobs → **U6** file transfer (not clipboard).
