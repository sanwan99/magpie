import Foundation
import GRDB

/// CRUD facade over `Database`. v0.1 only needs `insert` and `recent`;
/// search/Pin/delete land in v0.2.
struct ClipRepository: Sendable {
    let database: Database

    init(database: Database = .shared) {
        self.database = database
    }

    /// Inserts a freshly-detected clip — 但如果库里已有相同 type + payload 的
    /// 记录，**只把它的 `created_at` 刷到现在**（排到最前）而不是再插一条。
    ///
    /// 场景：
    /// - 用户从 Magpie 粘贴一条 clip → Magpie 写回 pasteboard → ClipboardWatcher
    ///   监听到变化又试图 ingest 同样内容。去重避免历史里出现 2 份 / N 份相同。
    /// - 用户在外部 app 重复复制同一段文本，行为同上。
    ///
    /// 注意：image 类型每次保存到新文件，payload 里的 path 不同，不会被去重 —
    /// 是预期行为（不同时刻截屏也是不同图片，即使内容看着像）。
    func insert(_ detected: DetectedClip) throws {
        try database.dbQueue.write { db in
            let existingId = try String.fetchOne(db, sql: """
                SELECT id FROM clips
                 WHERE type = ? AND payload = ?
                 ORDER BY created_at DESC
                 LIMIT 1;
            """, arguments: [detected.type.rawValue, detected.payload])

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
                INSERT INTO clips (id, type, app, created_at, pinned, tags, title, payload)
                VALUES (?, ?, ?, ?, 0, '[]', ?, ?);
            """, arguments: [
                id,
                detected.type.rawValue,
                detected.app,
                now,
                detected.title,
                detected.payload
            ])
            try db.execute(sql: """
                INSERT INTO clips_fts (clip_id, title, body, tags)
                VALUES (?, ?, ?, '');
            """, arguments: [
                id,
                detected.title ?? "",
                detected.searchText
            ])
        }
    }

    /// Most recent N clips. v0.1 returns `ClipRecord` (raw row);
    /// the UI layer in step 7 will lift these into typed `Clip` view models.
    func recent(limit: Int = 100) throws -> [ClipRecord] {
        try database.dbQueue.read { db in
            try ClipRecord
                .order(Column("created_at").desc)
                .limit(limit)
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
