import AVFoundation
import CoreVideo

@main struct AudioMixCheck {
    static func main() async throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let source = dir.appendingPathComponent("test.source.mov")
        let writer = try AVAssetWriter(url: source, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        writer.add(video)
        var inputs: [AVAssetWriterInput] = []
        for _ in 0..<2 {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000])
            writer.add(input); inputs.append(input)
        }
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
        for frame in 0..<120 {
            while !video.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            guard adaptor.append(buffer!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
        }
        video.markAsFinished()
        }
        for i in 0..<2 {
          group.addTask {
            let asset = AVURLAsset(url: dir.appendingPathComponent("tone\(i).wav"))
            let track = try await asset.loadTracks(withMediaType: .audio).first!
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(output); reader.startReading()
            while let sample = output.copyNextSampleBuffer() {
                while !inputs[i].isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
                var timing = CMSampleTimingInfo()
                CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
                timing.presentationTimeStamp = timing.presentationTimeStamp + CMTime(seconds: i == 0 ? 0 : 0.5, preferredTimescale: 48000)
                var shifted: CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &shifted)
                guard inputs[i].append(shifted!) else { throw writer.error! }
            }
            guard reader.status == .completed else { throw reader.error! }
            inputs[i].markAsFinished()
          }
        }
        try await group.waitForAll()
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        let systemGain = CommandLine.arguments.count > 2 ? Float(CommandLine.arguments[2])! : 0.5
        let micGain = CommandLine.arguments.count > 3 ? Float(CommandLine.arguments[3])! : 0.5
        let result = try await RecordingFinalizer.finalize(source, systemGain: systemGain, microphoneGain: micGain)
        let asset = AVURLAsset(url: result)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1 else { fatalError("Expected one audio track") }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); reader.startReading()
        var samples = [Float]()
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let length = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating: 0, count: length / 4)
            values.withUnsafeMutableBytes { raw in _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!) }
            samples += values
        }
        func amplitude(_ frequency: Double, _ start: Double) -> Double {
            let first = Int(start * 48000), count = 9600
            guard first + count <= samples.count else { fatalError("Audio truncated") }
            var real = 0.0, imag = 0.0
            for j in 0..<count {
                let angle = 2 * Double.pi * frequency * Double(j) / 48000
                real += Double(samples[first+j]) * cos(angle)
                imag += Double(samples[first+j]) * sin(angle)
            }
            return 2 * hypot(real, imag) / Double(count)
        }
        let early440 = amplitude(440, 0.1), early880 = amplitude(880, 0.1)
        let late440 = amplitude(440, 1), late880 = amplitude(880, 1)
        let expectedSystem = Double(systemGain) * 16000 / 32768
        let expectedMic = Double(micGain) * 16000 / 32768
        guard abs(early440 - expectedSystem) < 0.02, early880 < 0.01,
              abs(late440 - expectedSystem) < 0.02, abs(late880 - expectedMic) < 0.02 else {
            fatalError("Mix/offset failed: \(early440), \(early880), \(late440), \(late880)")
        }
        do {
            _ = try await RecordingFinalizer.finalize(result)
            fatalError("Expected rejection for one audio track")
        } catch {
            guard FileManager.default.fileExists(atPath: result.path) else { fatalError("Failure deleted source") }
        }
        print("PASS: incomplete audio rejected and original file retained.")
        print("PASS: one audio track; gains system=\(systemGain) mic=\(micGain); microphone offset preserved.")
        print("Amplitudes early440=\(early440), early880=\(early880), late440=\(late440), late880=\(late880)")
        print(result.path)
    }
}
