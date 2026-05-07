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
        }
        return id
    }

    private func clipCount(pinnedOnly: Bool? = nil) throws -> Int {
        try db.dbQueue.read { dbConn in
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
            HistoryReaper(database: db).reapNow()
        }

        XCTAssertEqual(try clipCount(), 2, "keepHistoryDays=0 means forever — nothing deleted")
    }

    func testKeepDaysDeletesOldUnpinned() throws {
        let now = Date()
        try insertClip(createdAt: now.addingTimeInterval(-40 * 86_400), pinned: false)  // 40 days old
        try insertClip(createdAt: now.addingTimeInterval(-20 * 86_400), pinned: false)  // 20 days old
        try insertClip(createdAt: now,                                  pinned: false)  // fresh

        try withSettings(keepHistoryDays: 30) {
            HistoryReaper(database: db).reapNow()
        }

        // 40-day-old should be gone; 20-day and fresh should remain.
        XCTAssertEqual(try clipCount(), 2)
    }

    func testKeepDaysDoesNotDeletePinned() throws {
        let oldDate = Date().addingTimeInterval(-100 * 86_400)
        try insertClip(createdAt: oldDate, pinned: true)
        try insertClip(createdAt: oldDate, pinned: false)

        try withSettings(keepHistoryDays: 7) {
            HistoryReaper(database: db).reapNow()
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
            HistoryReaper(database: db).reapNow()
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
            HistoryReaper(database: db).reapNow()
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
            HistoryReaper(database: db).reapNow()
        }

        XCTAssertEqual(try clipCount(pinnedOnly: true), 2, "Both pinned survive")
        XCTAssertEqual(try clipCount(pinnedOnly: false), 2, "Only 2 newest unpinned survive")
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
