import XCTest
import GRDB
@testable import Magpie

@MainActor
final class HistoryReaperTests: XCTestCase {

    private var db: Magpie.Database!
    private var imageDirectoryURL: URL!

    override func setUp() async throws {
        db = Magpie.Database.makeInMemoryForTests()
        imageDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-history-reaper-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let imageDirectoryURL {
            try? FileManager.default.removeItem(at: imageDirectoryURL)
        }
        imageDirectoryURL = nil
        db = nil
    }

    // MARK: - Helpers

    /// Insert a clip directly via SQL with a chosen created_at (epoch seconds)
    /// and pinned flag. Bypasses ClipRepository so we can stage retention scenarios.
    @discardableResult
    private func insertClip(
        id: String = UUID().uuidString,
        type: String = "text",
        createdAt: Date,
        pinned: Bool
    ) throws -> String {
        let payload = #"{"body":"test"}"#.data(using: .utf8)!
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO clips (id, type, app, created_at, pinned, tags, title, payload)
                VALUES (?, ?, NULL, ?, ?, '[]', NULL, ?);
            """, arguments: [id, type, createdAt.timeIntervalSince1970, pinned ? 1 : 0, payload])
            try dbConn.execute(sql: "INSERT INTO clips_fts(clip_id,title,body,tags) VALUES(?,'retention','synthetic searchable text','')", arguments: [id])
            try dbConn.execute(sql: "UPDATE clips SET fts_rowid = ? WHERE id = ?", arguments: [dbConn.lastInsertedRowID, id])
        }
        return id
    }

    private func clipCount(pinnedOnly: Bool? = nil) throws -> Int {
        try db.dbQueue.read { dbConn in
            let rows = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM clips")
            let indexed = try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM clips_fts")
            XCTAssertEqual(rows, indexed, "Retention must remove the searchable copy transactionally")
            switch pinnedOnly {
            case .some(true):
                return try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM clips WHERE pinned = 1") ?? 0
            case .some(false):
                return try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM clips WHERE pinned = 0") ?? 0
            case .none:
                return try Int.fetchOne(dbConn, sql: "SELECT COUNT(*) FROM clips") ?? 0
            }
        }
    }

    @discardableResult
    private func insertImageClip(
        id: String,
        path: String,
        createdAt: Date = Date(),
        pinned: Bool = false
    ) throws -> String {
        let payload = try JSONEncoder().encode(ImagePayload(
            path: path,
            width: 10,
            height: 10,
            sizeKB: 1
        ))
        try db.dbQueue.write { dbConn in
            try dbConn.execute(sql: """
                INSERT INTO clips (id, type, app, created_at, pinned, tags, title, payload)
                VALUES (?, 'image', NULL, ?, ?, '[]', 'image', ?);
            """, arguments: [id, createdAt.timeIntervalSince1970, pinned ? 1 : 0, payload])
            try dbConn.execute(sql: """
                INSERT INTO clips_fts (clip_id, title, body, tags)
                VALUES (?, 'image', 'image 10x10 1KB', '');
            """, arguments: [id])
        }
        return id
    }

    private func ftsCount(clipID: String) throws -> Int {
        try db.dbQueue.read { dbConn in
            try Int.fetchOne(
                dbConn,
                sql: "SELECT COUNT(*) FROM clips_fts WHERE clip_id = ?",
                arguments: [clipID]
            ) ?? 0
        }
    }

    /// Build a fresh SettingsStore-like config in a struct since SettingsStore.shared
    /// is a singleton and we don't want to mutate global state from tests.
    /// HistoryReaper takes a SettingsStore directly — we use the real one but
    /// snapshot/restore the values we touch.
    private func withSettings(
        keepHistoryDays: Int = 0,
        maxItems: Int = 0,
        body: () throws -> Void
    ) rethrows {
        let store = SettingsStore.shared
        let prevDays = store.keepHistoryDays
        let prevMax = store.maxItems
        store.keepHistoryDays = keepHistoryDays
        store.maxItems = maxItems
        defer {
            store.keepHistoryDays = prevDays
            store.maxItems = prevMax
        }
        try body()
    }

    // MARK: - keepHistoryDays

    func testKeepForeverDoesntDelete() throws {
        try insertClip(createdAt: Date().addingTimeInterval(-365 * 86_400), pinned: false)
        try insertClip(createdAt: Date(), pinned: false)

        try withSettings(keepHistoryDays: 0) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }

        XCTAssertEqual(try clipCount(), 2, "keepHistoryDays=0 means forever — nothing deleted")
    }

    func testKeepDaysDeletesOldUnpinned() throws {
        let now = Date()
        try insertClip(createdAt: now.addingTimeInterval(-40 * 86_400), pinned: false)  // 40 days old
        try insertClip(createdAt: now.addingTimeInterval(-20 * 86_400), pinned: false)  // 20 days old
        try insertClip(createdAt: now,                                  pinned: false)  // fresh

        try withSettings(keepHistoryDays: 30) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }

        // 40-day-old should be gone; 20-day and fresh should remain.
        XCTAssertEqual(try clipCount(), 2)
    }

    func testKeepDaysDoesNotDeletePinned() throws {
        let oldDate = Date().addingTimeInterval(-100 * 86_400)
        try insertClip(createdAt: oldDate, pinned: true)
        try insertClip(createdAt: oldDate, pinned: false)

        try withSettings(keepHistoryDays: 7) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }

        XCTAssertEqual(try clipCount(pinnedOnly: true), 1, "Pinned clip survives")
        XCTAssertEqual(try clipCount(pinnedOnly: false), 0, "Unpinned old clip is reaped")
    }

    // MARK: - maxItems

    func testMaxItemsZeroIsUnlimited() throws {
        for _ in 0..<10 {
            try insertClip(createdAt: Date(), pinned: false)
        }
        try withSettings(maxItems: 0) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }
        XCTAssertEqual(try clipCount(), 10)
    }

    func testMaxItemsKeepsNewest() throws {
        let now = Date()
        // Insert 5 clips with strictly increasing timestamps.
        for i in 0..<5 {
            try insertClip(
                id: "clip\(i)",
                createdAt: now.addingTimeInterval(Double(i)),
                pinned: false
            )
        }

        try withSettings(maxItems: 3) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }

        // Should keep the 3 newest (clip2/3/4).
        XCTAssertEqual(try clipCount(), 3)
        let surviving = try db.dbQueue.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT id FROM clips ORDER BY created_at DESC")
        }
        XCTAssertEqual(surviving, ["clip4", "clip3", "clip2"])
    }

    func testMaxItemsDoesNotCountPinnedAgainstLimit() throws {
        let now = Date()
        try insertClip(id: "p1", createdAt: now.addingTimeInterval(-100), pinned: true)
        try insertClip(id: "p2", createdAt: now.addingTimeInterval(-99), pinned: true)
        for i in 0..<5 {
            try insertClip(
                id: "u\(i)",
                createdAt: now.addingTimeInterval(Double(i)),
                pinned: false
            )
        }

        // Allow only 2 unpinned. Pins always preserved.
        try withSettings(maxItems: 2) {
            HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()
        }

        XCTAssertEqual(try clipCount(pinnedOnly: true), 2, "Both pinned survive")
        XCTAssertEqual(try clipCount(pinnedOnly: false), 2, "Only 2 newest unpinned survive")
    }

    // MARK: - stale image cache rows

    func testMissingImageCacheRowsAreRemovedWithFTS() throws {
        let existingImage = imageDirectoryURL.appendingPathComponent("existing.png")
        let missingImage = imageDirectoryURL.appendingPathComponent("missing.png")
        try Data("not a real png, but it exists".utf8).write(to: existingImage)

        try insertImageClip(id: "existing", path: existingImage.path)
        try insertImageClip(id: "missing", path: missingImage.path)

        HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL).reapNow()

        let surviving = try db.dbQueue.read { dbConn in
            try String.fetchAll(dbConn, sql: "SELECT id FROM clips ORDER BY id")
        }
        XCTAssertEqual(surviving, ["existing"])
        XCTAssertEqual(try ftsCount(clipID: "existing"), 1)
        XCTAssertEqual(try ftsCount(clipID: "missing"), 0)
    }

    // MARK: - clearAll

    func testClearAllRemovesEverything() throws {
        for _ in 0..<5 { try insertClip(createdAt: Date(), pinned: false) }
        try insertClip(createdAt: Date(), pinned: true)
        let cachedImage = imageDirectoryURL.appendingPathComponent("cached.png")
        try Data("png".utf8).write(to: cachedImage)

        let reaper = HistoryReaper(database: db, imageDirectoryURL: imageDirectoryURL)
        reaper.clearAll()

        XCTAssertEqual(try clipCount(), 0, "clearAll deletes pinned + unpinned")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedImage.path))
    }
}

final class StorageMigrationTests: XCTestCase {
    func testLegacyUpgradePreservesDataRepairsFTSAndIsRepeatable() throws {
        let queue = try DatabaseQueue()
        try Magpie.Database.migrate(queue, upTo: "v3_clip_notes")
        try queue.write { db in
            let payload = try JSONEncoder().encode(TextPayload(body: "legacy searchable body"))
            for id in ["indexed", "missing-index"] {
                try db.execute(sql: "INSERT INTO clips(id,type,created_at,pinned,tags,title,payload,note) VALUES(?,'text',1,1,'[\"tag\"]','title',?,'kept note')", arguments: [id, payload])
            }
            try db.execute(sql: "INSERT INTO clips_fts(clip_id,title,body,tags) VALUES('indexed','title','legacy searchable body','tag'),('orphan','old','deleted secret','')")
            try db.execute(sql: "INSERT INTO snippets(id,shortcut,title,body,created_at,updated_at) VALUES('s',';s','kept','template',1,1)")
        }
        let db = try Magpie.Database(dbQueue: queue)
        try Magpie.Database.migrate(queue)
        XCTAssertEqual(try ClipRepository(database: db).count(), 2)
        let records = try ClipRepository(database: db).search(SearchQueryParser.parse("legacy"))
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.pinned && $0.note == "kept note" && $0.tags == "[\"tag\"]" })
        try queue.write { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips_fts WHERE clips_fts MATCH 'secret'"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM snippets"), 1)
            try db.execute(sql: "DELETE FROM clips WHERE id = 'indexed'")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips_fts"), 1)
            try db.execute(sql: "DELETE FROM clips")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips_fts"), 0)
        }
    }

    func testFailedTransactionKeepsClipAndIndex() throws {
        let db = Magpie.Database.makeInMemoryForTests()
        try ClipRepository(database: db).insert(XCTUnwrap(ClipDetector.detectFromString("rollback", app: nil)))
        enum Expected: Error { case rollback }
        XCTAssertThrowsError(try db.dbQueue.write { connection in
            try connection.execute(sql: "DELETE FROM clips")
            throw Expected.rollback
        })
        XCTAssertEqual(try ClipRepository(database: db).count(), 1)
        XCTAssertEqual(try ClipRepository(database: db).search(SearchQueryParser.parse("rollback")).count, 1)
    }

    func testImageCleanupRejectsOutsideFilesSymlinksAndDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let managed = root.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.png")
        try Data([1]).write(to: outside)
        let link = managed.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let directory = managed.appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let owned = managed.appendingPathComponent("owned.png")
        try Data([2]).write(to: owned)
        XCTAssertFalse(ImageStorage.removeManagedFile(at: outside.path, in: managed))
        XCTAssertFalse(ImageStorage.removeManagedFile(at: link.path, in: managed))
        XCTAssertFalse(ImageStorage.removeManagedFile(at: directory.path, in: managed))
        try ImageStorage.removeOrphans(keeping: [], in: managed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    }
}
