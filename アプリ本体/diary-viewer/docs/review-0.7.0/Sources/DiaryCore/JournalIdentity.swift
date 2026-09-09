import Foundation

/// IDなしの日記は原文全体の一致で照合する。日付や表示本文から同一性を推測しない。
/// 同文の複数件は、ファイル全体が同じ場合だけ位置で区別できる。
struct JournalIdentity: Codable {
    struct Record: Codable {
        let id: UUID
        let hash: String
        let explicit: Bool
    }
    struct File: Codable {
        let hash: String
        let records: [Record]
    }
    var files: [String: File] = [:]
    var ids: [String: [UUID]] { files.mapValues { $0.records.map(\.id) } }

    func resolving(files input: [String: Data]) throws -> JournalIdentity {
        let documents = try input.mapValues { try OriginalJournal(data: $0) }
        let old = files.values.flatMap(\.records).filter { !$0.explicit }
        let groups = Dictionary(grouping: old, by: \.hash)
        var used = Set<UUID>()
        var next = JournalIdentity()
        var newLegacy = false
        let conflict = DiaryError.invalid("既存日記のIDを一意に対応できません。外部編集・重複を確認してください。以前の対応表は保持しています。")

        // 明示IDは全年で重複を検査する（ファイル単位の検査だけでは足りない）。
        for document in documents.values {
            for block in document.blocks {
                if let id = block.explicitID {
                    guard used.insert(id).inserted, !old.contains(where: { $0.id == id }) else { throw conflict }
                }
            }
        }
        for name in documents.keys.sorted() {
            let document = documents[name]!
            let hash = contentHash(document.data)
            let unchanged = files[name]?.hash == hash
            var records: [Record] = []
            for (index, block) in document.blocks.enumerated() {
                let blockHash = contentHash(block.data)
                if let id = block.explicitID {
                    records.append(Record(id: id, hash: blockHash, explicit: true))
                    continue
                }
                let id: UUID
                if unchanged, let previous = files[name], previous.records.indices.contains(index) {
                    let record = previous.records[index]
                    guard !record.explicit, record.hash == blockHash else { throw conflict }
                    id = record.id
                } else if let candidates = groups[blockHash] {
                    guard candidates.count == 1 else { throw conflict }
                    id = candidates[0].id
                } else {
                    id = UUID()
                    newLegacy = true
                }
                guard used.insert(id).inserted else { throw conflict }
                records.append(Record(id: id, hash: blockHash, explicit: false))
            }
            next.files[name] = File(hash: hash, records: records)
        }
        // 旧ブロック消失と新ブロック出現が同時なら「削除＋新規」と勝手に決めない。
        // 本文訂正・日付訂正の可能性があり、自動的なID再発行は関連を失う。
        if newLegacy && old.contains(where: { !used.contains($0.id) }) { throw conflict }
        return next
    }
}
