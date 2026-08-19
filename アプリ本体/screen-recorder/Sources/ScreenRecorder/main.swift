import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AppKit
import CoreGraphics

// MARK: - App

@main
struct App: SwiftUI.App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(width: 320, height: 280).fixedSize()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Engine

final class Engine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: AVAssetWriter
    let videoIn: AVAssetWriterInput
    let audioIn: AVAssetWriterInput

    private let lock = NSLock()
    private var sessionStarted = false
    private var videoCount = 0
    private var audioCount = 0
    private var firstError: String?

    /// Called from the capture queue when the writer or the stream dies mid-recording.
    var onFailure: ((String) -> Void)?

    init(writer: AVAssetWriter, vi: AVAssetWriterInput, ai: AVAssetWriterInput) {
        self.writer = writer
        self.videoIn = vi
        self.audioIn = ai
        super.init()
    }

    var stats: (video: Int, audio: Int, error: String?) {
        lock.withLock { return (videoCount, audioCount, firstError) }
    }

    private func fail(_ message: String) {
        var report = false
        lock.withLock {
            if firstError == nil {
                firstError = message
                report = true
            }
        }
        if report { onFailure?(message) }
    }

    /// ScreenCaptureKit emits `.idle` / `.blank` frames when nothing on screen changes.
    /// Those carry no image buffer. Appending them makes AVAssetWriter fail with -16122
    /// and the output file is left at 0 bytes. Only `.complete` frames may be written.
    private func isCompleteFrame(_ sb: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    // MARK: SCStreamOutput

    func stream(_: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferDataIsReady(sb) else { return }

        guard writer.status == .writing else {
            if writer.status == .failed {
                fail(writer.error?.localizedDescription ?? "Writer failed")
            }
            return
        }

        switch type {
        case .screen:
            guard isCompleteFrame(sb), sb.imageBuffer != nil else { return }

            var justStarted = false
            lock.withLock {
                if !sessionStarted {
                    sessionStarted = true
                    justStarted = true
                }
            }
            // The session must be anchored to a real video frame, never to an audio buffer.
            if justStarted {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            }

            guard videoIn.isReadyForMoreMediaData else { return }
            if videoIn.append(sb) {
                lock.withLock { videoCount += 1 }
            } else {
                fail(writer.error?.localizedDescription ?? "Video append failed")
            }

        case .audio:
            // Audio arriving before the first video frame has no session to belong to.
            let ready = lock.withLock { sessionStarted }
            guard ready, audioIn.isReadyForMoreMediaData else { return }
            if audioIn.append(sb) {
                lock.withLock { audioCount += 1 }
            } else {
                fail(writer.error?.localizedDescription ?? "Audio append failed")
            }

        default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_: SCStream, didStopWithError err: Error) {
        fail("Capture stopped: \(err.localizedDescription)")
    }
}

// MARK: - View

struct ContentView: View {
    @State private var isRecording = false
    @State private var busy = false
    @State private var needsPermission = false
    // v1.1（2026-07-31）。表示を見れば、いま動いているのが新しいビルドか古い
    // プロセスの残りかを一目で判別できる。今日、古いプロセスが残っていることに
    // 気づかず1回テストを無駄にした。
    @State private var message = "Ready v1.2"
    @State private var engine: Engine?
    @State private var stream: SCStream?
    @State private var lastFile: URL?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Button(action: tap) {
                if needsPermission {
                    Label("Open Settings", systemImage: "shield").font(.title3)
                } else if isRecording {
                    Image(systemName: "stop.fill").font(.title)
                } else {
                    Image(systemName: "record.circle").font(.title)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(needsPermission ? .orange : isRecording ? .red : .blue)
            .controlSize(.large)
            .disabled(busy)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 280)

            if let file = lastFile {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Spacer()
        }
        .padding()
    }

    func tap() {
        if isRecording { stop() }
        else if needsPermission { openSettings() }
        else { start() }
    }

    // MARK: Start

    func start() {
        // ★踏んではいけない地雷（2026-07-31）
        // SCShareableContent.current を呼ぶだけでは、macOS は許可ダイアログを出さない。
        // 出さないまま -3801（userDeclined）を返すので、アプリは「設定を開いて」としか
        // 言えなくなり、ユーザーは手で登録するしかなくなる。その手動登録は定着しない。
        // CGRequestScreenCaptureAccess() を明示的に呼んで、OS 本来のダイアログを出させる。
        // この2行を消すと、また同じ袋小路に戻る。
        if !CGPreflightScreenCaptureAccess() {
            if !CGRequestScreenCaptureAccess() {
                needsPermission = true
                message = "Screen recording permission needed"
                return
            }
        }

        busy = true
        lastFile = nil
        message = "Starting…"

        Task {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    message = "No display found"
                    busy = false
                    return
                }

                // H.264 requires even dimensions. A display height like 1169 makes the
                // encoder fail immediately, which is one way the writer ends up producing
                // a 0-byte file. Round both axes down to the nearest even number.
                let width = (display.width / 2) * 2
                let height = (display.height / 2) * 2

                let cfg = SCStreamConfiguration()
                cfg.width = width
                cfg.height = height
                cfg.capturesAudio = true
                // Match the system mixer. Asking for 44100 here while CoreAudio delivers
                // 48000 forces a resample the writer does not need to do.
                cfg.sampleRate = 48_000
                cfg.channelCount = 2
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                cfg.showsCursor = true
                cfg.queueDepth = 8
                cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

                let url = try makeOutputURL()

                let writer = try AVAssetWriter(url: url, fileType: .mov)

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000]
                ]
                let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                videoIn.expectsMediaDataInRealTime = true
                guard writer.canAdd(videoIn) else {
                    message = "Video input rejected"
                    busy = false
                    return
                }
                writer.add(videoIn)

                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
                let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioIn.expectsMediaDataInRealTime = true
                guard writer.canAdd(audioIn) else {
                    message = "Audio input rejected"
                    busy = false
                    return
                }
                writer.add(audioIn)

                guard writer.startWriting() else {
                    message = "Writer failed: \(writer.error?.localizedDescription ?? "unknown")"
                    busy = false
                    return
                }

                let eng = Engine(writer: writer, vi: videoIn, ai: audioIn)
                eng.onFailure = { reason in
                    Task { @MainActor in
                        self.message = "Error: \(reason)"
                    }
                }

                let queue = DispatchQueue(label: "screenrec.capture")
                let scStream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                                        configuration: cfg,
                                        delegate: eng)
                try scStream.addStreamOutput(eng, type: .screen, sampleHandlerQueue: queue)
                try scStream.addStreamOutput(eng, type: .audio, sampleHandlerQueue: queue)
                try await scStream.startCapture()

                engine = eng
                stream = scStream
                isRecording = true
                busy = false
                message = "Recording \(width)×\(height)"

            } catch {
                let ns = error as NSError
                if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && ns.code == -3801 {
                    needsPermission = true
                    message = "Screen recording permission needed"
                } else {
                    message = error.localizedDescription
                }
                busy = false
            }
        }
    }

    // MARK: Stop

    func stop() {
        guard let scStream = stream, let eng = engine else { return }
        busy = true
        message = "Stopping…"

        Task {
            try? await scStream.stopCapture()

            eng.videoIn.markAsFinished()
            eng.audioIn.markAsFinished()
            await eng.writer.finishWriting()

            // Read stats after finishing so failures raised during the flush are included.
            let stats = eng.stats

            let url = eng.writer.outputURL
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0

            stream = nil
            engine = nil
            isRecording = false
            busy = false

            // Never claim success without checking. The previous build printed "Saved:"
            // unconditionally, which hid every failure behind a 0-byte file.
            if eng.writer.status == .completed, stats.video > 0, size > 0 {
                lastFile = url
                message = "Saved \(url.lastPathComponent) — \(stats.video) frames, \(byteString(size))"
            } else {
                let reason = stats.error
                    ?? eng.writer.error?.localizedDescription
                    ?? (stats.video == 0 ? "no video frames were captured" : "writer did not complete")
                try? FileManager.default.removeItem(at: url)
                lastFile = nil
                message = "Failed: \(reason)"
            }
        }
    }

    // MARK: Helpers

    private func makeOutputURL() throws -> URL {
        let dir = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScreenRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return dir.appendingPathComponent("Screen \(df.string(from: Date())).mov")
    }

    private func byteString(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
