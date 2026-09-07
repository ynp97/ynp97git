import AVFoundation
import CoreMedia

struct MixerReading: Sendable {
    var system: Float = 0
    var microphone: Float = 0
    var clipped = false
}

// Only controls/meters cross threads; conversion and processing stay on the capture queue.
final class LiveAudioMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var requested: [Float] = [0.5, 0.5]
    private var initialized = [false, false]
    private var smoothed: [Float] = [0.5, 0.5]
    private var peaks: [Float] = [0, 0]
    private var peakTimes: [Double] = [0, 0]
    private var clipTime = -Double.infinity
    private var converters: [AVAudioConverter?] = [nil, nil]
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!

    func setGains(system: Float, microphone: Float) {
        lock.withLock { requested = [system, microphone].map { $0.isFinite ? min(1, max(0, $0)) : 0.5 } }
    }
    var reading: MixerReading {
        let now = ProcessInfo.processInfo.systemUptime
        return lock.withLock {
            let values = zip(peaks, peakTimes).map { peak, time in peak * Float(exp(-max(0, now-time-0.12)*7)) }
            return MixerReading(system: values[0], microphone: values[1], clipped: now-clipTime < 1 || values.reduce(0, +) >= 0.98)
        }
    }
    func process(_ sample: CMSampleBuffer, microphone: Bool) throws -> (CMSampleBuffer, AVAudioPCMBuffer) {
        let index = microphone ? 1 : 0
        let input = try AudioSamples.pcm(sample)
        let pcm: AVAudioPCMBuffer
        if input.format == format { pcm = input }
        else {
            if converters[index]?.inputFormat != input.format {
                converters[index] = AVAudioConverter(from: input.format, to: format)
            }
            guard let converter = converters[index],
                  let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength)*48000/input.format.sampleRate)+32)) else {
                throw RecordingError.message("音声形式を変換できません")
            }
            let feed = ConverterFeed(input)
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, status in
                return feed.take(status)
            }
            guard result != .error, output.frameLength > 0 else { throw error ?? RecordingError.message("音声変換に失敗しました") }
            pcm = output
        }
        let gain = lock.withLock { requested[index] }
        if !initialized[index] { smoothed[index] = gain; initialized[index] = true }
        var peak: Float = 0
        let channels = pcm.floatChannelData!
        for frame in 0..<Int(pcm.frameLength) {
            // 5ms ramp avoids clicks when a fader moves; it is identical for recording and listening.
            smoothed[index] += (gain-smoothed[index]) * (1.0/240.0)
            for channel in 0..<2 {
                channels[channel][frame] *= smoothed[index]
                peak = max(peak, abs(channels[channel][frame]))
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            let decayed = peaks[index] * Float(exp(-max(0, now-peakTimes[index])*7))
            peaks[index] = max(peak, decayed); peakTimes[index] = now
            if peak >= 0.98 { clipTime = now }
        }
        return (try AudioSamples.sample(pcm, time: CMSampleBufferGetPresentationTimeStamp(sample)), pcm)
    }
}

enum AudioSamples {
    static func sample(_ buffer: AVAudioPCMBuffer, time: CMTime) throws -> CMSampleBuffer {
        var description: CMAudioFormatDescription?
        var status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: buffer.format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard status == noErr, let description else { throw RecordingError.message("音声情報を作成できません: \(status)") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: description, sampleCount: Int(buffer.frameLength), sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw RecordingError.message("音声バッファを作成できません: \(status)") }
        status = CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList)
        guard status == noErr else { throw RecordingError.message("音声をコピーできません: \(status)") }
        CMSampleBufferSetDataReady(sample)
        return sample
    }
    static func pcm(_ sample: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))) else {
            throw RecordingError.message("対応しない音声形式です")
        }
        pcm.frameLength = pcm.frameCapacity
        var needed = 0
        var retained: CMBlockBuffer?
        let query = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &needed,
            bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, blockBufferOut: &retained)
        guard query == noErr, needed > 0 else { throw RecordingError.message("音声サイズを取得できません: \(query)") }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { storage.deallocate() }
        let pointer = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil,
            bufferListOut: pointer, bufferListSize: needed,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &retained)
        guard status == noErr else { throw RecordingError.message("音声を読み取れません: \(status)") }
        let list = UnsafeMutableAudioBufferListPointer(pointer)
        let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        guard list.count == destination.count else { throw RecordingError.message("音声チャンネル数が一致しません") }
        for i in 0..<list.count {
            guard let from = list[i].mData, let to = destination[i].mData,
                  list[i].mDataByteSize <= destination[i].mDataByteSize else { throw RecordingError.message("音声サイズが一致しません") }
            memcpy(to, from, Int(list[i].mDataByteSize))
        }
        return pcm
    }
}

// The exact gained PCM sent to the movie is also sent to this mixer.
// The process tap excludes our process, preventing monitoring from being recorded again.
final class HeadphoneMonitor: @unchecked Sendable {
    let audioEngine = AVAudioEngine()
    let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private var anchor: Double?
    private var queued = [0, 0]
    private var active = true
    private let lock = NSLock()
    var failure: (@Sendable (String) -> Void)?
    init() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        for player in players {
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }
    func play(_ buffer: AVAudioPCMBuffer, at time: CMTime, microphone: Bool) {
        guard lock.withLock({ active }) else { return }
        let index = microphone ? 1 : 0
        if anchor == nil {
            anchor = time.seconds
            let start = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: ProcessInfo.processInfo.systemUptime + 0.15))
            for player in players { player.play(at: start) }
        }
        let count = lock.withLock { queued[index] += 1; return queued[index] }
        guard count < 150 else { failure?("モニターの再生が追いつきません。録画を停止してください"); return }
        let position = max(0, AVAudioFramePosition((time.seconds-anchor!)*48000))
        players[index].scheduleBuffer(buffer, at: AVAudioTime(sampleTime: position, atRate: 48000), options: []) { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.queued[index] -= 1 }
        }
    }
    func stop() { lock.withLock { active = false }; for player in players { player.stop() }; audioEngine.stop() }
}


// AVAudioConverter calls this synchronously; the lock also makes one-shot ownership explicit.
private final class ConverterFeed: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let lock = NSLock()
    var supplied = false
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.withLock {
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
    }
}
