# Increment 2 — Bluetooth HFP Audio Feasibility Spike

**Status**: ✅ COMPLETE — hardware-validated on the target S23 Ultra + M1 Mac. **Verdict: call
audio over HFP does NOT work on this hardware (SCO link fails); ship the manual-audio fallback.**
**Date**: 2026-07-05
**Goal**: Prove the final call-audio route — can the Mac receive the phone's *cellular* call audio over Bluetooth HFP while Android Bridge keeps controlling calls over Wi-Fi/TLS?

---

## TL;DR (updated after hardware validation)

**Verdict: NOT viable on the target hardware.** The HFP **control** channel works — the Mac
connects as a Hands-Free unit and sees call state (`hf.isConnected=true`, `call active=1`) — but
the **SCO audio channel cannot be established**: when the S23 tries to open the voice link to the
Mac it fails at the controller level (`HFSCO-SCO fail reason 13`, `BTM_CreateSco Fail : 3`) and
keeps the audio on the phone. Since the entire goal was routing call *audio* to the Mac, this is
a **no-go** on the S23 Ultra + M1 Mac + current macOS.

Value of the spike: it **prevented us from building an audio bridge (Option C) that could never
carry audio**, and it **validated the existing design** — Wi-Fi/TLS for call control is correct,
and HFP control even works as a redundant path.

**Recommendation: ship the manual-audio fallback.** Wi-Fi/TLS keeps full call *control* (already
built); call *audio* stays on the phone or a Bluetooth headset paired directly to the phone, with
clear UI copy. Keep `HfpProbe` to re-test on future macOS releases.

---

## Original investigation (pre-validation)

macOS ships a native, non-deprecated API (`IOBluetoothHandsFreeDevice`) that lets an app make the
Mac act as the phone's Bluetooth **Hands-Free (HF)** unit; docs and shipping apps (Phone Amego)
say the framework routes the SCO audio link into CoreAudio automatically. That premise held for
*control* but **not for audio** on this hardware — see Hardware Validation below. The designed
split was:

- **Wi-Fi / TLS** → call metadata + control (dial / answer / decline, caller ID, contact names).
- **Bluetooth HFP** → the actual cellular call audio (this is the part that failed).

The flagged risk (recent-macOS HFP failures on Apple Silicon) turned out to be real, specifically
at the **SCO** layer. A runnable probe (`swift run HfpProbe`) was built to test it and compiles/
runs against macOS 26 / Apple Silicon.

---

## Hardware Validation (2026-07-05, S23 Ultra + M1 Mac)

Tested with the signed, Bluetooth-entitled `HfpProbe.app` and a clean symmetric pairing, with
ground truth captured on both sides (Mac probe log + phone `dumpsys bluetooth_manager` via adb).

**What worked (HFP control / SLC):**

- The Mac connected outbound as an HF client: `gateway service available = 1`, `hf.isConnected = true`.
- On a live call the Mac's link saw the call: **`call active = 1`** — the AT-command control
  channel is fully functional.

**What failed (HFP SCO audio):**

- When the phone (AG) tried to open the voice channel to the Mac, the phone logged:
  `HFSM-ACING AudioE_1 (…84:EE)` → `HFSCO-SCO fail reason 13` → `HFAGSCO-Retry SCO` →
  `HFAGSCO-BTM_CreateSco Fail : 3` → `HFAGSCO-Conn Close`. The SCO/eSCO link never establishes;
  audio stays on the phone.
- Independently, the phone's AG→Mac SDP discovery of the Mac's HF service also fails
  (`BTA_AG_DISC_FAIL_EVT`) when initiated from the phone's Bluetooth settings — macOS doesn't
  expose a discoverable HF service record for the AG to connect back to.

**Interpretation:** macOS's `IOBluetoothHandsFreeDevice` supports the HFP *control* role (RFCOMM/
AT commands) but the **SCO voice link cannot be brought up** with this phone/OS combination. This
is a macOS/controller-level limitation, consistent with the Apple-Silicon HFP reports, and is not
fixable from the app (the API gives no SCO parameter/codec control).

**Prerequisites learned along the way** (all necessary, none sufficient):

- Pairing must be **symmetric** — a one-sided bond (phone bonded, Mac forgot the phone) produces
  the same "can't connect" symptom. Verify both sides show the bond before concluding anything.
- The probe must run as a **signed, Bluetooth-entitled `.app`** (`make-hfp-probe-app.sh`), not a
  bare `swift run` CLI, for `connect()` to establish the control link at all.
- Do **not** tap "Connect" in the phone's Bluetooth settings (phone→Mac SDP fails); let the
  Mac-initiated SLC carry the call. Even then, SCO fails.

---

## The four questions this spike had to answer

### 1. Can system Bluetooth pairing alone make the Mac the phone's hands-free endpoint?

**No.** macOS does **not** natively present itself to a phone as a headset / car-kit. When you
pair a phone to a Mac in System Settings, the Mac does not offer to carry the phone's call
audio — that is precisely *why* third-party apps (Phone Amego, Dialogue, HandsFree) exist. The
HF role must be implemented by an app via `IOBluetoothHandsFreeDevice`. Pairing is a
*prerequisite*, not the mechanism.

### 2. Can call audio route to the Mac speaker/mic while Wi-Fi handles control?

**No — not on the target hardware.** Documentation and shipping apps (Phone Amego) say the
framework opens an SCO audio link and routes it into CoreAudio automatically. On the S23 Ultra +
M1 Mac + current macOS, the HFP **control** link comes up (`call active = 1`) but the **SCO audio
link fails to establish** (`BTM_CreateSco Fail`), so audio stays on the phone. See Hardware
Validation above. Native call-audio routing to the Mac is therefore **not achievable** here.

### 3. What is the minimum macOS integration needed?

Three options were considered; only one works:

| Option | Verdict | Why |
|--------|---------|-----|
| **A. No app control — system pairing only** | ❌ Not viable | macOS won't act as the phone's headset on its own (see Q1). No audio route appears. |
| **B. CoreAudio route hint only** | ❌ Not applicable | There is no SCO route to "hint" at until an HF connection exists. Nothing to point CoreAudio at. |
| **C. Small in-app HF component (`IOBluetoothHandsFreeDevice`)** | ✅ Required path | Implements the HF role; framework auto-routes SCO → CoreAudio. This is what the shipping apps do. |

**Recommendation: Option C, built into the existing Mac `BridgeCore`** — not a separate helper
process. It's a documented Apple framework, not a private hack, so it belongs in-app alongside
the rest of the call-control code. Keep it behind a feature flag until hardware-validated.

### 4. Supported manual flow if native automation proves unreliable

If the HF connect path is broken on the user's specific macOS build (the Sequoia risk), there
is still a usable, if less seamless, flow:

- Pair the phone to the Mac over Bluetooth. Android Bridge continues to **control** calls over
  Wi-Fi (dial / answer / decline) and shows caller ID.
- For audio, the user routes the call to any working Bluetooth audio endpoint (e.g. the Mac if
  the HF route works, or paired earbuds). Android Bridge's copy makes this explicit:
  *"Call audio is routed by the phone's Bluetooth settings; Android Bridge controls the call."*
- This degrades gracefully: control always works over Wi-Fi; audio quality depends on the
  Bluetooth stack, which is outside our control either way.

---

## Why HFP for audio at all (recap of the hard constraint)

Third-party Android apps **cannot** capture or relay live cellular call audio over Wi-Fi
without root — there is no public Android API for the in-call voice stream. Bluetooth HFP is the
*only* sanctioned path to move that audio off the phone. So the audio must go over Bluetooth
regardless; the design question was only whether the Mac can be the receiving end. It can.

## Key technical facts (from the spike research)

- `IOBluetoothHandsFreeDevice` + `IOBluetoothHandsFreeDeviceDelegate` are present in the current
  SDK and **not** formally deprecated (no direct Core Bluetooth replacement exists for classic
  HFP; Core Bluetooth is BLE-only).
- HFP itself carries call control (answer / hangup / dial / DTMF via AT commands) **and** call
  state (`isCallActive`, `callSetupMode`, signal strength). This overlaps our Wi-Fi control
  channel — a future simplification could let HFP handle answer/hangup while Wi-Fi adds the
  richer metadata (contact names, history) HFP can't express.
- Detecting the phone: it must advertise the **HFP Audio Gateway** SDP service to the Mac. The
  probe filters paired devices on this service class, which correctly excludes headsets
  (they're HF units, not gateways) and — notably — a paired **iPhone**, which uses Continuity
  rather than exposing classic HFP-AG to the Mac. The **target Samsung** must expose HFP-AG.

## The probe (`mac/Sources/HfpProbe/main.swift`)

A dependency-free executable target that de-risks the Sequoia concern on real hardware:

1. Enumerates paired Bluetooth devices and flags any advertising HFP Audio Gateway.
2. Picks the phone and creates an `IOBluetoothHandsFreeDevice`.
3. Calls `connect()` and narrates every delegate callback: service-available (HF link up),
   `scoConnectionOpened` (🔊 audio route live), call-active, disconnects.

**Status**: compiles and runs against macOS 26 / Apple Silicon; paired-device enumeration and
gateway detection verified locally (no phone exposing HFP-AG was present, so it stops at
detection — the expected path).

**How to run the hardware test**:

```bash
# 1. Pair the target Samsung to the Mac: System Settings ▸ Bluetooth.
# 2. On the phone, allow "Phone audio" / HFP for this Mac when prompted.
cd mac && swift run HfpProbe
# 3. Place or receive a call on the phone and watch for:
#      "✅ gateway service available = 1"   → HF link established
#      "🔊 SCO audio link OPENED"           → call audio is on the Mac speaker/mic
```

**Interpreting results**:

- Reaches `🔊 SCO audio link OPENED` and you hear call audio on the Mac → **green light**;
  proceed to build Option C into `BridgeCore` behind a feature flag.
- Lists the phone but `connect()` never completes / no service-available callback → the Sequoia
  HFP regression is present on this build; fall back to the manual flow (Q4) and revisit per OS
  updates.
- Phone never appears as an HFP Audio Gateway → check the phone's Bluetooth call-audio
  permission for this Mac; the SDP record may need a re-pair.

---

## Recommendation & next step

1. **Run `swift run HfpProbe` on the target M1 Mac with the Samsung paired** — this is the single
   decision-making data point and needs real hardware.
2. If green: implement **Option C** — an `HfpAudioBridge` in `mac/Sources/BridgeCore` wrapping
   `IOBluetoothHandsFreeDevice`, wired to the existing call UI, behind a feature flag. HFP
   surfaces call state that can reconcile with the Wi-Fi control channel.
3. If red: ship the **manual flow** copy now and keep the probe for re-testing on OS updates.

This spike does **not** change the committed call-control code; it adds only the probe target and
this document.
