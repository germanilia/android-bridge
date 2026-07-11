import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import BridgeCore

// SwiftUI views hosted in the AppKit windows created by AppDelegate (see main.swift).

/// Shared UI state so the AppKit tray/dock menus can drive the SwiftUI tab selection,
/// and so the window size the user picks per tab is remembered as the new default.
final class AppUIState: ObservableObject {
    static let shared = AppUIState()
    @Published var selectedTab = 0
    /// The dashboard window, set by AppDelegate — tab-driven resizing must not rely on
    /// NSApp.keyWindow, which is not yet updated when the tray menu switches the tab.
    weak var window: NSWindow?

    /// One shared size for every tab so switching tabs never resizes the window.
    /// Falls back to the old per-tab keys once so an existing preferred size survives.
    static func windowSize() -> CGSize {
        for key in ["windowSize", "windowSize.meetings", "windowSize.brain", "windowSize.bridge", "windowSize.settings"] {
            let w = UserDefaults.standard.double(forKey: "\(key).width")
            let h = UserDefaults.standard.double(forKey: "\(key).height")
            if w > 0 && h > 0 { return CGSize(width: w, height: h) }
        }
        return CGSize(width: 1360, height: 860)
    }

    static func saveWindowSize(_ size: CGSize) {
        UserDefaults.standard.set(Double(size.width), forKey: "windowSize.width")
        UserDefaults.standard.set(Double(size.height), forKey: "windowSize.height")
    }
}

struct DashboardView: View {
    @ObservedObject var link: LinkManager
    @State private var dropTargeted = false
    @State private var dialNumber = ""
    @State private var activityExpanded = false
    @State private var selectedMeetings = Set<String>()
    @State private var meetingQuestions = [String: String]()
    @State private var meetingSearch = ""
    @State private var speakerRename = [String: String]()
    @State private var meetingRename = [String: String]()
    @State private var meetingDateFilter = Date()
    @State private var filterByDate = false
    @State private var selectedMeetingId: String?
    @State private var showRawMarkdown = false
    @ObservedObject private var ui = AppUIState.shared
    private var connected: Bool { link.status == .connected }

    var body: some View {
        TabView(selection: $ui.selectedTab) {
        Form {
            Section {
                LabeledContent("Status") { StatusBadge(status: link.status) }
                LabeledContent("This Mac", value: link.deviceName)
            }

            Section("Nearby Devices") {
                if link.nearby.isEmpty {
                    Label("Searching the local network…", systemImage: "wifi").foregroundStyle(.secondary)
                } else {
                    ForEach(link.nearby) { peer in
                        HStack {
                            Label(peer.name, systemImage: "iphone")
                            Spacer()
                            if link.pairedFingerprints.contains(peer.fingerprint) {
                                Label("Paired", systemImage: "checkmark.seal.fill").labelStyle(.iconOnly).foregroundStyle(.green)
                            } else {
                                Button("Pair") { link.pair(peer) }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
            }

            Section("Screen") {
                if link.screenImage != nil {
                    Text("Phone screen is streaming in its own window.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Start screen share on the phone to view it in a window.").foregroundStyle(.secondary).font(.callout)
                }
                if link.screenSharing {
                    Button(role: .destructive) { link.stopScreenShare() } label: { Label("Stop sharing my screen", systemImage: "stop.circle") }
                } else {
                    Button { link.startScreenShare() } label: { Label("Share my screen to phone", systemImage: "rectangle.on.rectangle") }.disabled(!connected)
                }
                Button { link.openScreenRecordingSettings() } label: { Label("Open Screen Recording Settings", systemImage: "gear") }
            }

            Section("Clipboard & Files") {
                Text("Copy (⌘C) syncs automatically. Drop files below or use Send File.")
                    .font(.callout).foregroundStyle(.secondary)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .frame(height: 64)
                    .overlay(Label("Drop files here to send", systemImage: "arrow.down.doc").foregroundStyle(.secondary))
                    .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                        for p in providers {
                            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                var url: URL?
                                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                                else if let u = item as? URL { url = u }
                                if let url { DispatchQueue.main.async { link.sendFile(url) } }
                            }
                        }
                        return true
                    }
                HStack {
                    Button { link.sendClipboard(NSPasteboard.general.string(forType: .string) ?? "") } label: { Label("Push clipboard", systemImage: "doc.on.clipboard") }
                    Button { pickAndSendFile() } label: { Label("Send file…", systemImage: "doc.badge.plus") }
                }.disabled(!connected)

                if !link.receivedFiles.isEmpty {
                    Divider()
                    Text("Received files are kept here temporarily and auto-cleaned after 24 hours.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(link.receivedFiles) { file in
                        HStack {
                            Label(file.name, systemImage: "doc").lineLimit(1)
                            Spacer()
                            Button { link.copyReceivedFile(file) } label: { Label("Copy", systemImage: "doc.on.doc") }
                            Button(role: .destructive) { link.deleteReceivedFile(file) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }

            Section("Meetings") {
                Text("Use the Meetings tab for live transcription, summaries, recordings, questions, and merge tools.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Phone") {
                Text("Answer, decline, and place calls through your phone. Call audio stays on the phone.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("Phone number", text: $dialNumber)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { link.dial(dialNumber) }
                    Button { link.dial(dialNumber) } label: { Label("Call", systemImage: "phone.arrow.up.right") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!connected || dialNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(role: .destructive) { link.hangupCall() } label: { Label("End current call", systemImage: "phone.down") }
                    .disabled(!connected)
            }

            Section("Test") {
                HStack {
                    Button("Notification") { link.sendTestNotification() }
                    Button("SMS") { link.sendTestSms() }
                    Button("Call") { link.sendTestCall() }
                }.disabled(!connected)
            }

            Section("Activity") {
                DisclosureGroup(isExpanded: $activityExpanded) {
                    if link.events.isEmpty {
                        Text("Nothing yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(link.events.enumerated()), id: \.offset) { _, e in Text(e).font(.callout) }
                    }
                } label: {
                    Text(activityExpanded ? "Hide activity" : "Show activity")
                }
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Bridge", systemImage: "arrow.left.arrow.right") }
        .tag(0)

        MeetingCaptureTab(link: link, selectedMeetings: $selectedMeetings, meetingQuestions: $meetingQuestions, meetingSearch: $meetingSearch, speakerRename: $speakerRename, meetingRename: $meetingRename, meetingDateFilter: $meetingDateFilter, filterByDate: $filterByDate, selectedMeetingId: $selectedMeetingId, showRawMarkdown: $showRawMarkdown)
            .tabItem { Label("Meetings", systemImage: "note.text") }
            .tag(1)

        SecondBrainTab(link: link)
            .tabItem { Label("Second Brain", systemImage: "brain.head.profile") }
            .tag(2)

        SettingsTab()
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .sheet(item: $link.finishedMeeting) { meeting in
            MeetingFinishedSheet(link: link, meeting: meeting)
        }
    }

    private func toggleMeeting(_ id: String) {
        if selectedMeetings.contains(id) { selectedMeetings.remove(id) } else { selectedMeetings.insert(id) }
    }

    private func pickAndSendFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { link.sendFile(url) }
    }
}

struct MeetingCaptureTab: View {
    @ObservedObject var link: LinkManager
    @Binding var selectedMeetings: Set<String>
    @Binding var meetingQuestions: [String: String]
    @Binding var meetingSearch: String
    @Binding var speakerRename: [String: String]
    @Binding var meetingRename: [String: String]
    @Binding var meetingDateFilter: Date
    @Binding var filterByDate: Bool
    @Binding var selectedMeetingId: String?
    @Binding var showRawMarkdown: Bool

    private var filteredMeetings: [MeetingRecord] {
        let q = meetingSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return link.meetings.filter { meeting in
            let matchesText = q.isEmpty || [meeting.title, meeting.summary, meeting.transcript, meeting.questions].joined(separator: "\n").lowercased().contains(q)
            let matchesDate = !filterByDate || Calendar.current.isDate(meeting.date, inSameDayAs: meetingDateFilter)
            return matchesText && matchesDate
        }
    }

    private var selectedMeeting: MeetingRecord? {
        let id = selectedMeetingId ?? filteredMeetings.first?.id
        return link.meetings.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.title2)
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("Meetings").font(.title2).bold()
                }
                if let active = link.meetings.first(where: { $0.isActive }) {
                    HStack(spacing: 8) {
                        PulsingDot()
                        Text("Recording: \(active.title)").fontWeight(.semibold)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Color.red.opacity(0.18), Color.red.opacity(0.06)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.25)))
                }
                Text("Live chunks are transcribed as they arrive. Meetings stay local and searchable.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Search meetings, transcript, Q&A", text: $meetingSearch).textFieldStyle(.roundedBorder)
                HStack {
                    Toggle("Filter date", isOn: $filterByDate)
                    DatePicker("", selection: $meetingDateFilter, displayedComponents: .date).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if link.macMeetingActive {
                            Button { link.stopMeetingOnMac() } label: { Label("Stop Mac", systemImage: "stop.circle") }
                        } else {
                            Button { link.startMeetingOnMac() } label: { Label("Record on Mac", systemImage: "mic.circle.fill") }
                                .tint(.red)
                        }
                        Button { link.openMeetingsFolder() } label: { Label("Folder", systemImage: "folder") }
                    }
                    HStack {
                        if link.phoneMeetingActive {
                            Button { link.stopMeetingOnPhone() } label: { Label("Stop phone", systemImage: "stop.circle") }
                        } else {
                            Button { link.startMeetingOnPhone() } label: { Label("Start on phone", systemImage: "iphone") }
                                .tint(.blue)
                        }
                    }
                    .disabled(link.status != .connected)
                }
                Text("Record directly on this Mac, or start recording on the phone. Phone photos can still be added to active phone meetings.")
                    .font(.caption).foregroundStyle(.secondary)
                List(filteredMeetings, selection: $selectedMeetingId) { meeting in
                    MeetingListRow(
                        meeting: meeting,
                        selected: selectedMeetings.contains(meeting.id),
                        name: Binding(get: { meetingRename[meeting.id] ?? meeting.title }, set: { meetingRename[meeting.id] = $0 }),
                        onRename: { link.renameMeeting(meeting, to: meetingRename[meeting.id] ?? meeting.title); meetingRename[meeting.id] = nil },
                        onDelete: {
                            selectedMeetings.remove(meeting.id)
                            if selectedMeetingId == meeting.id { selectedMeetingId = nil }
                            link.deleteMeeting(meeting)
                        },
                        onToggle: {
                            if selectedMeetings.contains(meeting.id) { selectedMeetings.remove(meeting.id) } else { selectedMeetings.insert(meeting.id) }
                        }
                    )
                    .tag(meeting.id)
                }
                Button { link.mergeMeetings(link.meetings.filter { selectedMeetings.contains($0.id) }); selectedMeetings.removeAll() } label: {
                    Label("Merge selected", systemImage: "arrow.triangle.merge")
                }.disabled(selectedMeetings.count < 2)
            }
            .padding()
            .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)

            if let meeting = selectedMeeting {
                MeetingPreview(
                    link: link,
                    meeting: meeting,
                    question: Binding(get: { meetingQuestions[meeting.id] ?? "" }, set: { meetingQuestions[meeting.id] = $0 }),
                    meetingName: Binding(get: { meetingRename[meeting.id] ?? meeting.title }, set: { meetingRename[meeting.id] = $0 }),
                    speakerRename: $speakerRename,
                    showRawMarkdown: $showRawMarkdown,
                    onAsk: { link.askMeetingQuestion(meeting, question: meetingQuestions[meeting.id] ?? ""); meetingQuestions[meeting.id] = "" },
                    onRenameMeeting: { link.renameMeeting(meeting, to: meetingRename[meeting.id] ?? meeting.title); meetingRename[meeting.id] = nil },
                    onRenameSpeaker: { oldName, newName in link.renameSpeaker(meeting, from: oldName, to: newName); speakerRename["\(meeting.id)|\(oldName)"] = nil }
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.system(size: 44))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("No meeting selected").font(.title2).bold()
                    Text("Start a meeting on the phone or choose an existing meeting.").foregroundStyle(.secondary)
                }.frame(minWidth: 520, maxHeight: .infinity)
            }
        }
    }
}

struct MeetingListRow: View {
    let meeting: MeetingRecord
    let selected: Bool
    @Binding var name: String
    let onRename: () -> Void
    let onDelete: () -> Void
    let onToggle: () -> Void
    @State private var editing = false
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) { Image(systemName: selected ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                if editing {
                    TextField("Meeting name", text: $name).textFieldStyle(.roundedBorder).onSubmit { onRename(); editing = false }
                } else {
                    Text(meeting.title).font(.headline).lineLimit(1)
                }
                Text(meeting.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text("\(meeting.audioCount) recordings · \(meeting.photoCount) images").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if meeting.isActive { PulsingDot() }
                if editing {
                    Button { onRename(); editing = false } label: { Image(systemName: "checkmark.circle.fill") }.buttonStyle(.plain)
                    Button { name = meeting.title; editing = false } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                } else {
                    Button { name = meeting.title; editing = true } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                    Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(hovering ? Color.primary.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Small breathing dot used for "recording" and "connecting" states.
struct PulsingDot: View {
    var color: Color = .red
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(on ? 1.0 : 0.7)
            .opacity(on ? 1 : 0.5)
            .shadow(color: color.opacity(0.6), radius: on ? 4 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// Shown automatically when a recording finalizes: lets the user confirm the
/// meeting title and client so the note lands in the right second-brain cluster.
struct MeetingFinishedSheet: View {
    @ObservedObject var link: LinkManager
    let meeting: MeetingRecord
    @State private var title: String
    @AppStorage("secondBrainClient") private var client = ""

    init(link: LinkManager, meeting: MeetingRecord) {
        self.link = link
        self.meeting = meeting
        _title = State(initialValue: meeting.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meeting recorded").font(.title3.bold())
            Text("Set the title and client to file this note under work/sela/meetings/<client> in your second brain.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Meeting title", text: $title)
                .textFieldStyle(.roundedBorder)
            TextField("Client", text: $client)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Skip") { link.finishedMeeting = nil }
                Button("Save to Second Brain") {
                    link.completeFinishedMeeting(meeting, title: title, client: client)
                    link.finishedMeeting = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct MeetingPreview: View {
    @ObservedObject var link: LinkManager
    let meeting: MeetingRecord
    @Binding var question: String
    @Binding var meetingName: String
    @Binding var speakerRename: [String: String]
    @Binding var showRawMarkdown: Bool
    let onAsk: () -> Void
    let onRenameMeeting: () -> Void
    let onRenameSpeaker: (String, String) -> Void
    @State private var player: AVPlayer?
    @State private var now = Date()
    @AppStorage("summaryLanguage") private var summaryLanguage = "Original"
    @AppStorage("summaryType") private var summaryType = "Detailed"
    @State private var noteTab = "Summary"
    @State private var showRecordings = false
    @State private var editingTitle = false
    @State private var showBrainPrompt = false
    @State private var showAskDialog = false
    @AppStorage("secondBrainClient") private var brainClient = ""

    private var markdown: String { (try? String(contentsOf: meeting.notesURL ?? meeting.url.appendingPathComponent("notes.md"), encoding: .utf8)) ?? "" }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                noteControlBar
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                Divider()
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        HStack {
                            if editingTitle {
                                TextField("Meeting name", text: $meetingName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.largeTitle.bold())
                                    .onSubmit { onRenameMeeting(); editingTitle = false }
                                Button { onRenameMeeting(); editingTitle = false } label: { Image(systemName: "checkmark.circle.fill") }
                                Button { meetingName = meeting.title; editingTitle = false } label: { Image(systemName: "xmark.circle") }
                            } else {
                                Text(meeting.title).font(.largeTitle).bold()
                                Button { meetingName = meeting.title; editingTitle = true } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.plain)
                            }
                        }
                        Text(meeting.date.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
                        if meeting.isActive {
                            Text("Elapsed: \(elapsed(from: meeting.date, to: now))")
                                .font(.title3.monospacedDigit()).foregroundStyle(.red)
                        }

                    }
                    Spacer()
                    Menu("Copy") {
                        Button("Summary") { copy(meeting.summary) }
                        Button("Transcript") { copy(meeting.transcript) }
                        Button("Chat") { copy(meeting.questions) }
                        Button("Full note") { copy(markdown) }
                    }
                    Button { showBrainPrompt = true } label: {
                        if link.brainTransferIds.contains(meeting.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Second Brain", systemImage: "brain.head.profile")
                        }
                    }
                    .disabled(link.brainTransferIds.contains(meeting.id))
                    .alert("Transfer to Second Brain", isPresented: $showBrainPrompt) {
                        TextField("Client name", text: $brainClient)
                        Button("Transfer") { link.transferToSecondBrain(meeting, client: brainClient) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Saves this note under work/sela/meetings/<client> in your second brain.")
                    }
                    Button { link.retranscribeMeeting(meeting) } label: { Label("Re-transcribe", systemImage: "waveform") }
                        .help("Run Whisper again over the saved audio chunks and rebuild the notes")
                        .disabled(link.regeneratingSummaryIds.contains(meeting.id))
                    Button { link.shareMeeting(meeting) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { link.deleteMeeting(meeting) } label: { Label("Delete", systemImage: "trash") }
                }
                .padding(.trailing, 190)

                if !meeting.audioFiles.isEmpty {
                    SectionBox("Recordings") {
                        DisclosureGroup("Audio chunks (\(meeting.audioFiles.count))", isExpanded: $showRecordings) {
                            ForEach(meeting.audioFiles, id: \.path) { file in
                                HStack {
                                    Text(file.lastPathComponent).lineLimit(1)
                                    Spacer()
                                    Button("Play") { player = AVPlayer(url: file); player?.play() }
                                    Button("Stop") { player?.pause(); player = nil }
                                }
                            }
                        }
                    }
                }

                SectionBox("Speaker Names") {
                    ForEach(speakers, id: \.self) { speaker in
                        HStack {
                            Text(speaker).frame(width: 100, alignment: .leading)
                            TextField("New name", text: Binding(get: { speakerRename[renameKey(speaker)] ?? "" }, set: { speakerRename[renameKey(speaker)] = $0 }))
                                .textFieldStyle(.roundedBorder)
                            Button("Apply") { onRenameSpeaker(speaker, speakerRename[renameKey(speaker)] ?? "") }
                                .disabled((speakerRename[renameKey(speaker)] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    Text("Voice profiles are not stored yet; this version renames transcript labels in the note.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                SectionBox("Note") {
                    Group {
                    if noteTab == "Summary" {
                        FormattedNoteText(text: meeting.summary.isEmpty ? "Live summary will appear after the first recorded chunk is transcribed, then update while recording." : meeting.summary)
                    } else if noteTab == "Transcript" {
                        Text(meeting.transcript.isEmpty ? "Transcript is still empty." : meeting.transcript)
                            .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    } else if noteTab == "Chat" {
                        ChatQAView(text: meeting.questions)
                    } else if noteTab == "Events" {
                        EventLogView(events: link.events)
                    } else {
                        Toggle("Show raw Markdown", isOn: $showRawMarkdown)
                        if showRawMarkdown {
                            Text(markdownPreviewText(markdown)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        } else {
                            MeetingFullNotePreview(markdown: markdown, baseURL: meeting.url)
                        }
                    }
                    }
                    .transition(.opacity)
                }

                if !meeting.imageFiles.isEmpty {
                    SectionBox("Images") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(meeting.imageFiles, id: \.path) { image in
                                if let ns = NSImage(contentsOf: image) {
                                    Image(nsImage: ns).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }

            }
                    .padding()
                    .frame(minWidth: proxy.size.width, maxWidth: .infinity, alignment: .topLeading)
                }
                askNoteBox
                    .padding([.horizontal, .bottom])
            }
        }
        .frame(minWidth: 560, maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// Single pinned row above the scroll area: note-section tabs plus, on the
    /// Summary tab, the language/type pickers and the regenerate status.
    private var noteControlBar: some View {
        HStack(spacing: 12) {
            Picker("Note section", selection: Binding(
                get: { noteTab },
                set: { value in withAnimation(.easeInOut(duration: 0.2)) { noteTab = value } }
            )) {
                Text("Summary").tag("Summary")
                Text("Transcript").tag("Transcript")
                Text("Full note").tag("Full note")
                Text("Chat").tag("Chat")
                Text("Events").tag("Events")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            if noteTab == "Summary" {
                Picker("Summary language", selection: Binding(get: { summaryLanguage }, set: { summaryLanguage = $0; link.regenerateMeetingSummary(meeting) })) {
                    Text("Original").tag("Original")
                    Text("Hebrew").tag("Hebrew")
                    Text("English").tag("English")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
                Picker("Summary type", selection: Binding(get: { summaryType }, set: { summaryType = $0; link.regenerateMeetingSummary(meeting) })) {
                    Text("Detailed").tag("Detailed")
                    Text("Short").tag("Short")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                if link.regeneratingSummaryIds.contains(meeting.id) {
                    ProgressView().controlSize(.small)
                    Text("Regenerating…").font(.caption).foregroundStyle(.secondary)
                } else if let updated = meeting.notesUpdatedAt {
                    Text("Updated \(updated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var askNoteBox: some View {
        HStack(spacing: 10) {
            Button { showAskDialog = true } label: {
                Label("Ask this note", systemImage: "bubble.left.and.bubble.right.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .popover(isPresented: $showAskDialog, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask this note").font(.headline)
                    HStack(alignment: .bottom) {
                        TextField("Ask a question about this meeting", text: $question, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("Send") { onAsk() }.disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Button("Copy chat") { copy(meeting.questions) }.disabled(meeting.questions.isEmpty)
                        Button("Copy transcript") { copy(meeting.transcript) }.disabled(meeting.transcript.isEmpty)
                        Button("Copy summary") { copy(meeting.summary) }.disabled(meeting.summary.isEmpty)
                    }
                    ScrollView { ChatQAView(text: meeting.questions).frame(maxWidth: .infinity, alignment: .leading) }
                }
                .padding()
                .frame(width: 620, height: 520)
            }
            Text(meeting.questions.isEmpty ? "No chat yet" : "Chat history available")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Copy transcript") { copy(meeting.transcript) }.disabled(meeting.transcript.isEmpty)
            Button("Copy summary") { copy(meeting.summary) }.disabled(meeting.summary.isEmpty)
        }
        .padding(10)
        .background(.regularMaterial, in: Capsule())
    }

    private func markdownPreviewText(_ text: String) -> String {
        let limit = 80_000
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n\n… Full note is large; showing first \(limit) characters to keep the app responsive. Use Transcript/Summary tabs for focused reading, or open the meeting folder for the full Markdown file."
    }

    private var speakers: [String] {
        let names = meeting.transcript.split(separator: "\n").compactMap { line -> String? in
            guard let bracket = line.firstIndex(of: "[") else { return nil }
            return String(line[..<bracket]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Array(Set(names)).sorted()
    }

    private func renameKey(_ speaker: String) -> String { "\(meeting.id)|\(speaker)" }

    private func elapsed(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct SectionBox<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct EventLogView: View {
    let events: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if events.isEmpty { Text("No events yet.").foregroundStyle(.secondary) }
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                Text(event).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormattedNoteText: View {
    let text: String

    private enum Block {
        case text(AttributedString)
        case table([[String]])
    }

    var body: some View {
        let rtl = text.isMostlyHebrew
        VStack(alignment: rtl ? .trailing : .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    Text(content)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .multilineTextAlignment(rtl ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                case .table(let rows):
                    tableView(rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
    }

    /// Consecutive non-table lines are merged into one Text so selection can span
    /// multiple lines and paragraphs reflow to the available width.
    private var blocks: [Block] {
        var result: [Block] = []
        var textLines: [AttributedString] = []
        var tableRows: [[String]] = []

        func flushText() {
            while textLines.last?.characters.isEmpty == true { textLines.removeLast() }
            guard !textLines.isEmpty else { return }
            var joined = AttributedString()
            for (index, line) in textLines.enumerated() {
                if index > 0 { joined += AttributedString("\n") }
                joined += line
            }
            result.append(.text(joined))
            textLines = []
        }
        func flushTable() {
            if !tableRows.isEmpty { result.append(.table(tableRows)); tableRows = [] }
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let lowered = trimmed.lowercased()
            if lowered == "```" || lowered == "```markdown" { continue }
            if isTableSeparator(trimmed) { continue }
            if let cells = parseTableRow(trimmed) {
                flushText()
                tableRows.append(cells)
                continue
            }
            flushTable()
            if trimmed.isEmpty {
                if !textLines.isEmpty, textLines.last?.characters.isEmpty == false { textLines.append(AttributedString("")) }
            } else {
                textLines.append(attributedLine(trimmed))
            }
        }
        flushText()
        flushTable()
        return result
    }

    private func attributedLine(_ line: String) -> AttributedString {
        if let heading = parseHeading(line) {
            var content = inlineMarkdown(heading.text)
            content.font = heading.level == 1 ? .title2.bold() : (heading.level == 2 ? .title3.bold() : .headline.bold())
            return content
        }
        if let bullet = parseBullet(line) {
            return AttributedString("•  ") + inlineMarkdown(bullet)
        }
        return inlineMarkdown(line)
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func tableView(_ rows: [[String]]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, cells in
                GridRow {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        FormattedCell(text: cell)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes, String(text))
    }

    private func parseTableRow(_ line: String) -> [String]? {
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return nil }
        let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.isEmpty ? nil : cells
    }

    private func isTableSeparator(_ line: String) -> Bool {
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return false }
        let body = line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
        return !body.isEmpty && body.allSatisfy { $0 == "-" || $0.isWhitespace }
    }

    private func parseBullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") else { return nil }
        return String(line.dropFirst(2))
    }
}

struct FormattedCell: View {
    let text: String
    var body: some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        Text(attributed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: text.isMostlyHebrew ? .trailing : .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension String {
    var isMostlyHebrew: Bool {
        let letters = unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let hebrew = letters.filter { CharacterSet(charactersIn: "\u{0590}"..."\u{05FF}").contains($0) }
        return hebrew.count > letters.count / 2
    }
}

struct MeetingFullNotePreview: View {
    let markdown: String
    let baseURL: URL

    var body: some View {
        let limit = 80_000
        if markdown.count > limit {
            VStack(alignment: .leading, spacing: 10) {
                Label("Large note preview", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("This note is very large, so Android Bridge shows a truncated preview to avoid freezing the app.")
                    .foregroundStyle(.secondary)
                MarkdownPreview(markdown: String(markdown.prefix(limit)), baseURL: baseURL)
                Text("… Truncated. Use Summary/Transcript tabs or open the meeting folder for the complete Markdown file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            MarkdownPreview(markdown: markdown, baseURL: baseURL)
        }
    }
}

struct MarkdownPreview: View {
    let markdown: String
    let baseURL: URL

    private enum Chunk {
        case text(String)
        case image(URL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                switch chunk {
                case .text(let block):
                    FormattedNoteText(text: block)
                case .image(let url):
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var chunks: [Chunk] {
        var result: [Chunk] = []
        var textLines: [String] = []
        func flushText() {
            let block = textLines.joined(separator: "\n")
            if !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.text(block)) }
            textLines = []
        }
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("!["), let path = imagePath(line) {
                flushText()
                result.append(.image(baseURL.appendingPathComponent(path)))
            } else {
                textLines.append(line)
            }
        }
        flushText()
        return result
    }

    private func imagePath(_ line: String) -> String? {
        guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { return nil }
        return String(line[line.index(after: open)..<close])
    }
}

struct ChatQAView: View {
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            if entries.isEmpty {
                Text("No questions yet. Ask something about this note to build a chat history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entries, id: \.0) { entry in
                VStack(spacing: 6) {
                    HStack {
                        Spacer(minLength: 60)
                        Text(entry.1)
                            .padding(10)
                            .background(
                                LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                            .foregroundStyle(.white)
                    }
                    HStack {
                        Text(entry.2.isEmpty ? "Thinking…" : entry.2)
                            .padding(10)
                            .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                            .textSelection(.enabled)
                        Spacer(minLength: 60)
                    }
                }
            }
        }
    }
    private var entries: [(Int, String, String)] {
        text.components(separatedBy: "## Q: ").enumerated().compactMap { i, part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let pieces = trimmed.components(separatedBy: "\n\n")
            return (i, pieces.first ?? "Question", pieces.dropFirst().joined(separator: "\n\n"))
        }
    }
}

struct LLMSettingsView: View {
    let feature: LLMFeature
    @AppStorage private var usePi: Bool
    @AppStorage private var model: String
    @State private var modelSearch = ""
    @State private var ollamaModels = [String]()

    private let piModels = [
        "github-copilot/gpt-5.4",
        "github-copilot/claude-sonnet-4.5",
        "github-copilot/claude-opus-4.5",
        "openai/gpt-5.2",
        "openai/gpt-5.2-mini",
        "anthropic/claude-sonnet-4.5",
        "anthropic/claude-opus-4.5",
        "google/gemini-3-pro",
        "google/gemini-3-flash"
    ]

    init(_ feature: LLMFeature) {
        self.feature = feature
        _usePi = AppStorage(wrappedValue: false, "llm.\(feature.key).usePi")
        _model = AppStorage(wrappedValue: "gemma4:e4b", "llm.\(feature.key).model")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(feature.rawValue).frame(width: 160, alignment: .leading)
                Picker("Provider", selection: $usePi) {
                    Text("Local Ollama").tag(false)
                    Text("pi").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                if usePi {
                    Picker("pi model", selection: $model) {
                        ForEach(filteredPiModels, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 280)
                } else {
                    Picker("Ollama model", selection: $model) {
                        ForEach(filteredOllamaModels, id: \.self) { Text($0).tag($0) }
                        if filteredOllamaModels.isEmpty { Text(model.isEmpty ? "gemma4:e4b" : model).tag(model.isEmpty ? "gemma4:e4b" : model) }
                    }
                    .frame(width: 280)
                    Button { loadOllamaModels() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            if usePi {
                TextField("Search pi models", text: $modelSearch)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(width: 640)
            } else {
                TextField("Search Ollama models", text: $modelSearch)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(width: 640)
            }
        }
        .onAppear { loadOllamaModels() }
    }

    private var filteredPiModels: [String] {
        let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? piModels : piModels.filter { $0.lowercased().contains(q) }
    }

    private var filteredOllamaModels: [String] {
        let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let models = ollamaModels.isEmpty ? ["gemma4:e4b"] : ollamaModels
        return q.isEmpty ? models : models.filter { $0.lowercased().contains(q) }
    }

    private func loadOllamaModels() {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["ollama", "list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let names = output.components(separatedBy: .newlines).dropFirst().compactMap { line in
                line.split(separator: " ").first.map(String.init)
            }.filter { !$0.isEmpty }
            DispatchQueue.main.async { if !names.isEmpty { ollamaModels = names } }
        }
    }
}

struct SettingsTab: View {
    @AppStorage("pi.executable") private var piExecutable = "pi"
    @AppStorage("pi.secondBrainSkill") private var piSecondBrainSkill = NSHomeDirectory() + "/.agents/skills/second-brain"
    @AppStorage("secondBrain.root") private var secondBrainRoot = NSHomeDirectory() + "/second_brain"
    @AppStorage("meetings.root") private var meetingsRoot = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent("AndroidBridgeMeetings").path

    var body: some View {
        Form {
            Section("LLM routing") {
                ForEach(LLMFeature.allCases) { feature in LLMSettingsView(feature) }
            }
            Section("Paths") {
                pathRow("pi executable", text: $piExecutable, chooseFolder: false)
                pathRow("Second Brain skill", text: $piSecondBrainSkill, chooseFolder: true)
                pathRow("Second Brain root", text: $secondBrainRoot, chooseFolder: true)
                pathRow("Meetings folder", text: $meetingsRoot, chooseFolder: true)
                Text("Path changes are used for new pi/Second Brain/meeting operations. If a view is already open, press refresh or relaunch after changing roots.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("How pi integration works") {
                Text("Each task can use Local Ollama or pi. Local Ollama is the default and uses the model name in the row, usually gemma4:e4b.")
                Text("When pi is selected, Android Bridge invokes pi in non-interactive mode with the configured model and only the second-brain skill loaded:")
                Text("<pi executable> --print --no-session --no-skills --skill <Second Brain skill> --model <model> <prompt>")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Text("Current pi-backed paths: meeting summarize/title/chat when enabled, Second Brain search when enabled, and Second Brain Q&A when enabled. CRUD itself writes through the second-brain CLI so indexes stay consistent.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func pathRow(_ label: String, text: Binding<String>, chooseFolder: Bool) -> some View {
        HStack {
            Text(label).frame(width: 150, alignment: .leading)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
            Button("Choose…") { choosePath(text, folder: chooseFolder) }
        }
    }

    private func choosePath(_ text: Binding<String>, folder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path }
    }
}

struct SecondBrainTab: View {
    @ObservedObject var link: LinkManager
    @State private var search = ""
    @State private var draft = ""
    @State private var question = ""
    @State private var newTitle = ""
    @State private var newBody = ""
    @State private var addTargetCluster = ""
    @State private var showAddNote = false
    @State private var rawMode = false
    @State private var brainView = "Files"

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "brain.head.profile").font(.title2).foregroundStyle(.purple)
                    Text("Second Brain").font(.title2).bold()
                    Spacer()
                    Button { link.refreshBrain(loadMap: brainView == "Map") } label: { Image(systemName: "arrow.clockwise") }
                    Button { link.openSecondBrainFolder() } label: { Image(systemName: "folder") }
                }
                HStack {
                    TextField("Search second brain", text: $search).textFieldStyle(.roundedBorder).onSubmit { link.searchBrain(search) }
                    Button("Search") { link.searchBrain(search) }
                }
                Picker("View", selection: $brainView) {
                    Text("Files").tag("Files")
                    Text("Map").tag("Map")
                }
                .pickerStyle(.segmented)
                if !link.brainSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Search results").font(.headline)
                            Spacer()
                            Button { link.clearBrainSearch() } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain)
                                .keyboardShortcut(.escape, modifiers: [])
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(link.brainSearchResults) { result in
                                    Button { link.selectBrainNode(result.path) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Image(systemName: "doc.text.magnifyingglass")
                                                Text(result.title).font(.headline).lineLimit(1)
                                            }
                                            Text(result.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            Text(result.snippet)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.primary)
                                                .lineLimit(6)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(8)
                        }
                    }
                    .padding(8)
                    .frame(minHeight: 260, maxHeight: 360)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if brainView == "Files" {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(link.brainNodes) { node in
                                Button { link.selectBrainNode(node.path) } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: node.isDirectory ? "folder" : "doc.text")
                                        Text(node.label).lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.leading, CGFloat(node.depth * 16))
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 8)
                                    .background(link.selectedBrainPath == node.path ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                } else {
                    BrainMapView(nodes: link.brainNodes, edges: link.brainEdges, open: link.selectBrainNode)
                }
            }
            .padding()
            .frame(minWidth: 340, idealWidth: 430)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(link.selectedBrainPath).font(.headline).lineLimit(1)
                    Spacer()
                    Picker("View", selection: $rawMode) {
                        Text("Parsed").tag(false)
                        Text("Raw/Edit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    Button("Save") { link.saveBrainNode(draft) }.disabled(!rawMode)
                    Button("Add Note") { showAddNote = true }
                    Button("Delete Note", role: .destructive) { link.deleteSelectedBrainNote() }
                        .disabled(link.selectedBrainPath.hasSuffix("index.md"))
                }
                Group {
                    if rawMode {
                        TextEditor(text: $draft)
                            .font(.system(.body, design: .monospaced))
                            .border(Color.secondary.opacity(0.25))
                    } else {
                        ScrollView { BrainMarkdownView(markdown: draft, currentPath: link.selectedBrainPath, open: link.selectBrainNode).padding().frame(maxWidth: .infinity, alignment: .leading) }
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .onChange(of: link.selectedBrainContent) { draft = $0 }
                .onAppear { draft = link.selectedBrainContent }
                .sheet(isPresented: $showAddNote) { addNoteSheet.frame(width: 560, height: 420) }

                SectionBox("Chat with selected node") {
                    HStack(alignment: .bottom) {
                        TextField("Ask about this node", text: $question, axis: .vertical).textFieldStyle(.roundedBorder)
                        Button("Send") { link.askBrain(question); question = "" }
                            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ChatQAView(text: link.brainChat)
                }
            }
            .padding()
            .frame(minWidth: 620)
        }
        .onAppear {
            if link.brainNodes.isEmpty { link.refreshBrain(loadMap: brainView == "Map") }
        }
        .onChange(of: brainView) { view in
            if view == "Map" { link.loadBrainMap() }
        }
    }

    private var addNoteSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add note").font(.title2).bold()
            TextField("Title", text: $newTitle).textFieldStyle(.roundedBorder)
            TextField("Cluster path (blank = selected folder/index parent)", text: $addTargetCluster).textFieldStyle(.roundedBorder)
            TextEditor(text: $newBody).border(Color.secondary.opacity(0.25))
            HStack {
                Spacer()
                Button("Cancel") { showAddNote = false }
                Button("Add Note") {
                    link.addBrainNote(cluster: targetCluster, title: newTitle, body: newBody)
                    newTitle = ""; newBody = ""; showAddNote = false
                }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
    }

    private var targetCluster: String {
        let clean = addTargetCluster.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        let path = link.selectedBrainPath
        if path.hasSuffix("/index.md") { return String(path.dropLast("/index.md".count)) }
        return (path as NSString).deletingLastPathComponent
    }
}

struct BrainMapView: View {
    let nodes: [BrainNode]
    let edges: [BrainEdge]
    let open: (String) -> Void

    private struct ClusterLayout {
        let name: String
        let center: CGPoint
        let radius: CGFloat
    }

    private struct MapLayout {
        var clusters: [ClusterLayout] = []
        var points: [String: CGPoint] = [:]
        var size: CGSize = .zero
    }

    private static let nodeSpacing: CGFloat = 84
    private static let clusterGap: CGFloat = 44
    private static let margin: CGFloat = 50
    private static let maxRowWidth: CGFloat = 1500

    private var notePaths: [String] {
        nodes.filter { !$0.isDirectory && !$0.path.hasSuffix("index.md") }.map(\.path).sorted()
    }

    private var graphEdges: [BrainEdge] {
        edges.filter { notePaths.contains($0.from) && notePaths.contains($0.to) }
    }

    var body: some View {
        let layout = layout()
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for cluster in layout.clusters {
                        let rect = CGRect(x: cluster.center.x - cluster.radius, y: cluster.center.y - cluster.radius, width: cluster.radius * 2, height: cluster.radius * 2)
                        let tint = color(for: cluster.name)
                        context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.07)))
                        context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.3)), lineWidth: 1)
                    }
                    for edge in graphEdges {
                        guard let a = layout.points[edge.from], let b = layout.points[edge.to] else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)

                ForEach(layout.clusters, id: \.name) { cluster in
                    Text(cluster.name)
                        .font(.caption.bold())
                        .foregroundStyle(color(for: cluster.name))
                        .position(x: cluster.center.x, y: cluster.center.y - cluster.radius - 12)
                }

                ForEach(notePaths, id: \.self) { node in
                    let tint = color(for: clusterName(of: node))
                    let connected = graphEdges.contains { $0.from == node || $0.to == node }
                    Button { open(node) } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(tint)
                                .frame(width: connected ? 15 : 11, height: connected ? 15 : 11)
                                .shadow(color: tint.opacity(0.9), radius: 6)
                            Text(short(node))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 92)
                    }
                    .buttonStyle(.plain)
                    .position(layout.points[node] ?? .zero)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
        }
        .frame(minHeight: 420)
        .background(Color(red: 0.07, green: 0.08, blue: 0.11), in: RoundedRectangle(cornerRadius: 8))
    }

    private func layout() -> MapLayout {
        var grouped = [String: [String]]()
        for path in notePaths { grouped[clusterName(of: path), default: []].append(path) }
        let clusters = grouped.keys.sorted {
            grouped[$0]!.count == grouped[$1]!.count ? $0 < $1 : grouped[$0]!.count > grouped[$1]!.count
        }

        var result = MapLayout()
        var x = Self.margin
        var y = Self.margin
        var rowHeight: CGFloat = 0
        for cluster in clusters {
            let notes = grouped[cluster]!
            let radius = max(72, Self.nodeSpacing * sqrt(CGFloat(notes.count)) * 0.62 + 36)
            if x + radius * 2 > Self.maxRowWidth, x > Self.margin {
                x = Self.margin
                y += rowHeight + Self.clusterGap
                rowHeight = 0
            }
            let center = CGPoint(x: x + radius, y: y + radius + 16)
            result.clusters.append(ClusterLayout(name: cluster, center: center, radius: radius))
            for (index, note) in notes.enumerated() {
                let angle = CGFloat(index) * 2.399963
                let distance = (radius - 48) * sqrt(CGFloat(index) / CGFloat(max(notes.count - 1, 1)))
                result.points[note] = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            }
            x += radius * 2 + Self.clusterGap
            rowHeight = max(rowHeight, radius * 2 + 16)
        }
        let width = result.clusters.map { $0.center.x + $0.radius }.max() ?? 400
        result.size = CGSize(width: max(width + Self.margin, 500), height: max(y + rowHeight + Self.margin, 460))
        return result
    }

    private func clusterName(of path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "root" : dir
    }

    private func color(for cluster: String) -> Color {
        var hash: UInt32 = 5381
        for byte in cluster.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.6, brightness: 0.92)
    }

    private func short(_ path: String) -> String { (path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "") }
}

struct BrainMarkdownView: View {
    let markdown: String
    let currentPath: String
    let open: (String) -> Void

    private enum Block { case line(String), code(String), table([[String]]) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displayBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .line(let line): lineView(line)
                case .code(let code): codeView(code)
                case .table(let rows): tableView(rows)
                }
            }
        }
    }

    private func codeView(_ code: String) -> some View {
        Text(code.trimmingCharacters(in: .newlines))
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tableView(_ rows: [[String]]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(inlineMarkdown(cell))
                            .font(index == 0 ? .body.bold() : .body)
                            .textSelection(.enabled)
                            .padding(.vertical, 2)
                    }
                }
                if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" {
            EmptyView()
        } else if let heading = heading(trimmed) {
            Text(inlineMarkdown(heading.text)).font(heading.level == 1 ? .title2.bold() : .headline.bold())
        } else if let link = markdownLink(trimmed) {
            HStack(spacing: 4) {
                if !link.prefix.isEmpty { Text(inlineMarkdown(link.prefix)) }
                Button(link.title) { open(resolve(link.target)) }.buttonStyle(.link)
                if !link.suffix.isEmpty { Text(inlineMarkdown(link.suffix)) }
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 4)
        } else if let bullet = bullet(trimmed) {
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                Text(inlineMarkdown(bullet)).textSelection(.enabled)
            }
        } else {
            Text(inlineMarkdown(trimmed)).textSelection(.enabled)
        }
    }

    private var displayBlocks: [Block] {
        var lines = markdown.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }
        var blocks: [Block] = []
        var codeLines: [String] = []
        var tableRows: [[String]] = []
        var inCode = false
        func flushTable() {
            if !tableRows.isEmpty { blocks.append(.table(tableRows)); tableRows = [] }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushTable()
                if inCode { blocks.append(.code(codeLines.joined(separator: "\n"))); codeLines = [] }
                inCode.toggle()
            } else if inCode {
                codeLines.append(line)
            } else if let row = tableRow(trimmed) {
                tableRows.append(row)
            } else if isTableSeparator(trimmed) {
                continue
            } else {
                flushTable()
                blocks.append(.line(line))
            }
        }
        flushTable()
        if !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        return blocks
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func tableRow(_ line: String) -> [String]? {
        guard line.hasPrefix("|") && line.hasSuffix("|") && !isTableSeparator(line) else { return nil }
        return line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func isTableSeparator(_ line: String) -> Bool {
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return false }
        let body = line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
        return !body.isEmpty && body.allSatisfy { $0 == "-" || $0.isWhitespace }
    }

    private func bullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
        return String(line.dropFirst(2))
    }

    private func heading(_ line: String) -> (level: Int, text: String)? {
        let level = line.prefix { $0 == "#" }.count
        let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
        return level > 0 && !text.isEmpty ? (level, text) : nil
    }

    private func markdownLink(_ line: String) -> (prefix: String, title: String, target: String, suffix: String)? {
        guard let openBracket = line.firstIndex(of: "["),
              let closeBracket = line[openBracket...].firstIndex(of: "]"),
              line.index(after: closeBracket) < line.endIndex,
              line[line.index(after: closeBracket)] == "(",
              let closeParen = line[closeBracket...].firstIndex(of: ")")
        else { return nil }
        let targetStart = line.index(closeBracket, offsetBy: 2)
        return (
            String(line[..<openBracket]),
            String(line[line.index(after: openBracket)..<closeBracket]),
            String(line[targetStart..<closeParen]),
            String(line[line.index(after: closeParen)...])
        )
    }

    private func resolve(_ target: String) -> String {
        if target.hasPrefix("/") { return String(target.dropFirst()) }
        let base = (currentPath as NSString).deletingLastPathComponent
        return URL(fileURLWithPath: base).appendingPathComponent(target).path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct ScreenMirrorView: View {
    @ObservedObject var link: LinkManager
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let img = link.screenImage {
                    ZStack {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .allowsHitTesting(false)
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                                .onChanged { value in if dragStart == nil { dragStart = value.location } }
                                .onEnded { value in
                                    let size = fittedSize(image: img, in: geo.size)
                                    let origin = CGPoint(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2)
                                    let start = clamp(dragStart ?? value.startLocation, origin: origin, size: size)
                                    let end = clamp(value.location, origin: origin, size: size)
                                    dragStart = nil
                                    if hypot(end.x - start.x, end.y - start.y) < 6 {
                                        link.tapPhone(x: start.x, y: start.y, w: size.width, h: size.height)
                                    } else {
                                        link.swipePhone(x1: start.x, y1: start.y, x2: end.x, y2: end.y, w: size.width, h: size.height)
                                    }
                                })
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("Waiting for the phone screen…")
                        Text("Approve screen sharing on the phone. To control it from Mac, enable Android Bridge in Android Accessibility.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    private func fittedSize(image: NSImage, in bounds: CGSize) -> CGSize {
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func clamp(_ point: CGPoint, origin: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x - origin.x, 0), size.width),
            y: min(max(point.y - origin.y, 0), size.height)
        )
    }
}

struct StatusBadge: View {
    let status: ConnectionState
    var body: some View {
        let (color, label): (Color, String) = {
            switch status {
            case .connected: return (.green, "Connected")
            case .connecting, .reconnecting: return (.orange, "Connecting")
            case .discovering: return (.secondary, "Searching")
            case .disconnected: return (.secondary, "Offline")
            }
        }()
        HStack(spacing: 6) {
            if status == .connecting || status == .reconnecting {
                PulsingDot(color: .orange)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: status == .connected ? Color.green.opacity(0.6) : .clear, radius: 3)
            }
            Text(label).font(.callout).foregroundStyle(color == .secondary ? Color.secondary : color)
        }
        .animation(.easeInOut(duration: 0.25), value: status)
    }
}

/// Interactive banner shown when the phone rings — Answer/Decline act on the phone.
struct IncomingCallView: View {
    let name: String
    let number: String
    let onAnswer: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Incoming call" : name).font(.headline).lineLimit(1)
                    Text(name == number || number.isEmpty ? "Ringing on your phone" : number)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(action: onDecline) {
                    Label("Decline", systemImage: "phone.down.fill").frame(maxWidth: .infinity)
                }
                .tint(.red).buttonStyle(.borderedProminent)
                Button(action: onAnswer) {
                    Label("Answer", systemImage: "phone.fill").frame(maxWidth: .infinity)
                }
                .tint(.green).buttonStyle(.borderedProminent)
            }
            Label("Audio plays on your phone or a paired headset", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(width: 340, height: 138, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12)))
    }
}

/// In-call panel shown once a call is active: caller, live elapsed timer, and End Call.
/// Audio is on the phone (see the HFP spike) — the copy says so plainly.
struct ActiveCallView: View {
    let name: String
    let number: String
    let start: Date
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "phone.connection.fill").font(.title2).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "On call" : name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(timerInterval: start...start.addingTimeInterval(24 * 3600), countsDown: false)
                            .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        if !number.isEmpty && number != name {
                            Text("· \(number)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Button(action: onEnd) {
                Label("End Call", systemImage: "phone.down.fill").frame(maxWidth: .infinity)
            }
            .tint(.red).buttonStyle(.borderedProminent)
            Label("Audio is on your phone or a paired headset", systemImage: "info.circle")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(width: 340, height: 138, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12)))
    }
}

struct ToastView: View {
    let title: String
    let message: String
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(1)
                Text(message).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy notification content")
        }
        .padding(12)
        .frame(width: 360, height: 90, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12)))
    }
}
