# Unit of Work — Story Map — android_bridge

Maps every user story (E1–E10) to its unit. All **29 v1 stories** are assigned; the **3 [Later]**
stories are intentionally unassigned (their interfaces are kept open in the noted units).

## Story → Unit

| Story | Title | Scope | Unit |
|-------|-------|-------|------|
| US-1.1 | Pair via QR code | v1 | **U2** |
| US-1.2 | Store pairing secrets securely | v1 | **U2** |
| US-1.3 | View and unpair devices | v1 | **U2** |
| US-2.1 | Auto-discover paired device on LAN | v1 | **U3** |
| US-2.2 | Keep link alive in background (Android) | v1 | **U3** |
| US-2.3 | See connection status | v1 | **U3** |
| US-2.4 | Auto-reconnect after network drop | v1 | **U3** |
| US-3.1 | See phone notifications on the Mac | v1 | **U4** |
| US-3.2 | Choose which apps mirror | v1 | **U4** |
| US-3.3 | Act on notifications from Mac | **Later** | _(unassigned — U4 interface open)_ |
| US-4.1 | Receive incoming SMS/MMS on Mac | v1 | **U5** |
| US-4.2 | Read SMS conversation history | v1 | **U5** |
| US-4.3 | Send SMS from Mac | **Later** | _(unassigned — U5 interface open)_ |
| US-5.1 | Drag a file Mac → phone | v1 | **U6** |
| US-5.2 | Send a file phone → Mac | v1 | **U6** |
| US-5.3 | Configure received-files destination | v1 | **U6** |
| US-6.1 | Sync text clipboard | v1 | **U7** |
| US-6.2 | Control clipboard sync behavior | v1 | **U7** |
| US-7.1 | View phone screen on the Mac | v1 | **U8** |
| US-7.2 | Start/stop mirroring + capture indicator | v1 | **U8** |
| US-7.3 | Control the phone from the Mac | **Later** | _(unassigned — U8 interface open)_ |
| US-8.1 | One-time Bluetooth call setup | v1 | **U9** |
| US-8.2 | Caller-ID on Mac for incoming calls | v1 | **U9** |
| US-8.3 | Answer/decline a call from Mac | v1 | **U9** |
| US-8.4 | Place a call from Mac | v1 | **U9** |
| US-8.5 | View call history on Mac | v1 | **U9** |
| US-9.1 | Guided permission grants | v1 | **U10** |
| US-9.2 | Enable/disable each feature | v1 | **U10** |
| US-9.3 | Graceful degradation on missing permission | v1 | **U10** |
| US-10.1 | Build/run both apps from clean checkout | v1 | **U11** (Mac) + **U12** (Android) |
| US-10.2 | Documented, separable protocol + PBT | v1 | **U1** |
| US-10.3 | Runs on generic Android 13+ | v1 | **U3** |

## Unit → Stories (rollup)

| Unit | Stories | Count |
|------|---------|-------|
| **U1** Protocol/Transport | US-10.2 | 1 |
| **U2** Pairing & Security | US-1.1, US-1.2, US-1.3 | 3 |
| **U3** Discovery & Connection | US-2.1, US-2.2, US-2.3, US-2.4, US-10.3 | 5 |
| **U4** Notifications | US-3.1, US-3.2 | 2 |
| **U5** SMS | US-4.1, US-4.2 | 2 |
| **U6** File Transfer | US-5.1, US-5.2, US-5.3 | 3 |
| **U7** Clipboard | US-6.1, US-6.2 | 2 |
| **U8** Screen Mirror | US-7.1, US-7.2 | 2 |
| **U9** Calls | US-8.1, US-8.2, US-8.3, US-8.4, US-8.5 | 5 |
| **U10** Settings & Permissions | US-9.1, US-9.2, US-9.3 | 3 |
| **U11** Mac App Shell | US-10.1 (Mac) | 1 |
| **U12** Android App Shell | US-10.1 (Android) | 1 |
| **Total v1** | | **29** + US-10.1 shared across U11/U12 |

## Coverage check
- ✅ Every **v1** story is assigned to at least one unit.
- ✅ Cross-cutting acceptance criteria (CC-SEC, CC-PRIV, CC-VALID) are enforced in **U1** (validation/
  deserialization) and **U3** (mTLS/trust/fail-closed), then inherited by all feature units.
- ✅ [Later] stories (US-3.3, US-4.3, US-7.3) left unassigned; host units (U4, U5, U8) keep their
  protocol/plugin interfaces open per the application design.
