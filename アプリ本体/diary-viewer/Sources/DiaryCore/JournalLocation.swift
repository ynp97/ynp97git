import Foundation

/// 読込・保存・退避の照合で一つの名前を選ぶ。二系統は自動統合しない。
public enum JournalLocation {
    public static func directory(in root: URL) throws -> URL {
        let fm = FileManager.default
        let japanese = root.appendingPathComponent("ジャーナル")
        let english = root.appendingPathComponent("journal")
        let hasJapanese = fm.fileExists(atPath: japanese.path)
        let hasEnglish = fm.fileExists(atPath: english.path)
        guard !(hasJapanese && hasEnglish) else {
            throw DiaryError.invalid("ジャーナルとjournalが両方あります。自動で選ばず停止しました。受け箱から救出用の退避を作成できます。")
        }
        return hasEnglish ? english : japanese
    }
}
