import XCTest
@testable import Magpie

@MainActor
final class SnippetRepositoryTests: XCTestCase {

    private var db: Database!
    private var repo: SnippetRepository!

    override func setUp() async throws {
        db = Database.makeInMemoryForTests()
        repo = SnippetRepository(database: db)
    }

    override func tearDown() async throws {
        repo = nil
        db = nil
    }

    private func makeSnippet(
        id: String = UUID().uuidString,
        shortcut: String = ";test",
        title: String = "Test snippet",
        body: String = "Hello world"
    ) -> Snippet {
        let now = Date()
        return Snippet(
            id: id,
            shortcut: shortcut,
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Basic CRUD

    func testEmptyRepoStartsWithZeroCount() throws {
        XCTAssertEqual(try repo.count(), 0)
        XCTAssertTrue(try repo.all().isEmpty)
    }

    func testInsertOneSnippet() throws {
        let s = makeSnippet(shortcut: ";sig", title: "Email signature", body: "— Yu")
        try repo.upsert(s)

        XCTAssertEqual(try repo.count(), 1)
        let all = try repo.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].shortcut, ";sig")
        XCTAssertEqual(all[0].title, "Email signature")
        XCTAssertEqual(all[0].body, "— Yu")
    }

    func testUpsertUpdatesExistingByID() throws {
        let id = UUID().uuidString
        let original = makeSnippet(id: id, shortcut: ";v1", title: "v1", body: "first")
        try repo.upsert(original)

        let updated = makeSnippet(id: id, shortcut: ";v2", title: "v2", body: "second")
        try repo.upsert(updated)

        XCTAssertEqual(try repo.count(), 1, "Same ID should overwrite, not duplicate")
        let all = try repo.all()
        XCTAssertEqual(all[0].shortcut, ";v2")
        XCTAssertEqual(all[0].body, "second")
    }

    func testUpsertBumpsUpdatedAt() throws {
        let id = UUID().uuidString
        let oldDate = Date().addingTimeInterval(-3600)  // 1h ago
        let snippet = Snippet(
            id: id,
            shortcut: ";old",
            title: "Old",
            body: "stale",
            createdAt: oldDate,
            updatedAt: oldDate
        )
        try repo.upsert(snippet)

        let stored = try XCTUnwrap(try repo.all().first)
        XCTAssertGreaterThan(stored.updatedAt, oldDate, "upsert should refresh updatedAt to ~now")
    }

    func testDelete() throws {
        let s1 = makeSnippet(shortcut: ";a")
        let s2 = makeSnippet(shortcut: ";b")
        try repo.upsert(s1)
        try repo.upsert(s2)
        XCTAssertEqual(try repo.count(), 2)

        try repo.delete(id: s1.id)
        XCTAssertEqual(try repo.count(), 1)
        XCTAssertEqual(try repo.all().first?.shortcut, ";b")
    }

    func testDeleteNonexistentIsNoOp() throws {
        try repo.upsert(makeSnippet(shortcut: ";a"))
        try repo.delete(id: "nonexistent-id")
        XCTAssertEqual(try repo.count(), 1, "Deleting unknown ID shouldn't affect existing rows")
    }

    // MARK: - Lookup by shortcut

    func testFindByShortcut() throws {
        try repo.upsert(makeSnippet(shortcut: ";sig", body: "Yu"))
        try repo.upsert(makeSnippet(shortcut: ";meet", body: "Meeting"))

        let sig = try repo.find(shortcut: ";sig")
        XCTAssertNotNil(sig)
        XCTAssertEqual(sig?.body, "Yu")

        let meet = try repo.find(shortcut: ";meet")
        XCTAssertEqual(meet?.body, "Meeting")
    }

    func testFindByShortcutMiss() throws {
        try repo.upsert(makeSnippet(shortcut: ";sig"))
        XCTAssertNil(try repo.find(shortcut: ";nonexistent"))
    }

    func testShortcutConflictReplaces() throws {
        // INSERT OR REPLACE semantics: if a different row has the same shortcut
        // (UNIQUE constraint), SQLite deletes that row and inserts the new one.
        // This documents current behavior — if v1.0 wants to *detect* conflicts
        // and ask the user, switch to plain INSERT and catch the throw.
        try repo.upsert(makeSnippet(id: "id1", shortcut: ";dup", title: "first"))
        try repo.upsert(makeSnippet(id: "id2", shortcut: ";dup", title: "second"))

        XCTAssertEqual(try repo.count(), 1, "REPLACE removes the conflicting row")
        let surviving = try XCTUnwrap(try repo.all().first)
        XCTAssertEqual(surviving.id, "id2")
        XCTAssertEqual(surviving.title, "second")
    }

    // MARK: - Sort order

    func testAllSortsByTitleCaseInsensitive() throws {
        try repo.upsert(makeSnippet(shortcut: ";c", title: "carrot"))
        try repo.upsert(makeSnippet(shortcut: ";b", title: "Banana"))
        try repo.upsert(makeSnippet(shortcut: ";a", title: "apple"))

        let titles = try repo.all().map(\.title)
        XCTAssertEqual(titles, ["apple", "Banana", "carrot"])
    }
}
