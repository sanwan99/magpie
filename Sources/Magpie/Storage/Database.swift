import Foundation
import GRDB

/// Owns the on-disk SQLite database and migrations.
/// The database lives in `~/Library/Application Support/Magpie/clips.sqlite`.
final class Database: @unchecked Sendable {
    static let shared = Database()

    let dbQueue: DatabaseQueue
    // Coordinates PNG creation + database commit with retention and clear.
    // Always acquire before dbQueue; never await while holding this lock.
    private let storageLock = NSRecursiveLock()
    private let generationLock = NSLock()
    private var ingestGeneration: UInt64 = 0

    // Separate, short-held lock: capturing a generation never waits for PNG I/O.
    var currentIngestGeneration: UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return ingestGeneration
    }

    /// Called under storageLock before clearing history; invalidates queued snapshots.
    func invalidatePendingIngests() {
        generationLock.lock()
        defer { generationLock.unlock() }
        ingestGeneration &+= 1
    }

    func withStorageLock<T>(_ work: () throws -> T) rethrows -> T {
        storageLock.lock()
        defer { storageLock.unlock() }
        return try work()
    }

    private init() {
        do {
            let url = try Self.databaseURL()
            self.dbQueue = try DatabaseQueue(path: url.path)
            try Self.migrate(dbQueue)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            NSLog("[storage] database ready")
        } catch {
            // Bootstrap-time failure — surface immediately rather than degrading silently.
            DiagnosticLog.failure("storage.initialize", error: error)
            fatalError("Magpie database initialization failed; inspect local storage permissions and disk space.")
        }
    }

    /// Test-only initializer that wires up an in-memory queue with the same
    /// migrations as production. Lets unit tests exercise repositories without
    /// touching the user's real database.
    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Self.migrate(dbQueue)
    }

    /// Returns a fresh in-memory Database — every call gets a new instance with
    /// its own data, fully migrated. For tests only.
    static func makeInMemoryForTests() -> Database {
        do {
            let queue = try DatabaseQueue()  // in-memory by default
            return try Database(dbQueue: queue)
        } catch {
            fatalError("In-memory database initialization failed")
        }
    }

    private static func databaseURL() throws -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Magpie", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appendingPathComponent("clips.sqlite")
    }

    static func migrate(_ queue: DatabaseQueue, upTo target: String? = nil) throws {
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

            // Contentful FTS5: it owns a second copy of searchable text.
            // v4 repairs old orphan entries and makes deletion transactional.
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
        // Pinned clip notes. Kept on the clip row so notes survive unpin/re-pin,
        // while UI still exposes editing only for pinned clips.
        migrator.registerMigration("v3_clip_notes") { db in
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN note TEXT NOT NULL DEFAULT '';")
        }
        // Preserve existing FTS body/tags while assigning a durable FTS row ID.
        // A temporary B-tree makes the upgrade linear/log-linear, not N scans.
        migrator.registerMigration("v4_fts_cleanup") { db in
            try db.execute(sql: """
                ALTER TABLE clips ADD COLUMN fts_rowid INTEGER;
                CREATE TEMP TABLE magpie_fts_ids AS
                    SELECT clip_id, MIN(rowid) AS fts_rowid FROM clips_fts GROUP BY clip_id;
                CREATE INDEX temp.magpie_fts_ids_clip ON magpie_fts_ids(clip_id);
                UPDATE clips SET fts_rowid = (
                    SELECT fts_rowid FROM magpie_fts_ids WHERE clip_id = clips.id
                );
                DELETE FROM clips_fts WHERE rowid NOT IN (
                    SELECT fts_rowid FROM clips WHERE fts_rowid IS NOT NULL
                );
                DROP TABLE temp.magpie_fts_ids;
                CREATE UNIQUE INDEX idx_clips_fts_rowid ON clips(fts_rowid);
                CREATE TRIGGER clips_delete_fts AFTER DELETE ON clips
                WHEN OLD.fts_rowid IS NOT NULL BEGIN
                    DELETE FROM clips_fts WHERE rowid = OLD.fts_rowid;
                END;
                CREATE TRIGGER clips_delete_legacy_fts AFTER DELETE ON clips
                WHEN OLD.fts_rowid IS NULL BEGIN
                    DELETE FROM clips_fts WHERE clip_id = OLD.id;
                END;
                """)
            // Repair rows whose old index entry was missing without changing payloads.
            while true {
                let records = try ClipRecord.fetchAll(db, sql: "SELECT * FROM clips WHERE fts_rowid IS NULL LIMIT 200")
                if records.isEmpty { break }
                for record in records {
                    let object = (try? JSONSerialization.jsonObject(with: record.payload)) as? [String: Any]
                    let body = (object?["body"] ?? object?["url"] ?? object?["path"]) as? String ?? record.title ?? ""
                    try db.execute(sql: "INSERT INTO clips_fts(clip_id, title, body, tags) VALUES (?, ?, ?, ?)",
                                   arguments: [record.id, record.title ?? "", body, record.tags])
                    try db.execute(sql: "UPDATE clips SET fts_rowid = ? WHERE id = ?",
                                   arguments: [db.lastInsertedRowID, record.id])
                }
            }
        }
        migrator.registerMigration("v5_dedup_hash") { db in
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN payload_hash TEXT;")
            // Bounded batches preserve payloads and avoid loading entire histories.
            var lastRowID: Int64 = .min
            while true {
                let rows = try Row.fetchAll(db, sql: "SELECT rowid, id, payload FROM clips WHERE rowid > ? ORDER BY rowid LIMIT 200", arguments: [lastRowID])
                if rows.isEmpty { break }
                for row in rows {
                    let payload: Data = row["payload"]
                    let id: String = row["id"]
                    lastRowID = row["rowid"]
                    try db.execute(sql: "UPDATE clips SET payload_hash = ? WHERE id = ?",
                                   arguments: [ClipRepository.payloadHash(payload), id])
                }
            }
            try db.execute(sql: "CREATE INDEX idx_clips_dedup_hash ON clips(payload_hash, type, app);")
        }
        if let target { try migrator.migrate(queue, upTo: target) }
        else { try migrator.migrate(queue) }
    }
}
