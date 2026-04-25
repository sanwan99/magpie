import XCTest
@testable import Magpie

final class ClipDetectorTests: XCTestCase {

    // MARK: - URL detection

    func testHTTPSURLIsDetected() {
        let d = ClipDetector.detectFromString("https://example.com/path?q=1", app: nil)
        XCTAssertEqual(d?.type, .url)
    }

    func testHTTPURLIsDetected() {
        let d = ClipDetector.detectFromString("http://example.com", app: nil)
        XCTAssertEqual(d?.type, .url)
    }

    func testURLWithSurroundingWhitespaceIsDetected() {
        let d = ClipDetector.detectFromString("   https://example.com/x   \n", app: nil)
        XCTAssertEqual(d?.type, .url)
    }

    func testNonHTTPSchemeIsNotURL() {
        let d = ClipDetector.detectFromString("ftp://example.com", app: nil)
        XCTAssertEqual(d?.type, .text)
    }

    func testStringContainingURLAmidstTextIsNotURL() {
        let d = ClipDetector.detectFromString("see https://example.com for more", app: nil)
        XCTAssertEqual(d?.type, .text)
    }

    // MARK: - Code detection

    func testSwiftFunctionIsCode() {
        let snippet = """
        func greet(name: String) -> String {
            return "hello, \\(name)"
        }
        """
        let d = ClipDetector.detectFromString(snippet, app: nil)
        XCTAssertEqual(d?.type, .code)
    }

    func testPythonDefIsCode() {
        let snippet = """
        def add(a, b):
            return a + b
        """
        let d = ClipDetector.detectFromString(snippet, app: nil)
        XCTAssertEqual(d?.type, .code)
    }

    func testJavaScriptArrowIsCode() {
        let snippet = """
        const add = (a, b) => {
            return a + b
        }
        """
        let d = ClipDetector.detectFromString(snippet, app: nil)
        XCTAssertEqual(d?.type, .code)
    }

    func testHTMLDocTypeIsCode() {
        let snippet = "<!DOCTYPE html>\n<html><body>Hi</body></html>"
        let d = ClipDetector.detectFromString(snippet, app: nil)
        XCTAssertEqual(d?.type, .code)
    }

    func testSingleLineWithBracesIsNotCode() {
        // Single line — even with braces — is more likely a token than a code snippet.
        let d = ClipDetector.detectFromString("{key: value}", app: nil)
        XCTAssertEqual(d?.type, .text)
    }

    // MARK: - Text fallback

    func testShortPhraseIsText() {
        let d = ClipDetector.detectFromString("hello world", app: nil)
        XCTAssertEqual(d?.type, .text)
    }

    func testParagraphIsText() {
        let s = """
        This is a multi-line paragraph that contains no code keywords.
        Just two ordinary sentences here.
        """
        let d = ClipDetector.detectFromString(s, app: nil)
        XCTAssertEqual(d?.type, .text)
    }

    func testChineseTextIsDetected() {
        let d = ClipDetector.detectFromString("粘贴板中文内容测试", app: nil)
        XCTAssertEqual(d?.type, .text)
        XCTAssertEqual(d?.title, "粘贴板中文内容测试")
    }

    // MARK: - Edge cases

    func testEmptyStringReturnsNil() {
        XCTAssertNil(ClipDetector.detectFromString("", app: nil))
    }

    func testWhitespaceOnlyReturnsNil() {
        XCTAssertNil(ClipDetector.detectFromString("   \n\t  ", app: nil))
    }

    // MARK: - App attribution

    func testAppBundleIdIsCarriedThrough() {
        let d = ClipDetector.detectFromString("hello", app: "com.apple.dt.Xcode")
        XCTAssertEqual(d?.app, "com.apple.dt.Xcode")
    }

    // MARK: - Title generation

    func testTitleIsFirstLineTrimmedAndCapped() {
        let body = "first line\nsecond line\nthird line"
        let d = ClipDetector.detectFromString(body, app: nil)
        XCTAssertEqual(d?.title, "first line")
    }

    // MARK: - Payload encoding

    func testTextPayloadCarriesBody() throws {
        let d = try XCTUnwrap(ClipDetector.detectFromString("hello world", app: nil))
        let payload = try JSONDecoder().decode(TextPayload.self, from: d.payload)
        XCTAssertEqual(payload.body, "hello world")
    }

    func testURLPayloadCarriesHost() throws {
        let d = try XCTUnwrap(ClipDetector.detectFromString("https://example.com/x", app: nil))
        let payload = try JSONDecoder().decode(URLPayload.self, from: d.payload)
        XCTAssertEqual(payload.url, "https://example.com/x")
        XCTAssertEqual(payload.host, "example.com")
    }
}
