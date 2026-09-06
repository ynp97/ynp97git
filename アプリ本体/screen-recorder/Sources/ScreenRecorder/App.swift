import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AppKit
import CoreGraphics

// MARK: - App

@main
struct App: SwiftUI.App {
    @NSApplicationDelegateAdaptor(RecordingAppDelegate.self) var delegate
    var body: some Scene {
        Window("スクトレル", id: "main") {
            ContentView().frame(width: 320, height: 280).fixedSize()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor enum RecordingLifecycle { static var active = false }
@MainActor final class RecordingAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard RecordingLifecycle.active else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "録画の保存が終わってから終了してください"
        alert.informativeText = "録画中なら「録画を停止」を押してください。"
        alert.addButton(withTitle: "戻る")
        alert.runModal()
        return .terminateCancel
    }
}

// MARK: - Engine

final class Engine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let writer: AVAssetWriter
    let videoIn: AVAssetWriterInput
    let audioIn: AVAssetWriterInput
    let micIn: AVAssetWriterInput

    private let lock = NSLock()
    private var sessionStarted = false
    private var sessionTime = CMTime.zero
    private var lastFrame: CMSampleBuffer?
    private var lastMediaTime = CMTime.zero
    private var videoCount = 0
    private var audioCount = 0
    private var micCount = 0
    private var firstError: String?

    /// Called from the capture queue when the writer or the stream dies mid-recording.
    var onFailure: ((String) -> Void)?

    init(writer: AVAssetWriter, vi: AVAssetWriterInput, ai: AVAssetWriterInput, mi: AVAssetWriterInput) {
        self.writer = writer
        self.videoIn = vi
        self.audioIn = ai
        self.micIn = mi
        super.init()
    }

    var stats: (video: Int, audio: Int, mic: Int, error: String?) {
        lock.withLock { return (videoCount, audioCount, micCount, firstError) }
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
                    sessionTime = CMSampleBufferGetPresentationTimeStamp(sb)
                    justStarted = true
                }
            }
            // The session must be anchored to a real video frame, never to an audio buffer.
            if justStarted {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sb))
            }

            guard videoIn.isReadyForMoreMediaData else { return }
            lastFrame = sb
            lastMediaTime = CMTimeMaximum(lastMediaTime, CMSampleBufferGetPresentationTimeStamp(sb))
            if videoIn.append(sb) {
                lock.withLock { videoCount += 1 }
            } else {
                fail(writer.error?.localizedDescription ?? "Video append failed")
            }

        case .audio:
            // Audio arriving before the first video frame has no session to belong to.
            let ready = lock.withLock { sessionStarted }
            guard ready, CMSampleBufferGetPresentationTimeStamp(sb) >= sessionTime, audioIn.isReadyForMoreMediaData else { return }
            lastMediaTime = CMTimeMaximum(lastMediaTime, CMSampleBufferGetPresentationTimeStamp(sb))
            if audioIn.append(sb) {
                lock.withLock { audioCount += 1 }
            } else {
                fail(writer.error?.localizedDescription ?? "Audio append failed")
            }

        case .microphone:
            let ready = lock.withLock { sessionStarted }
            guard ready, CMSampleBufferGetPresentationTimeStamp(sb) >= sessionTime, micIn.isReadyForMoreMediaData else { return }
            lastMediaTime = CMTimeMaximum(lastMediaTime, CMSampleBufferGetPresentationTimeStamp(sb))
            if micIn.append(sb) {
                lock.withLock { micCount += 1 }
            } else {
                fail(writer.error?.localizedDescription ?? "Microphone append failed")
            }

        default:
            break
        }
    }

    // Run on the sample queue after capture has stopped. ScreenCaptureKit sends no
    // complete frames for a static slide; extend its final image to the audio end.
    func finishInputs() {
        guard writer.status == .writing else { return }
        if writer.status == .writing, let frame = lastFrame,
           lastMediaTime > CMSampleBufferGetPresentationTimeStamp(frame), videoIn.isReadyForMoreMediaData {
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                           presentationTimeStamp: lastMediaTime, decodeTimeStamp: .invalid)
            var copy: CMSampleBuffer?
            if CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: frame,
                 sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy) == noErr,
               let copy, !videoIn.append(copy) {
                fail(writer.error?.localizedDescription ?? "Final frame failed")
            }
        }
        videoIn.markAsFinished()
        audioIn.markAsFinished()
        micIn.markAsFinished()
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
    @State private var message = "画面・相手の音・自分の声を録画します"
    @State private var permissionPane = "Privacy_ScreenCapture"
    @State private var startedAt: Date?
    @State private var captureQueue: DispatchQueue?
    @State private var engine: Engine?
    @State private var stream: SCStream?
    @State private var lastFile: URL?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Button(action: tap) {
                if needsPermission {
                    Label("設定を開く", systemImage: "shield").font(.title3)
                } else if isRecording {
                    Label("録画を停止", systemImage: "stop.fill").font(.title3)
                } else {
                    Label("録画を開始", systemImage: "record.circle").font(.title3)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(needsPermission ? .orange : isRecording ? .red : .blue)
            .controlSize(.large)
            .disabled(busy)

            if let startedAt, isRecording {
                Text(startedAt, style: .timer).monospacedDigit()
            }
            Text("スクトレル 1.3").font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 280)

            if let file = lastFile {
                Button("保存した動画を表示") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Spacer()
        }
        .padding()
        .onChange(of: busy) { _, _ in RecordingLifecycle.active = busy || isRecording }
        .onChange(of: isRecording) { _, _ in RecordingLifecycle.active = busy || isRecording }
        .task {
            // Opt-in local integration check. Normal launches never auto-record.
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--recording-check"), args.count > index + 1 {
                let report = URL(fileURLWithPath: args[index + 1])
                start()
                while busy { try? await Task.sleep(for: .milliseconds(100)) }
                writeCheckReport(to: report)
                if isRecording {
                    try? await Task.sleep(for: .seconds(10))
                    stop()
                    while busy { try? await Task.sleep(for: .milliseconds(100)) }
                    writeCheckReport(to: report)
                }
            }
        }
    }

    private func writeCheckReport(to url: URL) {
        let report: [String: Any] = ["recording": isRecording, "needsPermission": needsPermission,
                                    "message": message, "file": lastFile?.path ?? ""]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
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
                permissionPane = "Privacy_ScreenCapture"
                message = "画面収録を許可して、アプリを開き直してください"
                return
            }
        }

        busy = true
        lastFile = nil
        message = "Starting…"

        Task {
            do {
                // Refuse to silently produce a meeting recording without our voice.
                let micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard micAllowed else {
                    permissionPane = "Privacy_Microphone"
                    needsPermission = true
                    message = "自分の声を録るため、マイクを許可してください"
                    busy = false
                    return
                }
                let content = try await SCShareableContent.current
                guard let display = (content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first) else {
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
                cfg.captureMicrophone = true
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

                let micIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                micIn.expectsMediaDataInRealTime = true
                guard writer.canAdd(micIn) else { throw RecordingError.message("マイク音声を保存できません") }
                writer.add(micIn)

                guard writer.startWriting() else {
                    message = "Writer failed: \(writer.error?.localizedDescription ?? "unknown")"
                    busy = false
                    return
                }

                let eng = Engine(writer: writer, vi: videoIn, ai: audioIn, mi: micIn)
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
                try scStream.addStreamOutput(eng, type: .microphone, sampleHandlerQueue: queue)
                // Keep ownership even if startup fails, so we can close the partial writer.
                engine = eng
                stream = scStream
                captureQueue = queue
                try await scStream.startCapture()

                engine = eng
                stream = scStream
                startedAt = Date()
                isRecording = true
                busy = false
                message = "録画中 — 画面・相手の音・自分の声"

            } catch {
                if let stream { try? await stream.stopCapture() }
                engine?.writer.cancelWriting()
                engine = nil
                stream = nil
                captureQueue = nil
                let ns = error as NSError
                if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && ns.code == -3801 {
                    needsPermission = true
                    permissionPane = "Privacy_ScreenCapture"
                    message = "画面収録を許可して、アプリを開き直してください"
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
        message = "録画を保存しています…"

        Task {
            var stopError: String?
            do { try await scStream.stopCapture() }
            catch { stopError = error.localizedDescription }
            // Drain the serial sample queue before finishing inputs (no append/finish race).
            if let queue = captureQueue {
                await withCheckedContinuation { continuation in
                    queue.async { eng.finishInputs(); continuation.resume() }
                }
            }

            if eng.writer.status == .writing { await eng.writer.finishWriting() }

            // Read stats after finishing so failures raised during the flush are included.
            let stats = eng.stats

            let url = eng.writer.outputURL
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0

            stream = nil
            engine = nil
            isRecording = false
            startedAt = nil
            captureQueue = nil

            // Never claim success without checking. The previous build printed "Saved:"
            // unconditionally, which hid every failure behind a 0-byte file.
            if eng.writer.status == .completed, stats.video > 0, size > 0 {
                lastFile = url // Original is recoverable if mixing fails.
                do {
                    guard stats.mic > 0, stats.audio > 0 else {
                        throw RecordingError.message("一方の音声が取得できませんでした。元の録画を残しました")
                    }
                    message = "両方の音声をまとめています…"
                    let finalURL = try await RecordingFinalizer.finalize(url, keepSource: ProcessInfo.processInfo.arguments.contains("--recording-check"))
                    lastFile = finalURL
                    if let reason = stopError ?? stats.error {
                        message = "途中で録画が中断しました: \(reason)。保存できた部分を残しました"
                    } else {
                        message = "保存しました — 画面・相手の音・自分の声"
                    }
                } catch {
                    message = "保存の確認が必要です: \(error.localizedDescription)"
                }
            } else {
                let reason = stats.error
                    ?? eng.writer.error?.localizedDescription
                    ?? (stats.video == 0 ? "no video frames were captured" : "writer did not complete")
                // A failed movie can still contain recoverable meeting data. Only delete empties.
                if size == 0 { try? FileManager.default.removeItem(at: url) }
                lastFile = size > 0 ? url : nil
                message = "保存失敗: \(reason)"
            }
            busy = false
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
        return dir.appendingPathComponent("Screen \(df.string(from: Date())) \(UUID().uuidString.prefix(6)).source.mov")
    }

    private func byteString(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(permissionPane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
