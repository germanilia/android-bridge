import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

@available(macOS 13.0, *)
final class SystemAudioRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false
    private let queue = DispatchQueue(label: "com.androidbridge.systemAudio")

    func start(to url: URL) {
        Task { await startCapture(to: url) }
    }

    func stop() {
        let writer = writer
        stream?.stopCapture()
        input?.markAsFinished()
        writer?.finishWriting {}
        stream = nil
        self.writer = nil
        input = nil
        started = false
    }

    private func startCapture(to url: URL) async {
        guard CGPreflightScreenCaptureAccess() else { return }
        do {
            try? FileManager.default.removeItem(at: url)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { return }
            writer.add(input)
            self.writer = writer
            self.input = input

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            self.stream = stream
            try await stream.startCapture()
        } catch {
            // Screen/system-audio permission may be missing. Mic recording still works.
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let writer, let input else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }
}
