import Foundation
import GRDB

/// CRUD facade over `Database`. v0.1 only needs `insert` and `recent`;
/// search/Pin/delete land in v0.2.
struct ClipRepository {
    let database: Database

    init(database: Database = .shared) {
        self.database = database
    }

    /// Inserts a freshly-detected clip and its FTS index row in one transaction.
    /// Throws on SQL failure; caller should log + drop.
    func insert(_ detected: DetectedClip) throws {
        let id = UUID().uuidString
        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO clips (id, type, app, created_at, pinned, tags, title, payload)
                VALUES (?, ?, ?, ?, 0, '[]', ?, ?);
            """, arguments: [
                id,
                detected.type.rawValue,
                detected.app,
                Date().timeIntervalSince1970,
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
