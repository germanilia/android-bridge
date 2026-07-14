import Foundation
import AVFoundation

public final class MacMeetingRecorder: NSObject, AVAudioRecorderDelegate {
    public static let shared = MacMeetingRecorder()
    private var recorder: AVAudioRecorder?
    @available(macOS 13.0, *) private var systemRecorder: SystemAudioRecorder?
    private var systemFile: URL?
    private var timer: Timer?
    private var meetingId = ""
    private var sequence = 0
    private var chunkStarted = Date()
    private let store = MeetingStore.shared
    private let whisper = WhisperTranscriptionService()
    // Serial: chunk transcriptions and the final finalizeMeeting must run in order.
    private let transcriptionQueue = DispatchQueue(label: "com.androidbridge.meeting-transcription", qos: .userInitiated)
    public var onUpdate: (() -> Void)?
    /// Called with the finalized notes URL once stop() has flushed every chunk.
    public var onFinished: ((URL) -> Void)?

    public var isRecording: Bool { recorder != nil }

    public func start() -> String? {
        if !meetingId.isEmpty { return meetingId }
        meetingId = UUID().uuidString
        sequence = 0
        _ = store.meetingDir(meetingId)
        if startChunk() { return meetingId }
        meetingId = ""
        return nil
    }

    public func stop() {
        guard !meetingId.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        let id = meetingId
        meetingId = ""
        finishChunk(of: id)
        // Finalize on the same serial queue so it runs only after every pending
        // chunk transcription: finalizeMeeting renames the meeting folder, and a
        // transcript appended afterwards under the old id would recreate a ghost
        // directory and lose the last chunk's text.
        transcriptionQueue.async {
            let notes = self.store.finalizeMeeting(meetingId: id)
            self.onUpdate?()
            self.onFinished?(notes)
        }
    }

    private func startChunk() -> Bool {
        chunkStarted = Date()
        let media = store.meetingDir(meetingId).appendingPathComponent("media", isDirectory: true)
        let file = media.appendingPathComponent(String(format: "you-chunk-%04d.m4a", sequence))
        systemFile = media.appendingPathComponent(String(format: "remote-chunk-%04d.m4a", sequence))
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64_000,
        ]
        guard let recorder = try? AVAudioRecorder(url: file, settings: settings), recorder.record() else { return false }
        self.recorder = recorder
        recorder.delegate = self
        if #available(macOS 13.0, *), let systemFile {
            let systemRecorder = SystemAudioRecorder()
            self.systemRecorder = systemRecorder
            systemRecorder.start(to: systemFile)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.rotateChunk() }
        return true
    }

    private func rotateChunk() {
        finishChunk(of: meetingId)
        sequence += 1
        if !startChunk() { stop() }
    }

    private func finishChunk(of id: String) {
        guard let recorder else { return }
        let micFile = recorder.url
        let remoteFile = systemFile
        recorder.stop()
        if #available(macOS 13.0, *) { systemRecorder?.stop(); systemRecorder = nil }
        self.recorder = nil
        self.systemFile = nil
        let startMs = Int(chunkStarted.timeIntervalSince1970 * 1000)
        let endMs = Int(Date().timeIntervalSince1970 * 1000)
        transcriptionQueue.async {
            var newSegments = [TranscriptSegment]()
            let you = self.whisper.transcribe(file: micFile, startMs: startMs, endMs: endMs, speaker: "You")
            self.store.appendTranscript(meetingId: id, segment: you)
            newSegments.append(you)
            if let remoteFile, FileManager.default.fileExists(atPath: remoteFile.path) {
                Thread.sleep(forTimeInterval: 1)
                let remote = self.whisper.transcribe(file: remoteFile, startMs: startMs, endMs: endMs, speaker: "Remote")
                self.store.appendTranscript(meetingId: id, segment: remote)
                newSegments.append(remote)
            }
            _ = self.store.writeNotesIncremental(meetingId: id, newSegments: newSegments)
            self.onUpdate?()
        }
    }
}
