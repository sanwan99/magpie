import Foundation
import GRDB

/// Owns the on-disk SQLite database and migrations.
/// The database lives in `~/Library/Application Support/Magpie/clips.sqlite`.
@MainActor
final class Database {
    static let shared = Database()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let url = Self.databaseURL()
            self.dbQueue = try DatabaseQueue(path: url.path)
            try Self.migrate(dbQueue)
            NSLog("[storage] database ready at %@", url.path)
        } catch {
            // Bootstrap-time failure — surface immediately rather than degrading silently.
            fatalError("Magpie database init failed: \(error)")
        }
    }

    private static func databaseURL() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Magpie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clips.sqlite")
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: """
                CREATE TABLE clips (
                    id          TEXT PRIMARY KEY,
                    type        TEXT NOT NULL,
                    app         TEXT,
                    created_at  REAL NOT NULL,
                    pinned      INTEGER NOT NULL DEFAULT 0,
                    tags        TEXT NOT NULL DEFAULT '[]',
                    title       TEXT,
                    payload     BLOB NOT NULL
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_clips_created_at ON clips(created_at DESC);")
            try db.execute(sql: "CREATE INDEX idx_clips_type        ON clips(type);")
            try db.execute(sql: "CREATE INDEX idx_clips_pinned      ON clips(pinned, created_at DESC);")

            // External-content FTS5 — body is denormalized at insert time.
            // Cleaner contentless / triggered design lands in v0.2 once UI demands tighter sync.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE clips_fts USING fts5(
                    clip_id UNINDEXED,
                    title,
                    body,
                    tags,
                    tokenize='porter unicode61'
                );
            """)
        }
        // v0.3-b: snippets — user-defined templates (e.g. ;sig → signature).
        migrator.registerMigration("v2_snippets") { db in
            try db.execute(sql: """
                CREATE TABLE snippets (
                    id          TEXT PRIMARY KEY,
                    shortcut    TEXT NOT NULL UNIQUE,
                    title       TEXT NOT NULL,
                    body        TEXT NOT NULL,
                    created_at  REAL NOT NULL,
                    updated_at  REAL NOT NULL
                );
            """)
            try db.execute(sql: "CREATE INDEX idx_snippets_shortcut ON snippets(shortcut);")
        }
        try migrator.migrate(queue)
    }
}
