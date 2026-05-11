import XCTest
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
