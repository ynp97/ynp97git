import AVFoundation
import CoreImage

@main struct InspectMovie {
    static func main() async throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let asset = AVURLAsset(url: url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        print("file=\(url.lastPathComponent) duration=\(duration) videoTracks=\(videos.count) audioTracks=\(audios.count)")
        for (index, track) in audios.enumerated() {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
            reader.add(output)
            guard reader.startReading() else { throw reader.error! }
            var count = 0, energy = 0.0, peak = 0.0
            while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
                let size = CMBlockBufferGetDataLength(block)
                var data = [Float](repeating: 0, count: size/4)
                data.withUnsafeMutableBytes { raw in _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: raw.baseAddress!) }
                for value in data { let x = Double(value); energy += x*x; peak = max(peak, abs(x)) }
                count += data.count
            }
            guard reader.status == .completed else { throw reader.error! }
            print("audio[\(index)] samples=\(count) rms=\(sqrt(energy/Double(max(1,count)))) peak=\(peak)")
        }
        if let track = videos.first {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            reader.add(output); reader.startReading()
            var frames = 0, last = 0.0
            while let sample = output.copyNextSampleBuffer() {
                guard CMSampleBufferGetImageBuffer(sample) != nil else { fatalError("Video decode failed") }
                frames += 1; last = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            }
            guard reader.status == .completed, frames > 0 else { throw reader.error ?? RecordingError.message("No frames") }
            print("video decodedFrames=\(frames) lastFrame=\(last)")
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 960, height: 600)
            let (image, _) = try await generator.image(at: CMTime(seconds: duration/2, preferredTimescale: 600))
            let imageURL = URL(fileURLWithPath: "/private/tmp/screenrec-checked-frame.png")
            let context = CIContext()
            try context.writePNGRepresentation(of: CIImage(cgImage: image), to: imageURL, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            print("frame=\(imageURL.path)")
        }
    }
}
