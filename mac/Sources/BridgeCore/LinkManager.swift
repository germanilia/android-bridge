import Foundation
import Network
import AppKit
import Combine
import CoreAudio
import UserNotifications
import DeviceLinkProtocol
import Crypto
import Security

/// A peer discovered on the LAN (Bonjour), with its advertised fingerprint.
public struct NearbyPeer: Identifiable, Equatable {
    public let id: String            // fingerprint
    public let name: String
    public let endpoint: NWEndpoint
    public let fingerprint: String
}

public struct ReceivedFile: Identifiable, Equatable {
    public let id = UUID()
    public let name: String
    public let url: URL
    public let receivedAt: Date
}

/// TLS server over Bonjour. Android connects as a pinned TLS client, so clipboard/files/call metadata
/// are encrypted on the LAN. This is server-authenticated TLS; full client-certificate mTLS is future hardening.
public final class LinkManager: ObservableObject {
    @Published public private(set) var status: ConnectionState = .disconnected
    @Published public private(set) var nearby: [NearbyPeer] = []
    @Published public private(set) var pairedFingerprints: Set<String> = []
    @Published public private(set) var lastClipboard: String?
    @Published public private(set) var events: [String] = []
    @Published public private(set) var screenImage: NSImage?
    @Published public private(set) var screenSharing = false
    private var captureActive = false
    private var captureGeneration = 0
    private var warnedScreenCapture = false
    @Published public private(set) var receivedFiles: [ReceivedFile] = []
    @Published public private(set) var meetings: [MeetingRecord] = []
    @Published public private(set) var regeneratingSummaryIds: Set<String> = []
    @Published public private(set) var brainTransferIds: Set<String> = []
    @Published public private(set) var brainNodes: [BrainNode] = []
    @Published public private(set) var brainEdges: [BrainEdge] = []
    @Published public private(set) var selectedBrainPath = "index.md"
    @Published public private(set) var selectedBrainContent = ""
    @Published public private(set) var brainSearchResults: [BrainSearchResult] = []
    @Published public private(set) var brainChat = ""
    @Published public private(set) var macMeetingActive = false
    @Published public private(set) var phoneMeetingActive = false
    /// Set when a recording finalizes so the UI can ask for a title/client and
    /// file the note into the second brain. The sheet clears it on dismiss.
    @Published public var finishedMeeting: MeetingRecord?
    private var zoomAutoMeetingActive = false
    private let brainStore = SecondBrainStore()

    /// Broadcast for inbound events so the app can show a banner (reliable without notification entitlements).
    public let notificationSubject = PassthroughSubject<(title: String, body: String, userInfo: [AnyHashable: Any]), Never>()
    /// Ringing on the phone — the app shows an interactive Answer/Decline panel.
    public let incomingCallSubject = PassthroughSubject<(number: String, name: String), Never>()
    /// Call lifecycle transition ("active"/"ended") — the app swaps to an in-call panel or dismisses.
    public let callStateSubject = PassthroughSubject<(state: String, number: String, name: String), Never>()
    /// The call currently on screen — set on ring (incoming) and on dial (outgoing); the source of
    /// truth for the in-call panel, since OFFHOOK/IDLE transitions carry no reliable number.
    private var currentCallNumber = ""
    private var currentCallName = ""

    private var lastPeer: NearbyPeer?
    private var incomingFile: (name: String, data: Data)?
    private var meetingPhotos: [String: [MeetingPhoto]] = [:]
    private var meetingStartTimes: [String: Int] = [:]
    private var activeMeetingIds: Set<String> = []
    private var macStartedMeetingId: String?
    private let meetingStore = MeetingStore.shared
    private let whisper = WhisperTranscriptionService()
    private let macRecorder = MacMeetingRecorder.shared
    private let meetingProcessingQueue = DispatchQueue(label: "com.androidbridge.meeting.processing")
    private var lastPasteboardChange = 0
    private var suppressClip: String?

    public let deviceName: String
    public let fingerprint: String
    private let identity: SelfSignedIdentity

    public static let shared = LinkManager(deviceName: Host.current().localizedName ?? "Mac")
    private var started = false

    private func refreshMeetings() {
        DispatchQueue.main.async { self.meetings = self.meetingStore.listMeetings(activeIds: self.activeMeetingIds) }
    }

    private func pushEvent(_ text: String) {
        let stamp = Date().formatted(date: .omitted, time: .standard)
        DispatchQueue.main.async { self.events = Array((["\(stamp)  \(text)"] + self.events).prefix(100)) }
    }

    private func dbg(_ s: String) {
        let line = "[\(Int(Date().timeIntervalSince1970))] LINK \(s)\n"
        let url = URL(fileURLWithPath: "/tmp/androidbridge-diag.txt")
        if let fh = try? FileHandle(forWritingTo: url) { fh.seekToEndOfFile(); fh.write(line.data(using: .utf8)!); try? fh.close() }
        else { try? line.data(using: .utf8)!.write(to: url) }
    }

    public func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String, userInfo: [String: String] = [:]) {
        notificationSubject.send((title: title, body: body, userInfo: userInfo))
    }

    private let serviceType = "_androidbridge._tcp"
    private let queue = DispatchQueue(label: "com.androidbridge.link")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var recvBuffer = [UInt8]()

    private let pairedKey = "com.androidbridge.paired"

    public init(deviceName: String) {
        self.deviceName = deviceName
        self.identity = Self.loadOrCreateIdentity(deviceName: deviceName)
        self.fingerprint = identity.fingerprint
        // Restore known (paired) devices so we auto-reconnect without re-pairing.
        self.pairedFingerprints = Set(UserDefaults.standard.stringArray(forKey: pairedKey) ?? [])
        cleanReceivedFiles()
        macRecorder.onUpdate = { [weak self] in self?.refreshMeetings() }
        macRecorder.onFinished = { [weak self] notes in self?.promptFinishedMeeting(notesURL: notes) }
        refreshMeetings()
    }

    private func rememberPaired(_ fp: String) {
        if pairedFingerprints.contains(fp) { return }
        DispatchQueue.main.async {
            self.pairedFingerprints.insert(fp)
            UserDefaults.standard.set(Array(self.pairedFingerprints), forKey: self.pairedKey)
        }
    }

    public func start() {
        if started { return }
        started = true
        requestNotificationAuthorization()
        startBrowser()
        startClipboardWatch()
        startAutoMeetingWatch()
        setStatus(.discovering)
    }

    /// Auto-sync the system clipboard: whenever the Mac clipboard changes (Cmd+C), push text (or files)
    /// to the phone. Incoming clipboard is written to the pasteboard so Cmd+V pastes it.
    private func startClipboardWatch() {
        DispatchQueue.main.async {
            self.lastPasteboardChange = NSPasteboard.general.changeCount
            Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in self?.pollPasteboard() }
        }
    }

    private func startAutoMeetingWatch() {
        DispatchQueue.main.async {
            // Screen Recording gates window-title detection and system-audio
            // (remote speaker) capture. Show the system dialog only once ever —
            // re-requesting on every launch turns into a nag; afterwards just
            // leave a hint in the activity feed.
            if !CGPreflightScreenCaptureAccess() {
                if !UserDefaults.standard.bool(forKey: "screenCapture.requested") {
                    UserDefaults.standard.set(true, forKey: "screenCapture.requested")
                    CGRequestScreenCaptureAccess()
                }
                self.pushEvent("⚠️ Screen Recording is off — remote meeting audio won't be captured (System Settings → Privacy & Security)")
            }
            Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in self?.pollVideoMeeting() }
        }
    }

    private func pollVideoMeeting() {
        guard let app = Self.activeMeetingApp() else {
            if zoomAutoMeetingActive {
                dbg("AUTO_MEETING ended")
                zoomAutoMeetingActive = false
                if macMeetingActive { stopMeetingOnMac() }
            }
            return
        }
        if !macMeetingActive {
            dbg("AUTO_MEETING detected app=\(app)")
            zoomAutoMeetingActive = true
            startMeetingOnMac()
            pushEvent("🎙️ Auto-recording \(app) meeting")
        }
    }

    private static func activeMeetingApp() -> String? {
        // Primary signal: some other process is holding a live microphone — that IS
        // an ongoing conversation, and it needs no Screen Recording permission.
        if #available(macOS 14.4, *), let app = conversationAppUsingMicrophone() { return app }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            let owner = (window[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let title = (window[kCGWindowName as String] as? String ?? "").lowercased()
            if owner.contains("zoom"), title.contains("meeting") || title.contains("webinar") || title.contains("פגישה") { return "Zoom" }
            if owner.contains("msteams") || owner.contains("microsoft teams") || owner == "teams",
               isMeetingTitle(title) { return "Teams" }
            if owner.contains("google chrome") || owner.contains("safari") || owner.contains("arc") || owner.contains("brave") || owner.contains("firefox") {
                // Google Meet tab titles use an en dash: "Meet – abc-defg-hij".
                if title.contains("meet.google.com") || title.contains("google meet") || title.contains("meet -") || title.contains("meet –") { return "Google Meet" }
            }
        }
        return nil
    }

    /// Names the conversation app currently capturing the microphone, if any.
    /// CoreAudio (macOS 14.4+) lists every audio client process with a live input,
    /// so a Teams/Zoom/browser call is detected the moment audio flows and ends
    /// when the app releases the mic — our own recorder is excluded by pid.
    @available(macOS 14.4, *)
    private static func conversationAppUsingMicrophone() -> String? {
        let apps: [(needle: String, name: String)] = [
            ("zoom", "Zoom"), ("teams", "Teams"), ("whatsapp", "WhatsApp"),
            ("facetime", "FaceTime"), ("telegram", "Telegram"), ("slack", "Slack"),
            ("discord", "Discord"),
            ("chrome", "Browser call"), ("safari", "Browser call"), ("firefox", "Browser call"),
            ("thebrowser", "Browser call"), ("brave", "Browser call"),
        ]
        for bundleId in processesWithLiveMicrophone() {
            if let match = apps.first(where: { bundleId.contains($0.needle) }) { return match.name }
        }
        return nil
    }

    /// Bundle ids (lowercased) of other processes currently recording from any input device.
    @available(macOS 14.4, *)
    private static func processesWithLiveMicrophone() -> [String] {
        func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &size, &objects) == noErr else { return [] }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var result: [String] = []
        for object in objects {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid != ownPid else { continue }
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            var bundleAddress = address(kAudioProcessPropertyBundleID)
            guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr else { continue }
            result.append((bundle as String).lowercased())
        }
        return result
    }

    private static func isMeetingTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        // Hebrew UI titles say פגישה (meeting) / שיחה (call) instead of the English words.
        return t.contains("meeting") || t.contains("call") || t.contains("פגישה") || t.contains("שיחה") || t.contains("meet.google.com") || t.contains("google meet")
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChange else { return }
        lastPasteboardChange = pb.changeCount
        guard connection != nil else { return }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], urls.contains(where: { $0.isFileURL }) {
            for u in urls where u.isFileURL { sendFile(u) }
        } else if let text = pb.string(forType: .string), !text.isEmpty, text != suppressClip {
            send(Mappers.clipboard(text))
            pushEvent("📋 Sent clipboard")
        }
    }

    public func stop() {
        connection?.cancel()
        listener?.cancel()
        browser?.cancel()
    }

    public func pair(_ peer: NearbyPeer) {
        rememberPaired(peer.fingerprint) // persists so we never re-pair
        connect(peer) // demo: the Mac always dials; the phone accepts
    }

    public func connect(_ peer: NearbyPeer) {
        if connection != nil { dbg("connect skipped (busy) → \(peer.name)"); return }
        dbg("dialing \(peer.name) endpoint=\(peer.endpoint)")
        lastPeer = peer
        rememberPaired(peer.fingerprint)
        setStatus(.connecting)
        adopt(NWConnection(to: peer.endpoint, using: tlsParameters(pinnedFingerprint: peer.fingerprint)), initiator: true)
    }

    private func scheduleReconnect() {
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.connection == nil, let p = self.lastPeer else { return }
            // The phone's port changes across app restarts — prefer the freshest
            // discovered endpoint over the cached one, or dialing hangs forever.
            let fresh = self.nearby.first { $0.fingerprint == p.fingerprint } ?? p
            self.connect(fresh)
        }
    }

    private func startHeartbeat(_ conn: NWConnection) {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.connection === conn else { return }
            self.send(Message(id: UUID().uuidString, type: MessageTypes.linkHeartbeat))
            self.startHeartbeat(conn)
        }
    }

    public func sendClipboard(_ text: String) { send(Mappers.clipboard(text)) }
    public func requestPhoneScreen() { send(Mappers.screenRequest()); pushEvent("🖥️ Requested phone screen") }
    public func tapPhone(x: Double, y: Double, w: Double, h: Double) { send(Mappers.inputTap(x: x, y: y, w: w, h: h)) }
    public func swipePhone(x1: Double, y1: Double, x2: Double, y2: Double, w: Double, h: Double) { send(Mappers.inputSwipe(x1: x1, y1: y1, x2: x2, y2: y2, w: w, h: h)) }

    // MARK: - Calls (control the phone's telephony from the Mac; audio stays on the phone)

    public func answerCall() { send(Mappers.callAction("answer")); pushEvent("📞 Answered on phone") }
    public func hangupCall() { send(Mappers.callAction("decline")); pushEvent("📞 Hung up") }
    public func dial(_ number: String) {
        let trimmed = number.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        currentCallNumber = trimmed
        currentCallName = trimmed
        send(Mappers.callAction("dial", number: trimmed))
        pushEvent("📞 Calling \(trimmed)…")
    }

    // Per-feature test senders — exercise the whole protocol end-to-end over the link.
    public func sendTestNotification() { send(Mappers.notification(pkg: "com.demo.app", title: "Test notification", text: "Hello from \(deviceName)", postedAt: 0)) }
    public func sendTestSms() { send(Mappers.smsReceived(threadId: 1, address: "+1 555 0100", body: "Test SMS from \(deviceName)", receivedAt: 0)) }
    public func sendTestCall() { send(Mappers.incomingCall(number: "+1 555 0199", contactName: "Test Caller")) }
    public func sendTestFile() {
        send(Message(id: UUID().uuidString, type: MessageTypes.fileOffer,
                     payload: ["name": .string("demo.txt"), "size": .int(1024), "transferId": .string("t1"), "streamId": .int(1)]))
    }
    public func sendTestScreen() {
        send(Message(id: UUID().uuidString, type: MessageTypes.screenStart,
                     payload: ["streamId": .int(1), "codec": .string("h264"), "maxBitrate": .int(8_000_000)]))
    }

    // MARK: - Networking

    private static func loadOrCreateIdentity(deviceName: String) -> SelfSignedIdentity {
        try! SelfSignedIdentity.generate(commonName: deviceName)
    }

    private func tlsParameters(pinnedFingerprint: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let cert = SecTrustGetCertificateAtIndex(secTrust, 0) else { complete(false); return }
            let der = SecCertificateCopyData(cert) as Data
            let fp = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined(separator: ":")
            complete(fp == pinnedFingerprint)
        }, queue)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }

    private func startBrowser() {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in self?.handleResults(results) }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        var peers: [NearbyPeer] = []
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint, name != "AndroidBridge-\(deviceName)" else { continue }
            guard case let .bonjour(txt) = r.metadata else { continue }
            let fp = txtValue(txt, "fp") ?? ""
            if fp.isEmpty || fp == fingerprint { continue }
            peers.append(NearbyPeer(id: fp, name: txtValue(txt, "name") ?? name, endpoint: r.endpoint, fingerprint: fp))
        }
        dbg("browse results: \(peers.map { "\($0.name)@\($0.endpoint)" }.joined(separator: " | "))")
        DispatchQueue.main.async {
            self.nearby = peers
            // Auto-connect to a known device — or, if none are known yet, to the first discovered peer
            // (trust-on-first-discovery) and remember it. After that we only reconnect to known devices,
            // so the user never has to pair manually.
            if self.connection == nil,
               let p = peers.first(where: { self.pairedFingerprints.contains($0.fingerprint) })
                    ?? (self.pairedFingerprints.isEmpty ? peers.first : nil) {
                self.connect(p)
            }
        }
    }

    private func adopt(_ conn: NWConnection, initiator: Bool) {
        if connection != nil { conn.cancel(); return } // first-wins: keep the existing connection
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.dbg("conn state=\(state) initiator=\(initiator)")
            switch state {
            case .ready:
                self.setStatus(.connected)
                if initiator { self.send(Message(id: UUID().uuidString, type: MessageTypes.linkHello)) }
                self.receive(on: conn)
                self.startHeartbeat(conn)
            case .failed, .cancelled:
                if self.connection === conn {
                    self.connection = nil
                    DispatchQueue.main.async { self.screenImage = nil }
                    self.setStatus(.disconnected)
                    self.scheduleReconnect()
                }
            default:
                break
            }
        }
        conn.start(queue: queue)
        // A dial to a stale endpoint can hang in .preparing indefinitely — cancel after 6s
        // so the reconnect loop retries with a freshly discovered endpoint.
        queue.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.connection === conn, self.status != .connected else { return }
            conn.cancel()
        }
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.ingest([UInt8](data)) }
            if error != nil || isComplete {
                // A graceful peer close (FIN) never fires .failed — cancel explicitly
                // or we're left with a zombie "connected" state that blocks reconnects.
                self.dbg("rx ended err=\(error.map { "\($0)" } ?? "nil") complete=\(isComplete) → cancel")
                conn.cancel()
                return
            }
            self.receive(on: conn)
        }
    }

    private func ingest(_ bytes: [UInt8]) {
        recvBuffer.append(contentsOf: bytes)
        while recvBuffer.count >= 4 {
            let len = (Int(recvBuffer[0]) << 24) | (Int(recvBuffer[1]) << 16) | (Int(recvBuffer[2]) << 8) | Int(recvBuffer[3])
            if recvBuffer.count < 4 + len { break }
            let frame = Array(recvBuffer[0..<(4 + len)])
            recvBuffer.removeFirst(4 + len)
            if let msg = try? MessageCodec.decode(frame) { route(msg) }
        }
    }

    private func route(_ message: Message) {
        func f(_ key: String) -> String {
            switch message.payload[key] {
            case .string(let v)?: return v
            case .int(let n)?: return String(n)
            default: return ""
            }
        }
        switch message.type {
        case MessageTypes.clipUpdate:
            let text = f("text")
            DispatchQueue.main.async {
                self.lastClipboard = text
                self.suppressClip = text
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                self.lastPasteboardChange = pb.changeCount // don't echo back
            }
            pushEvent("📋 Clipboard: \(text)")
            postNotification(title: "Clipboard received", body: "Click to copy it on this Mac", userInfo: ["action": "copyClipboard", "text": text])
        case MessageTypes.notifPosted:
            pushEvent("🔔 \(f("title")): \(f("text"))")
            postNotification(title: f("title"), body: f("text"))
        case MessageTypes.smsReceived:
            pushEvent("✉️ SMS \(f("address")): \(f("body"))")
            postNotification(title: "SMS from \(f("address"))", body: f("body"))
        case MessageTypes.callIncoming:
            let who = f("contactName").isEmpty ? f("number") : f("contactName")
            pushEvent("📞 Incoming call: \(who)")
            let number = f("number")
            currentCallNumber = number
            currentCallName = who
            // No toast here: the interactive call panel below IS the incoming-call UI, and it
            // replaces itself. Android fires the RINGING broadcast twice (first without the
            // number, second with it) — a toast would stack into a duplicate; the panel doesn't.
            DispatchQueue.main.async { self.incomingCallSubject.send((number: number, name: who)) }
        case MessageTypes.callState:
            // Trust our own tracked call for the number/name (OFFHOOK/IDLE carry none reliably);
            // fall back to whatever the phone sent if we have nothing.
            let state = f("state")
            if currentCallNumber.isEmpty && !f("number").isEmpty {
                currentCallNumber = f("number")
                currentCallName = f("contactName").isEmpty ? f("number") : f("contactName")
            }
            let number = currentCallNumber, name = currentCallName
            pushEvent("📞 Call \(state): \(name.isEmpty ? "unknown" : name)")
            if state == "ended" { currentCallNumber = ""; currentCallName = "" }
            DispatchQueue.main.async { self.callStateSubject.send((state: state, number: number, name: name)) }
        case MessageTypes.fileOffer:
            incomingFile = (f("name"), Data())
            pushEvent("📎 Receiving \(f("name"))…")
        case MessageTypes.fileChunk:
            if var inf = incomingFile, let d = Data(base64Encoded: f("data")) {
                inf.data.append(d)
                incomingFile = inf
                if f("last") == "true" {
                    let file = saveIncomingFile(name: inf.name, data: inf.data)
                    DispatchQueue.main.async { self.receivedFiles.insert(file, at: 0) }
                    pushEvent("📎 Received \(inf.name)")
                    postNotification(title: "File received", body: "Click to open \(inf.name)", userInfo: ["action": "openFile", "path": file.url.path])
                    incomingFile = nil
                }
            }
        case MessageTypes.screenFrame:
            if let data = Data(base64Encoded: f("data")), let img = NSImage(data: data) {
                DispatchQueue.main.async { self.screenImage = img }
            }
        case MessageTypes.meetingStart:
            let meetingId = f("meetingId")
            let startedAt = Int(f("startedAt")) ?? Int(Date().timeIntervalSince1970 * 1000)
            meetingStartTimes[meetingId] = startedAt
            activeMeetingIds.insert(meetingId)
            meetingStore.markStarted(meetingId: meetingId, startedAtMs: startedAt)
            refreshMeetings()
            pushEvent("🎙️ Meeting started")
            send(Message(id: UUID().uuidString, type: MessageTypes.meetingProcessingStatus, payload: ["meetingId": .string(meetingId), "state": .string("receiving")]))
        case MessageTypes.meetingStop:
            let meetingId = f("meetingId")
            let notes = meetingStore.finalizeMeeting(meetingId: meetingId, photos: meetingPhotos[meetingId] ?? [])
            meetingStartTimes.removeValue(forKey: meetingId)
            activeMeetingIds.remove(meetingId)
            refreshMeetings()
            pushEvent("📝 Meeting notes ready")
            send(Message(id: UUID().uuidString, type: MessageTypes.meetingNotesReady, payload: ["meetingId": .string(meetingId), "path": .string(notes.path)]))
            promptFinishedMeeting(notesURL: notes)
        case MessageTypes.meetingAudioChunkOffer:
            let meetingId = f("meetingId")
            if !meetingId.isEmpty && !activeMeetingIds.contains(meetingId) {
                let startedAt = Int(f("startedAtMs")) ?? Int(Date().timeIntervalSince1970 * 1000)
                meetingStartTimes[meetingId] = startedAt
                activeMeetingIds.insert(meetingId)
                meetingStore.markStarted(meetingId: meetingId, startedAtMs: startedAt)
                refreshMeetings()
                pushEvent("🎙️ Meeting detected from audio chunk")
            }
            handleMeetingAudioChunk(message, f)
        case MessageTypes.meetingPhotoOffer:
            handleMeetingPhoto(message, f)
        case MessageTypes.inputTap:
            performMacTap(x: Double(f("x")) ?? 0, y: Double(f("y")) ?? 0, w: Double(f("w")) ?? 1, h: Double(f("h")) ?? 1)
        case MessageTypes.inputSwipe:
            performMacSwipe(x1: Double(f("x1")) ?? 0, y1: Double(f("y1")) ?? 0, x2: Double(f("x2")) ?? 0, y2: Double(f("y2")) ?? 0, w: Double(f("w")) ?? 1, h: Double(f("h")) ?? 1)
        case MessageTypes.screenStart: pushEvent("🖥️ Screen mirror requested (stream \(f("streamId")))")
        default: break
        }
    }

    private func handleMeetingAudioChunk(_ message: Message, _ f: (String) -> String) {
        let meetingId = f("meetingId")
        let sequence = Int(f("sequence")) ?? 0
        guard let data = Data(base64Encoded: f("data")), !meetingId.isEmpty else { return }
        let file = meetingStore.saveAudio(meetingId: meetingId, sequence: sequence, data: data)
        let checksum = f("checksum")
        let base = meetingStartTimes[meetingId] ?? (Int(f("startedAtMs")) ?? 0)
        let startMs = max(0, (Int(f("startedAtMs")) ?? base) - base)
        let endMs = max(startMs, (Int(f("endedAtMs")) ?? base) - base)
        send(Message(id: UUID().uuidString, type: MessageTypes.meetingAudioChunkReceived, payload: ["meetingId": .string(meetingId), "sequence": .int(sequence), "checksum": .string(checksum)]))
        pushEvent("🎙️ Meeting chunk \(sequence) received; transcribing…")
        meetingProcessingQueue.async {
            let segment = self.whisper.transcribe(file: file, startMs: startMs, endMs: endMs)
            self.meetingStore.appendTranscript(meetingId: meetingId, segment: segment)
            _ = self.meetingStore.writeNotesIncremental(meetingId: meetingId, newSegments: [segment], photos: self.meetingPhotos[meetingId] ?? [])
            self.refreshMeetings()
            self.pushEvent("📝 Summary updated from chunk \(sequence)")
        }
    }

    private func handleMeetingPhoto(_ message: Message, _ f: (String) -> String) {
        let meetingId = f("meetingId")
        let photoId = f("photoId")
        guard let data = Data(base64Encoded: f("data")), !meetingId.isEmpty, !photoId.isEmpty else { return }
        let url = meetingStore.savePhoto(meetingId: meetingId, photoId: photoId, data: data)
        let base = meetingStartTimes[meetingId] ?? (Int(f("capturedAtMs")) ?? 0)
        let capturedAtMs = max(0, (Int(f("capturedAtMs")) ?? base) - base)
        let photo = MeetingPhoto(photoId: photoId, capturedAtMs: capturedAtMs, fileName: url.lastPathComponent)
        meetingPhotos[meetingId, default: []].append(photo)
        _ = meetingStore.writeNotes(meetingId: meetingId, photos: meetingPhotos[meetingId] ?? [])
        refreshMeetings()
        send(Message(id: UUID().uuidString, type: MessageTypes.meetingPhotoReceived, payload: ["meetingId": .string(meetingId), "photoId": .string(photoId), "checksum": .string(f("checksum"))]))
        pushEvent("📷 Meeting photo received")
    }

    private func receivedFilesDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("AndroidBridge/Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanReceivedFiles() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let dir = receivedFilesDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in files {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if date < cutoff { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func saveIncomingFile(name: String, data: Data) -> ReceivedFile {
        cleanReceivedFiles()
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let base = receivedFilesDirectory().appendingPathComponent(safeName)
        let url = uniqueURL(base)
        try? data.write(to: url)
        return ReceivedFile(name: url.lastPathComponent, url: url, receivedAt: Date())
    }

    private func uniqueURL(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) { return url }
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        for i in 2...999 {
            var candidate = dir.appendingPathComponent("\(stem) \(i)")
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return dir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
    }

    public func copyReceivedFile(_ file: ReceivedFile) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file.url as NSURL])
        pushEvent("📋 Copied \(file.name)")
    }

    public func startMeetingOnMac() {
        let id = macRecorder.start()
        meetingStore.markStarted(meetingId: id, startedAtMs: Int(Date().timeIntervalSince1970 * 1000))
        activeMeetingIds.insert(id)
        DispatchQueue.main.async { self.macMeetingActive = true }
        refreshMeetings()
        pushEvent("🎙️ Mac recording started")
    }

    public func stopMeetingOnMac() {
        macRecorder.stop()
        activeMeetingIds.removeAll()
        DispatchQueue.main.async { self.macMeetingActive = false }
        refreshMeetings()
        pushEvent("📝 Mac recording stopped — transcribing last chunk in background")
    }

    public func startMeetingOnPhone(title: String = "") {
        let meetingId = UUID().uuidString
        macStartedMeetingId = meetingId
        let startedAt = Int(Date().timeIntervalSince1970 * 1000)
        meetingStartTimes[meetingId] = startedAt
        activeMeetingIds.insert(meetingId)
        meetingStore.markStarted(meetingId: meetingId, startedAtMs: startedAt)
        DispatchQueue.main.async { self.phoneMeetingActive = true }
        refreshMeetings()
        send(Message(id: UUID().uuidString, type: MessageTypes.meetingStart, payload: ["meetingId": .string(meetingId), "title": .string(title), "startedAt": .int(meetingStartTimes[meetingId] ?? 0)]))
        pushEvent("🎙️ Started phone recording from Mac")
    }

    public func stopMeetingOnPhone() {
        guard let meetingId = macStartedMeetingId else { return }
        send(Message(id: UUID().uuidString, type: MessageTypes.meetingStop, payload: ["meetingId": .string(meetingId), "endedAt": .int(Int(Date().timeIntervalSince1970 * 1000))]))
        macStartedMeetingId = nil
        DispatchQueue.main.async { self.phoneMeetingActive = false }
        pushEvent("🎙️ Stop requested from Mac")
    }

    public func openMeetingsFolder() {
        refreshMeetings()
        NSWorkspace.shared.open(meetingStore.rootURL)
    }

    public func openMeeting(_ meeting: MeetingRecord) {
        NSWorkspace.shared.open(meeting.url)
    }

    public func openMeetingNotes(_ meeting: MeetingRecord) {
        if let notes = meeting.notesURL { NSWorkspace.shared.open(notes) }
        else { NSWorkspace.shared.open(meeting.url) }
    }

    public func deleteMeeting(_ meeting: MeetingRecord) {
        meetingStore.deleteMeeting(meeting)
        refreshMeetings()
    }

    public func renameMeeting(_ meeting: MeetingRecord, to newName: String) {
        meetingStore.renameMeeting(meeting, to: newName)
        refreshMeetings()
    }

    /// Recover a meeting whose chunks were saved but never transcribed.
    public func retranscribeMeeting(_ meeting: MeetingRecord) {
        DispatchQueue.main.async { self.regeneratingSummaryIds.insert(meeting.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            self.meetingStore.retranscribeMeeting(meeting)
            self.refreshMeetings()
            DispatchQueue.main.async { self.regeneratingSummaryIds.remove(meeting.id) }
            self.pushEvent("📝 Re-transcribed \"\(meeting.title)\"")
        }
    }

    public func regenerateMeetingSummary(_ meeting: MeetingRecord) {
        DispatchQueue.main.async { self.regeneratingSummaryIds.insert(meeting.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            self.meetingStore.regenerateSummary(meeting)
            self.refreshMeetings()
            self.pushEvent("📝 Summary regenerated")
            DispatchQueue.main.async { self.regeneratingSummaryIds.remove(meeting.id) }
        }
    }

    public func renameSpeaker(_ meeting: MeetingRecord, from oldName: String, to newName: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.meetingStore.renameSpeaker(meeting, from: oldName, to: newName)
            self.refreshMeetings()
        }
    }

    public func shareMeeting(_ meeting: MeetingRecord) {
        let item = meeting.notesURL ?? meeting.url
        DispatchQueue.main.async {
            guard let view = NSApp.keyWindow?.contentView else { return }
            NSSharingServicePicker(items: [item]).show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    public func refreshBrain(loadMap: Bool = false) {
        let path = selectedBrainPath
        DispatchQueue.global(qos: .utility).async {
            do {
                let nodes = try self.brainStore.tree()
                let edges = loadMap ? self.brainStore.edges() : self.brainEdges
                let content = try self.brainStore.show(path)
                DispatchQueue.main.async { self.brainNodes = nodes; self.brainEdges = edges; self.selectedBrainContent = content }
            } catch { self.pushEvent("🧠 Second brain refresh failed: \(error.localizedDescription)") }
        }
    }

    public func loadBrainMap() {
        DispatchQueue.global(qos: .utility).async {
            let edges = self.brainStore.edges()
            DispatchQueue.main.async { self.brainEdges = edges }
        }
    }

    public func openSecondBrainFolder() { NSWorkspace.shared.open(brainStore.rootURL) }

    public func selectBrainNode(_ path: String) {
        selectedBrainPath = path
        DispatchQueue.global(qos: .utility).async {
            do {
                let content = try self.brainStore.show(path)
                DispatchQueue.main.async { self.selectedBrainContent = content }
            } catch { self.pushEvent("🧠 Second brain read failed: \(error.localizedDescription)") }
        }
    }

    public func searchBrain(_ query: String) {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try self.brainStore.search(clean)
                DispatchQueue.main.async { self.brainSearchResults = results }
            } catch { self.pushEvent("🧠 Second brain search failed: \(error.localizedDescription)") }
        }
    }

    public func clearBrainSearch() {
        DispatchQueue.main.async { self.brainSearchResults = [] }
    }

    public func saveBrainNode(_ content: String) {
        let path = selectedBrainPath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.brainStore.save(path: path, content: content)
                self.refreshBrain()
                self.pushEvent("🧠 Saved \(path)")
            } catch { self.pushEvent("🧠 Second brain save failed: \(error.localizedDescription)") }
        }
    }

    public func addBrainNote(cluster: String, title: String, body: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.brainStore.addNote(cluster: cluster, title: title, summary: title, tags: "android-bridge", body: body)
                self.refreshBrain()
            } catch { self.pushEvent("🧠 Second brain add note failed: \(error.localizedDescription)") }
        }
    }

    public func deleteSelectedBrainNote() {
        let path = selectedBrainPath
        guard path.hasSuffix(".md"), !path.hasSuffix("index.md") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.brainStore.deleteNote(path: path)
                DispatchQueue.main.async { self.selectedBrainPath = "index.md" }
                self.refreshBrain()
            } catch { self.pushEvent("🧠 Second brain delete failed: \(error.localizedDescription)") }
        }
    }

    public func askBrain(_ question: String) {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let path = selectedBrainPath
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let answer = try self.brainStore.answer(path: path, question: clean)
                let entry = "## Q: \(clean)\n\n\(answer)\n\n"
                DispatchQueue.main.async { self.brainChat = entry + self.brainChat }
            } catch { self.pushEvent("🧠 Second brain chat failed: \(error.localizedDescription)") }
        }
    }

    public func transferToSecondBrain(_ meeting: MeetingRecord, client: String) {
        DispatchQueue.main.async { self.brainTransferIds.insert(meeting.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let path = try SecondBrainExporter().transfer(meeting: meeting, client: client)
                self.pushEvent("🧠 Transferred \"\(meeting.title)\" to second brain: \(path)")
            } catch {
                self.pushEvent("🧠 Second brain transfer failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { self.brainTransferIds.remove(meeting.id) }
        }
    }

    /// After a recording finalizes, surface the meeting so the UI can ask for a
    /// title and client before filing the note into the second brain.
    private func promptFinishedMeeting(notesURL: URL) {
        let dir = notesURL.deletingLastPathComponent().standardizedFileURL.path
        guard let record = meetingStore.listMeetings().first(where: { $0.url.standardizedFileURL.path == dir }) else { return }
        DispatchQueue.main.async { self.finishedMeeting = record }
    }

    /// Save the finished meeting into the second brain under the given client,
    /// then apply the chosen title locally. The transfer runs first because
    /// renaming moves the meeting folder the exporter reads from.
    public func completeFinishedMeeting(_ meeting: MeetingRecord, title: String, client: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled = cleanTitle.isEmpty || cleanTitle == meeting.title ? meeting : MeetingRecord(
            id: meeting.id, title: cleanTitle, url: meeting.url, notesURL: meeting.notesURL,
            date: meeting.date, audioFiles: meeting.audioFiles, imageFiles: meeting.imageFiles,
            audioCount: meeting.audioCount, photoCount: meeting.photoCount,
            transcript: meeting.transcript, summary: meeting.summary, questions: meeting.questions,
            notesUpdatedAt: meeting.notesUpdatedAt, isActive: meeting.isActive)
        DispatchQueue.main.async { self.brainTransferIds.insert(meeting.id) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let path = try SecondBrainExporter().transfer(meeting: titled, client: client)
                self.pushEvent("🧠 Transferred \"\(titled.title)\" to second brain: \(path)")
            } catch {
                self.pushEvent("🧠 Second brain transfer failed: \(error.localizedDescription)")
            }
            if titled.title != meeting.title { self.meetingStore.renameMeeting(meeting, to: titled.title) }
            self.refreshMeetings()
            DispatchQueue.main.async { self.brainTransferIds.remove(meeting.id) }
        }
    }

    public func askMeetingQuestion(_ meeting: MeetingRecord, question: String) {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.meetingStore.answerQuestion(meeting, question: clean)
            self.refreshMeetings()
        }
    }

    public func mergeMeetings(_ meetings: [MeetingRecord]) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let dir = self.meetingStore.mergeMeetings(meetings), self.meetingStore.hasReadableMeeting(at: dir) else {
                self.pushEvent("🔀 Merge failed")
                return
            }
            for meeting in meetings where !meeting.isActive { self.meetingStore.trashMeeting(meeting) }
            self.refreshMeetings()
            self.pushEvent("🔀 Merged \(meetings.count) meetings into \(dir.lastPathComponent)")
        }
    }

    public func deleteReceivedFile(_ file: ReceivedFile) {
        try? FileManager.default.removeItem(at: file.url)
        DispatchQueue.main.async { self.receivedFiles.removeAll { $0.id == file.id } }
        pushEvent("🗑️ Deleted \(file.name)")
    }

    public func handleNotificationClick(_ userInfo: [AnyHashable: Any]) {
        guard let action = userInfo["action"] as? String else { return }
        if action == "openFile", let path = userInfo["path"] as? String {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
        if action == "copyClipboard", let text = userInfo["text"] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            pushEvent("📋 Copied clipboard notification")
        }
        if action == "openScreenRecordingSettings" {
            openScreenRecordingSettings()
        }
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Send a file to the peer, chunked (offer + chunks).
    public func sendFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.lastPathComponent
        send(Message(id: UUID().uuidString, type: MessageTypes.fileOffer,
                     payload: ["name": .string(name), "size": .int(data.count)]))
        var offset = 0
        var seq = 0
        let chunk = 48 * 1024
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            let slice = data.subdata(in: offset..<end)
            let last = end == data.count
            send(Message(id: UUID().uuidString, type: MessageTypes.fileChunk,
                         payload: ["seq": .int(seq), "data": .string(slice.base64EncodedString()), "last": .string(last ? "true" : "false")]))
            offset = end; seq += 1
        }
        pushEvent("📎 Sent \(name) (\(data.count) B)")
    }

    // MARK: - Mac screen capture (two-way, U8)

    public func startScreenShare() {
        dbg("SCREEN share requested connected=\(connection != nil) preflight=\(CGPreflightScreenCaptureAccess())")
        pushEvent("🖥️ Share Mac screen requested")
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        warnedScreenCapture = false
        captureGeneration += 1
        let generation = captureGeneration
        captureActive = true
        DispatchQueue.main.async { self.screenSharing = true }
        queue.async { self.captureLoop(generation: generation) }
    }

    public func stopScreenShare() {
        captureGeneration += 1
        captureActive = false
        DispatchQueue.main.async { self.screenSharing = false }
    }

    private func captureLoop(generation: Int) {
        guard captureActive, generation == captureGeneration else { return }
        if connection != nil, let cg = CGDisplayCreateImage(CGMainDisplayID()),
           let jpeg = Self.jpeg(from: cg, maxWidth: 360, quality: 0.25) {
            let scale = 360.0 / Double(cg.width)
            if !warnedScreenCapture {
                warnedScreenCapture = true
                dbg("SCREEN sending frames jpeg=\(jpeg.count)")
                pushEvent("🖥️ Sending Mac screen frames")
            }
            send(Message(id: UUID().uuidString, type: MessageTypes.screenFrame,
                         payload: ["data": .string(jpeg.base64EncodedString()), "w": .int(360), "h": .int(Int(Double(cg.height) * scale))]))
        } else if !warnedScreenCapture {
            warnedScreenCapture = true
            captureActive = false
            DispatchQueue.main.async { self.screenSharing = false }
            postNotification(title: "Cannot capture Mac screen", body: "Click to open Screen Recording settings.", userInfo: ["action": "openScreenRecordingSettings"])
            dbg("SCREEN cannot capture connection=\(connection != nil)")
            pushEvent("🖥️ Cannot capture Mac screen")
        }
        queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.captureLoop(generation: generation) }
    }

    private func performMacTap(x: Double, y: Double, w: Double, h: Double) {
        let p = macPoint(x: x, y: y, w: w, h: h)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
        pushEvent("🖱️ Phone tapped Mac")
    }

    private func performMacSwipe(x1: Double, y1: Double, x2: Double, y2: Double, w: Double, h: Double) {
        let a = macPoint(x: x1, y: y1, w: w, h: h)
        let b = macPoint(x: x2, y: y2, w: w, h: h)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
        pushEvent("🖱️ Phone dragged Mac")
    }

    private func macPoint(x: Double, y: Double, w: Double, h: Double) -> CGPoint {
        let display = CGMainDisplayID()
        return CGPoint(x: x / max(w, 1) * Double(CGDisplayPixelsWide(display)),
                       y: y / max(h, 1) * Double(CGDisplayPixelsHigh(display)))
    }

    private static func jpeg(from cg: CGImage, maxWidth: Int, quality: CGFloat) -> Data? {
        let scale = CGFloat(maxWidth) / CGFloat(cg.width)
        let w = maxWidth
        let h = Int(CGFloat(cg.height) * scale)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    private func send(_ message: Message) {
        guard let conn = connection, let bytes = try? MessageCodec.encode(message) else { return }
        conn.send(content: Data(bytes), completion: .contentProcessed { [weak self] err in
            if err != nil { self?.dbg("send failed → cancel"); conn.cancel() }
        })
    }

    private func txtValue(_ txt: NWTXTRecord, _ key: String) -> String? {
        if case let .string(v)? = txt.getEntry(for: key) { return v }
        return nil
    }

    private func setStatus(_ s: ConnectionState) {
        DispatchQueue.main.async { self.status = s }
    }
}
