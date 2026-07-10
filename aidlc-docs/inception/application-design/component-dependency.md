# Component Dependencies — android_bridge

## Dependency Matrix (within each app)

| Component | Depends on | Communication |
|---|---|---|
| App Shell (Mac/Android) | Services, PluginRegistry | direct calls / view-models |
| DiscoveryService | DeviceDiscovery, ConnectionService | callbacks |
| PairingService | PairingManager, SecureStore | direct calls |
| ConnectionService | ConnectionManager, MessageRouter | direct calls + state stream |
| Feature Services (C1–C7) | ConnectionService, their Plugin | direct calls + streams |
| PermissionService | platform permission APIs | direct calls |
| ConnectionManager | SecureStore (certs), MessageCodec, FrameCodec | network I/O (mTLS) |
| PairingManager | SecureStore, MessageCodec | direct calls |
| MessageRouter | MessageTypeRegistry, Plugins | dispatch |
| DeviceDiscovery | OS mDNS APIs | OS callbacks |
| Plugins (C1–C7) | OS feature APIs, MessageCodec/FrameCodec | OS APIs + messages |
| SecureStore | Keychain / Keystore | OS APIs |
| LinkLogger | (used by all) | direct calls |

**Cross-device dependency**: the only link between the two apps is the **Device-Link Protocol over mutual TLS**. No app calls the other directly; everything is messages/streams. Call **audio** depends on **Bluetooth HFP** (OS-level, outside the protocol).

## Layering (acyclic)
```
App Shell / UI
      │
   Services (orchestration)
      │
 Plugins ── Core (Connection, Pairing, Discovery, Router, SecureStore, Logger)
      │                     │
  OS feature APIs      Device-Link Protocol  ── mTLS ──▶ peer device
```

## Data-Flow Diagram

```mermaid
flowchart LR
    subgraph MAC["Mac App (SwiftUI)"]
        MUI["UI / Menu-bar + Windows"]
        MSVC["Services"]
        MPLUG["Feature Plugins"]
        MCORE["Core: Conn / Pair / Router / SecureStore"]
    end

    subgraph LINK["Device-Link"]
        TLS["Mutual TLS session<br/>JSON control + binary frames"]
        BT["Bluetooth HFP<br/>call audio only"]
    end

    subgraph AND["Android App (Kotlin/Compose)"]
        ACORE["Core: Conn / Pair / Router / SecureStore"]
        APLUG["Feature Plugins"]
        ASVC["Services + Foreground Service"]
        AUI["UI / Compose"]
        AOS["OS APIs: Notif / SMS / Screen / Telephony"]
    end

    MUI --> MSVC --> MPLUG --> MCORE
    MCORE --> TLS
    TLS --> ACORE
    ACORE --> APLUG --> ASVC --> AUI
    APLUG --> AOS
    BT -. audio .- MAC
    BT -. audio .- AND

    style MAC fill:#BBDEFB,stroke:#1565C0,color:#000
    style AND fill:#C8E6C9,stroke:#2E7D32,color:#000
    style LINK fill:#FFF59D,stroke:#F57F17,color:#000
    style TLS fill:#FFA726,stroke:#E65100,color:#000
    style BT fill:#CE93D8,stroke:#6A1B9A,color:#000
```

## Communication Patterns
- **Control**: length-prefixed JSON messages over the mTLS session, dispatched by `MessageRouter`.
- **Bulk**: binary frames (file chunks, screen frames) over a stream on the same session.
- **State**: `ConnectionService` exposes a connection-state stream to the UI.
- **Audio (calls)**: Bluetooth HFP at the OS level — never traverses the protocol.
- **Trust boundary**: every inbound message is validated + safely deserialized before reaching a plugin (CC-VALID, SECURITY-05/-13); unpinned peers are rejected at the TLS layer (CC-SEC).
