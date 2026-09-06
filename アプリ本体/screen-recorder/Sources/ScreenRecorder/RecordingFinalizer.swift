import AVFoundation

// Two independent capture clocks are kept in the source movie. AVFoundation mixes
// them on that movie's timeline; never interleave microphone samples into audioIn.
enum RecordingError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum RecordingFinalizer {
    static func finalize(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 2 else { throw RecordingError.message("音声が2系統そろっていません。元の録画を残しました") }
        let stem = source.deletingPathExtension().deletingPathExtension()
        let mixed = stem.appendingPathExtension("mixed.m4a")
        let final = stem.appendingPathExtension("mov")
        let staging = stem.appendingPathExtension("saving.mov")
        defer {
            try? FileManager.default.removeItem(at: mixed)
            try? FileManager.default.removeItem(at: staging)
        }

        let audioComposition = AVMutableComposition()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for track in tracks {
            guard let dest = audioComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw RecordingError.message("音声をまとめる準備に失敗しました")
            }
            let range = try await track.load(.timeRange)
            try dest.insertTimeRange(range, of: track, at: range.start)
            let parameter = AVMutableAudioMixInputParameters(track: dest)
            // Headroom for simultaneous speech; preserve relative input levels.
            parameter.setVolume(0.5, at: .zero)
            parameters.append(parameter)
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        guard let audioExport = AVAssetExportSession(asset: audioComposition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingError.message("音声の書き出しを開始できません")
        }
        audioExport.audioMix = mix
        try await audioExport.export(to: mixed, as: .m4a)

        // Copy the compressed video; a long meeting must not be re-encoded just to mix audio.
        let result = AVMutableComposition()
        guard let video = try await asset.loadTracks(withMediaType: .video).first,
              let outputVideo = result.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecordingError.message("映像が見つかりません")
        }
        let videoRange = try await video.load(.timeRange)
        try outputVideo.insertTimeRange(videoRange, of: video, at: videoRange.start)
        outputVideo.preferredTransform = try await video.load(.preferredTransform)
        let mixedAsset = AVURLAsset(url: mixed)
        guard let audio = try await mixedAsset.loadTracks(withMediaType: .audio).first,
              let outputAudio = result.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw RecordingError.message("まとめた音声が見つかりません")
        }
        let audioRange = try await audio.load(.timeRange)
        try outputAudio.insertTimeRange(audioRange, of: audio, at: audioRange.start)
        guard let movieExport = AVAssetExportSession(asset: result, presetName: AVAssetExportPresetPassthrough) else {
            throw RecordingError.message("動画の保存を開始できません")
        }
        try await movieExport.export(to: staging, as: .mov)
        let check = AVURLAsset(url: staging)
        let videos = try await check.loadTracks(withMediaType: .video)
        let audios = try await check.loadTracks(withMediaType: .audio)
        let duration = try await check.load(.duration).seconds
        let originalDuration = try await asset.load(.duration).seconds
        guard videos.count == 1, audios.count == 1, duration > 0,
              abs(duration - originalDuration) < 0.25,
              ((try FileManager.default.attributesOfItem(atPath: staging.path)[.size]) as? Int ?? 0) > 0 else {
            throw RecordingError.message("保存した動画の内容確認に失敗しました。元の録画を残しました")
        }
        try FileManager.default.moveItem(at: staging, to: final)
        // Only remove the original after both exports and the final movie checks succeed.
        try? FileManager.default.removeItem(at: source)
        return final
    }
}
