# Business Rules — U7 Clipboard

Decision rules, validation logic, and constraints for clipboard sync. IDs (BR-x) are referenced by
NFR Design and Code Generation. Codec/validation rules are inherited from U1; U7 rules govern sync
behavior on top of them.

---

## Sync mode & sending
- **BR-1**: The **default sync mode is MANUAL push** (locked decision Q5 / US-6.2). Auto-sync is
  strictly opt-in.
- **BR-2**: In `MANUAL` mode, a `clip.update` is sent **only** on an explicit user "push clipboard"
  (`userInitiated = true`). A plain local copy never auto-sends — no surprise sharing.
- **BR-3**: In `AUTO` mode, any observed local clipboard change sends a `clip.update`.
- **BR-4**: Applying an inbound `clip.update` to the local clipboard must **not** re-trigger an
  outbound send (no echo loop).

## Persistence & transport
- **BR-5**: The chosen sync mode **persists** across restarts via Settings/SecureStore (U10;
  US-6.2 / FR-9.3).
- **BR-6**: Clipboard text travels only over the **encrypted** mTLS LAN link (FR-6.3, Inherited U3).
- **BR-7**: Inbound `clip.update` is validated + safely deserialized before applying; malformed →
  drop + log security event, keep link (CC-VALID, Inherited U1/U3, fail-closed).

## Sizing & privacy
- **BR-8**: Clipboard text is bounded by the U1 control-message cap (1 MiB). Larger content is **not**
  a clipboard concern — it would route via U6 file transfer.
- **BR-9**: Clipboard **text content never appears in logs**; logs may carry only event names, mode,
  and `userInitiated` (CC-PRIV / SECURITY-03). (The `LinkLogger` forbidden-fields set already drops
  `text`/`body`.)

## Property-based testing (PBT partial)
- **BR-10 (PBT-02)**: `decode(encode(clip.update)) == msg` for arbitrary text.
- **BR-11 (PBT-03)**: `shouldSend(mode, userInitiated) == (mode == AUTO) || userInitiated`.

---

## Story / cross-cutting coverage
| Source | Covered by |
|--------|-----------|
| US-6.1 (sync text clipboard) | BR-2..BR-4, BR-6 |
| US-6.2 (control sync behavior; default settled) | BR-1, BR-2, BR-3, BR-5 |
| FR-6.3 (encrypted link) | BR-6 |
| CC-VALID / SECURITY-15 (fail-closed) | BR-7 |
| CC-PRIV / SECURITY-03 (no PII in logs) | BR-9 |
| Q5 decision (clipboard default = manual push) | BR-1 |
