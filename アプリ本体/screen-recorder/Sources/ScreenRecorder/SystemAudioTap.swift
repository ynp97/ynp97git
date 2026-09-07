import CoreAudio
import AVFoundation

// Public Core Audio process tap. No virtual driver, default-device change or persistent mute.
// The original audio is suppressed only while this private tap is actively read.
final class SystemAudioTap: @unchecked Sendable {
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var io: AudioDeviceIOProcID?
    private var format: AVAudioFormat?
    private var running = false
    private var configurationObserver: NSObjectProtocol?

    func start(queue: DispatchQueue, onSample: @escaping @Sendable (CMSampleBuffer) -> Void,
               onFailure: @escaping @Sendable (String) -> Void) throws {
        do {
            var pid = getpid(), ownProcess: AudioObjectID = 0
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &ownProcess), "自分の音声経路の識別")
            guard ownProcess != kAudioObjectUnknown else { throw RecordingError.message("モニター音の除外対象を特定できません") }
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
            description.name = "スクトレル・モニター"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try check(AudioHardwareCreateProcessTap(description, &tap), "パソコンの音の取り込み")
            var asbd = AudioStreamBasicDescription()
            address.mSelector = kAudioTapPropertyFormat
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd), "音声形式の取得")
            guard let format = AVAudioFormat(streamDescription: &asbd) else { throw RecordingError.message("モニターの音声形式に対応できません") }
            self.format = format
            let settings: [String: Any] = [
                kAudioAggregateDeviceNameKey: "スクトレル・録音用",
                kAudioAggregateDeviceUIDKey: "com.screenrecorder.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                   kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device), "音声経路の作成")
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, device, queue) { [weak self] _, input, inputTime, _, _ in
                guard let self, let format = self.format else { return }
                let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                guard let first = buffers.first, first.mDataByteSize > 0 else { return }
                let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
                guard bytesPerFrame > 0,
                      let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: first.mDataByteSize / bytesPerFrame) else { return }
                pcm.frameLength = pcm.frameCapacity
                let destination = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
                guard destination.count == buffers.count else { onFailure("モニターのチャンネル数が変わりました"); return }
                for i in 0..<buffers.count {
                    guard let from = buffers[i].mData, let to = destination[i].mData,
                          buffers[i].mDataByteSize <= destination[i].mDataByteSize else { return }
                    memcpy(to, from, Int(buffers[i].mDataByteSize))
                }
                let time = CMTime(seconds: AVAudioTime.seconds(forHostTime: inputTime.pointee.mHostTime), preferredTimescale: 48000)
                do { onSample(try AudioSamples.sample(pcm, time: time)) }
                catch { onFailure(error.localizedDescription) }
            }, "音声の受信準備")
            try check(AudioDeviceStart(device, io), "音声の受信開始")
            running = true
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: nil, queue: nil) { _ in onFailure("音声機器の接続が変わりました。保存して停止します") }
        } catch { stop(); throw error }
    }
    func stop() {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        if running { AudioDeviceStop(device, io); running = false }
        if let io { AudioDeviceDestroyIOProcID(device, io) }
        io = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }
    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw RecordingError.message("\(operation)に失敗しました（\(status)）") }
    }
}
