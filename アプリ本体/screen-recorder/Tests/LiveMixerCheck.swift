import AVFoundation

@main struct LiveMixerCheck {
    static func main() throws {
        let mixer = LiveAudioMixer()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        var systemEarly: Float = 0, systemLate: Float = 0, micEarly: Float = 0, micLate: Float = 0
        for block in 0..<100 {
            mixer.setGains(system: block < 50 ? 0.2 : 0, microphone: block < 50 ? 0.8 : 0.3)
            for index in 0..<2 {
                let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
                pcm.frameLength = 480
                for channel in 0..<2 {
                    for j in 0..<480 { pcm.floatChannelData![channel][j] = 0.5 }
                }
                let pts = CMTime(value: Int64(block*480), timescale: 48000)
                let original = try AudioSamples.sample(pcm, time: pts)
                let (sample, monitorPCM) = try mixer.process(original, microphone: index == 1)
                let recordingPCM = try AudioSamples.pcm(sample)
                guard CMSampleBufferGetPresentationTimeStamp(sample) == pts else { fatalError("Timestamp changed") }
                for channel in 0..<2 {
                    for j in 0..<480 {
                        guard recordingPCM.floatChannelData![channel][j] == monitorPCM.floatChannelData![channel][j] else {
                            fatalError("Monitor and recording PCM differ")
                        }
                    }
                }
                if block == 40 { if index == 0 { systemEarly = recordingPCM.floatChannelData![0][479] } else { micEarly = recordingPCM.floatChannelData![0][479] } }
                if block == 90 { if index == 0 { systemLate = recordingPCM.floatChannelData![0][479] } else { micLate = recordingPCM.floatChannelData![0][479] } }
            }
        }
        guard abs(systemEarly-0.1) < 0.001, abs(micEarly-0.4) < 0.001,
              abs(systemLate) < 0.001, abs(micLate-0.15) < 0.001 else { fatalError("Live gain failed") }
        guard mixer.reading.microphone > 0.1 else { fatalError("Meter has no signal") }
        // Exercise the microphone's mono conversion path, not just stereo passthrough.
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: 480)!
        mono.frameLength = 480
        for j in 0..<480 { mono.floatChannelData![0][j] = 0.1 }
        let (_, converted) = try mixer.process(AudioSamples.sample(mono, time: CMTime(seconds: 1, preferredTimescale: 48000)), microphone: true)
        guard converted.format.channelCount == 2, converted.frameLength > 0 else { fatalError("Mono conversion failed") }
        print("PASS: live faders, mute, timestamp, meter, mono conversion; recording PCM equals monitor PCM sample-for-sample.")
        print("System \(systemEarly) -> \(systemLate); microphone \(micEarly) -> \(micLate)")
    }
}
