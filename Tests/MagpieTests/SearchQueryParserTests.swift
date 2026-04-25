import XCTest
@testable import Magpie

final class SearchQueryParserTests: XCTestCase {

    func testEmptyInputProducesEmptyQuery() {
        let q = SearchQueryParser.parse("")
        XCTAssertTrue(q.isEmpty)
    }

    func testWhitespaceOnlyIsEmpty() {
        let q = SearchQueryParser.parse("   \t  ")
        XCTAssertTrue(q.isEmpty)
    }

    // MARK: - Free terms

    func testSingleFreeTerm() {
        let q = SearchQueryParser.parse("react")
        XCTAssertEqual(q.terms, ["react"])
        XCTAssertTrue(q.typeFilters.isEmpty)
    }

    func testMultipleFreeTermsAreAnded() {
        let q = SearchQueryParser.parse("react hook useState")
        XCTAssertEqual(q.terms, ["react", "hook", "useState"])
    }

    // MARK: - type:

    func testTypeFacet() {
        let q = SearchQueryParser.parse("type:code")
        XCTAssertEqual(q.typeFilters, [.code])
        XCTAssertTrue(q.terms.isEmpty)
    }

    func testTypeFacetCaseInsensitive() {
        let q = SearchQueryParser.parse("TYPE:CODE")
        XCTAssertEqual(q.typeFilters, [.code])
    }

    func testTypeFacetPlusFreeTerms() {
        let q = SearchQueryParser.parse("type:code react hook")
        XCTAssertEqual(q.typeFilters, [.code])
        XCTAssertEqual(q.terms, ["react", "hook"])
    }

    func testUnknownTypeIsDropped() {
        let q = SearchQueryParser.parse("type:bogus react")
        XCTAssertTrue(q.typeFilters.isEmpty)
        XCTAssertEqual(q.terms, ["react"])
    }

    // MARK: - app:

    func testAppFacet() {
        let q = SearchQueryParser.parse("app:vscode")
        XCTAssertEqual(q.apps, ["vscode"])
    }

    func testAppFacetPreservesCase() {
        let q = SearchQueryParser.parse("app:com.apple.dt.Xcode")
        XCTAssertEqual(q.apps, ["com.apple.dt.Xcode"])
    }

    func testMultipleAppFacets() {
        let q = SearchQueryParser.parse("app:vscode app:terminal")
        XCTAssertEqual(q.apps, ["vscode", "terminal"])
    }

    // MARK: - tag:

    func testTagFacet() {
        let q = SearchQueryParser.parse("tag:design")
        XCTAssertEqual(q.tags, ["design"])
    }

    func testMultipleTags() {
        let q = SearchQueryParser.parse("tag:design tag:react")
        XCTAssertEqual(q.tags, ["design", "react"])
    }

    // MARK: - Combinations

    func testFullCombination() {
        let q = SearchQueryParser.parse("type:code app:vscode tag:react useState hook")
        XCTAssertEqual(q.typeFilters, [.code])
        XCTAssertEqual(q.apps, ["vscode"])
        XCTAssertEqual(q.tags, ["react"])
        XCTAssertEqual(q.terms, ["useState", "hook"])
    }

    func testPinnedOnlyFlag() {
        let q = SearchQueryParser.parse("react", pinnedOnly: true)
        XCTAssertEqual(q.terms, ["react"])
        XCTAssertTrue(q.pinnedOnly)
    }

    // MARK: - Edge cases

    func testColonWithoutValueIsIgnored() {
        let q = SearchQueryParser.parse("type: react")
        XCTAssertTrue(q.typeFilters.isEmpty)
        XCTAssertEqual(q.terms, ["react"])
    }

    func testUnknownFacetBecomesFreeTerm() {
        let q = SearchQueryParser.parse("color:red sky")
        XCTAssertEqual(q.terms, ["color:red", "sky"])
        XCTAssertTrue(q.typeFilters.isEmpty)
        XCTAssertTrue(q.apps.isEmpty)
    }

    // MARK: - isEmpty

    func testEmptyVsNonEmpty() {
        XCTAssertTrue(SearchQuery.empty.isEmpty)
        XCTAssertFalse(SearchQueryParser.parse("a").isEmpty)
        XCTAssertFalse(SearchQueryParser.parse("type:code").isEmpty)
        XCTAssertFalse(SearchQueryParser.parse("", pinnedOnly: true).isEmpty)
    }
}
