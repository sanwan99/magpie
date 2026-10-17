import Foundation
import GRDB
import CryptoKit

/// Transactional persistence of clips and their searchable text.
struct ClipRepository: Sendable {
    let database: Database

    init(database: Database = .shared) {
        self.database = database
    }

    static func payloadHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Inserts a freshly-detected clip — 但如果库里已有相同 type + payload + app
    /// 的记录，**只把它的 `created_at` 刷到现在**（排到最前）而不是再插一条。
    ///
    /// 场景：
    /// - 用户从 Magpie 粘贴一条 clip → Magpie 写回 pasteboard → ClipboardWatcher
    ///   监听到变化又试图 ingest 同样内容。去重避免历史里出现 2 份 / N 份相同。
    /// - 用户在同一个外部 app 重复复制同一段文本，行为同上；不同 app
    ///   保留独立来源，保证 `app:` facet 结果可信。
    ///
    /// 注意：image 类型每次保存到新文件，payload 里的 path 不同，不会被去重 —
    /// 是预期行为（不同时刻截屏也是不同图片，即使内容看着像）。
    func insert(_ detected: DetectedClip) throws {
        let hash = Self.payloadHash(detected.payload)
        try database.dbQueue.write { db in
            let existingId = try String.fetchOne(db, sql: """
                SELECT id FROM clips
                 WHERE payload_hash = ? AND type = ? AND payload = ?
                   AND ((app IS NULL AND ? IS NULL) OR app = ?)
                 ORDER BY created_at DESC
                 LIMIT 1;
            """, arguments: [
                hash,
                detected.type.rawValue,
                detected.payload,
                detected.app,
                detected.app
            ])

            let now = Date().timeIntervalSince1970

            if let existingId {
                // 已存在：只刷新 created_at 让它排到最前；pinned / tags / title /
                // FTS 内容都不动（内容本身没变）。
                try db.execute(sql: """
                    UPDATE clips SET created_at = ? WHERE id = ?;
                """, arguments: [now, existingId])
                return
            }

            let id = UUID().uuidString
            try db.execute(sql: """
                INSERT INTO clips (id, type, app, created_at, pinned, tags, title, payload, payload_hash)
                VALUES (?, ?, ?, ?, 0, '[]', ?, ?, ?);
            """, arguments: [
                id,
                detected.type.rawValue,
                detected.app,
                now,
                detected.title,
                detected.payload,
                hash
            ])
            try db.execute(sql: """
                INSERT INTO clips_fts (clip_id, title, body, tags)
                VALUES (?, ?, ?, '');
            """, arguments: [
                id,
                detected.title ?? "",
                detected.searchText
            ])
            try db.execute(sql: "UPDATE clips SET fts_rowid = ? WHERE id = ?",
                           arguments: [db.lastInsertedRowID, id])
        }
    }

    /// Bounded recent records; the UI decodes only the requested page.
    func recent(limit: Int = 100) throws -> [ClipRecord] {
        try database.dbQueue.read { db in
            try ClipRecord
                .order(Column("created_at").desc)
                .limit(max(0, min(limit, 1000)))
                .fetchAll(db)
        }
    }

    /// Total count. Useful for the search-counter UI later.
    func count() throws -> Int {
        try database.dbQueue.read { db in
            try ClipRecord.fetchCount(db)
        }
    }
}
