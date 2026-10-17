import XCTest
import GRDB
@testable import Magpie

final class ClipRepositorySearchTests: XCTestCase {

    private var db: Database!
    private var repo: ClipRepository!

    override func setUp() async throws {
        db = Database.makeInMemoryForTests()
        repo = ClipRepository(database: db)
    }

    override func tearDown() async throws {
        repo = nil
        db = nil
    }

    func testAppFacetMatchesBundleIdentifierSubstring() throws {
        try insertText(body: "hook implementation", app: "com.microsoft.VSCode")
        try insertText(body: "shell notes", app: "com.apple.Terminal")

        let result = try repo.search(SearchQueryParser.parse("app:vscode"))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.app, "com.microsoft.VSCode")
    }

    func testFreeTextTermDoesNotMatchSourceApp() throws {
        try insertText(body: "shared clipboard body", app: "com.microsoft.VSCode")
        try insertText(body: "shared clipboard body", app: "com.apple.Terminal")

        let result = try repo.search(SearchQueryParser.parse("vscode"))

        XCTAssertTrue(result.isEmpty)
    }

    func testAppFacetCombinesWithFreeTextBodyTerms() throws {
        try insertText(body: "react hook example", app: "com.microsoft.VSCode")
        try insertText(body: "react hook example", app: "com.apple.Terminal")
        try insertText(body: "react state example", app: "com.microsoft.VSCode")

        let result = try repo.search(SearchQueryParser.parse("app:vscode hook"))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.app, "com.microsoft.VSCode")
        XCTAssertEqual(result.first?.title, "react hook example")
    }

    func testAppFacetAllowsSearchingCodexSourceExplicitly() throws {
        try insertText(body: "plain unrelated text", app: "com.openai.chat")
        try insertText(body: "plain unrelated text", app: "ai.codex.desktop")

        let result = try repo.search(SearchQueryParser.parse("app:codex"))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.app, "ai.codex.desktop")
    }

    func testCJKTermsUseSubstringFallbackAndKeepAndSemantics() throws {
        try insertText(
            body: "请以资深 Java/Spring/MyBatis 代码审查视角，review 仓库：/Users/example/iam",
            app: "ai.codex.desktop"
        )
        try insertText(
            body: "review 仓库，但没有另一个中文关键词",
            app: "ai.codex.desktop"
        )

        let result = try repo.search(SearchQueryParser.parse("review 仓库 资深"))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "请以资深 Java/Spring/MyBatis 代码审查视角，review 仓库：/Users/example/iam")
    }

    func testQuotedPhraseSearchUsesSinglePhraseTerm() throws {
        try insertText(body: "say hello world today", app: "com.microsoft.VSCode")
        try insertText(body: "hello there world", app: "com.apple.Terminal")

        let result = try repo.search(SearchQueryParser.parse("\"hello world\""))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "say hello world today")
    }

    func testNewClipsStartWithEmptyNote() throws {
        try insertText(body: "plain clip", app: "abnerworks.Typora")

        let clip = try XCTUnwrap(repo.recent(limit: 1).first)

        XCTAssertEqual(clip.note, "")
    }

    func testUpdateNoteTrimsAndPersistsPinnedClipNote() throws {
        try insertText(body: "pinned api token example", app: "abnerworks.Typora")
        let clip = try XCTUnwrap(repo.recent(limit: 1).first)

        try repo.togglePin(clipId: clip.id)
        try repo.updateNote(clipId: clip.id, note: "  release checklist  ")

        let updated = try XCTUnwrap(repo.recent(limit: 1).first)
        XCTAssertTrue(updated.pinned)
        XCTAssertEqual(updated.note, "release checklist")

        try repo.updateNote(clipId: clip.id, note: "")
        let cleared = try XCTUnwrap(repo.recent(limit: 1).first)
        XCTAssertEqual(cleared.note, "")
    }

    func testFreeTextSearchMatchesClipNote() throws {
        try insertText(body: "ordinary clipboard body", app: "abnerworks.Typora")
        let clip = try XCTUnwrap(repo.recent(limit: 1).first)
        try repo.togglePin(clipId: clip.id)
        try repo.updateNote(clipId: clip.id, note: "客户回访话术")

        let result = try repo.search(SearchQueryParser.parse("回访"))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.note, "客户回访话术")
    }

    private func insertText(body: String, app: String?) throws {
        let payload = try JSONEncoder().encode(TextPayload(body: body))
        let detected = DetectedClip(
            type: .text,
            app: app,
            title: body,
            payload: payload,
            searchText: body
        )
        try repo.insert(detected)
    }
}

final class RepositoryPerformanceTests: XCTestCase {
    func testLargeHistoriesRemainBoundedAndSearchable() throws {
        // Synthetic fixtures only. Times include GRDB/decoding for repository
        // operations; they are diagnostic measurements, not timing assertions.
        for count in [1_000, 10_000, 50_000] {
            let db = Database.makeInMemoryForTests()
            try db.dbQueue.write { connection in
                for i in 0..<count {
                    let body = "entry \(i) " + (i % 97 == 0 ? "needle 客户回访记录" : "ordinary 常规记录")
                    let payload = try JSONEncoder().encode(TextPayload(body: body))
                    try connection.execute(sql: "INSERT INTO clips(id,type,app,created_at,title,payload,payload_hash) VALUES(?,'text','com.example.Editor',?,?,?,?)",
                        arguments: ["\(i)", Double(i), body, payload, ClipRepository.payloadHash(payload)])
                    try connection.execute(sql: "INSERT INTO clips_fts(clip_id,title,body,tags) VALUES(?,?,?,'')",
                        arguments: ["\(i)", body, body])
                    try connection.execute(sql: "UPDATE clips SET fts_rowid=? WHERE id=?", arguments: [connection.lastInsertedRowID, "\(i)"])
                }
            }
            let repository = ClipRepository(database: db)
            for query in ["", "needle", "回访"] {
                let started = ProcessInfo.processInfo.systemUptime
                let rows = try repository.search(SearchQueryParser.parse(query))
                let ms = (ProcessInfo.processInfo.systemUptime - started) * 1000
                XCTAssertLessThanOrEqual(rows.count, 200)
                XCTAssertFalse(rows.isEmpty)
                print("BENCH history=\(count) queryKind=\(query.isEmpty ? "recent" : query == "needle" ? "ascii" : "cjk") elapsedMS=\(ms)")
            }
            XCTAssertEqual(try repository.count(), count)
        }
    }

    func testHashDedupPreservesPinNoteAndAppIdentity() throws {
        let db = Database.makeInMemoryForTests(), body = "duplicate payload"
        let repository = ClipRepository(database: db)
        let clip = try XCTUnwrap(ClipDetector.detectFromString(body, app: "app.one"))
        try repository.insert(clip)
        let id = try XCTUnwrap(repository.recent().first?.id)
        try repository.togglePin(clipId: id)
        try repository.updateNote(clipId: id, note: "preserved")
        try repository.insert(clip)
        XCTAssertEqual(try repository.count(), 1)
        let record = try XCTUnwrap(repository.recent().first)
        XCTAssertTrue(record.pinned); XCTAssertEqual(record.note, "preserved")
        try repository.insert(XCTUnwrap(ClipDetector.detectFromString(body, app: "app.two")))
        XCTAssertEqual(try repository.count(), 2)
        XCTAssertEqual(try repository.search(SearchQueryParser.parse("duplicate")).count, 2)
        XCTAssertTrue(try repository.search(SearchQueryParser.parse("duplicate"), limit: -1).isEmpty)
    }
}
