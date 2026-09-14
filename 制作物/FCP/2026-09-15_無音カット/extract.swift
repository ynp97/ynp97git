import Foundation
import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let reader = try AVAssetReader(asset: asset)
let track = asset.tracks(withMediaType: .audio)[0]
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey:kAudioFormatLinearPCM, AVLinearPCMBitDepthKey:16, AVLinearPCMIsFloatKey:false, AVLinearPCMIsBigEndianKey:false, AVLinearPCMIsNonInterleaved:false])
reader.add(output)
FileManager.default.createFile(atPath:CommandLine.arguments[2], contents:nil)
let file = FileHandle(forWritingAtPath:CommandLine.arguments[2])!
reader.startReading()
while let sample = output.copyNextSampleBuffer() {
 if let block = CMSampleBufferGetDataBuffer(sample) {
  let size = CMBlockBufferGetDataLength(block)
  var bytes = [UInt8](repeating:0,count:size)
  CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:size,destination:&bytes)
  file.write(Data(bytes))
 }
}
file.closeFile()
print("status",reader.status.rawValue,"duration",CMTimeGetSeconds(asset.duration),"error",String(describing:reader.error))
