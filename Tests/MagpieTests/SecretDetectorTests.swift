import XCTest
@testable import Magpie

final class SecretDetectorTests: XCTestCase {

    // MARK: - Positive matches (should be detected as secret)

    func testApiKeyAssignmentEquals() {
        XCTAssertTrue(SecretDetector.looksSecret("api_key=abc123def456"))
    }

    func testApiKeyAssignmentColon() {
        XCTAssertTrue(SecretDetector.looksSecret("api_key: sk-1234567890abcdef"))
    }

    func testApiKeyDashedSpelling() {
        XCTAssertTrue(SecretDetector.looksSecret("api-key=xyz789"))
    }

    func testAccessKeyAssignment() {
        XCTAssertTrue(SecretDetector.looksSecret("access_key=ABCD1234"))
    }

    func testSecretKeyAssignment() {
        XCTAssertTrue(SecretDetector.looksSecret("secret_key=hunter2"))
    }

    func testTokenAssignment() {
        XCTAssertTrue(SecretDetector.looksSecret("token=xoxb-12345"))
    }

    func testPasswordAssignment() {
        XCTAssertTrue(SecretDetector.looksSecret("password = ChangeMe42!"))
    }

    func testBearerToken() {
        XCTAssertTrue(SecretDetector.looksSecret("bearer eyJhbGc.payload.signature"))
    }

    func testAuthorizationBearer() {
        XCTAssertTrue(SecretDetector.looksSecret("Authorization: Bearer abc123"))
    }

    func testJWT() {
        XCTAssertTrue(SecretDetector.looksSecret("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"))
    }

    func testGitHubClassicToken() {
        XCTAssertTrue(SecretDetector.looksSecret("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef"))
    }

    func testGitHubFineGrainedPAT() {
        XCTAssertTrue(SecretDetector.looksSecret("github_pat_ABCDEFGHIJKLMNOPQRSTUV_abcdefghijklmnopqrstuvwxyz0123456789ABCDEF"))
    }

    func testAWSAccessKey() {
        XCTAssertTrue(SecretDetector.looksSecret("AKIAIOSFODNN7EXAMPLE"))
    }

    func testOTP() {
        XCTAssertTrue(SecretDetector.looksSecret("Your verification code is 123456"))
    }

    func testOTPLowercase() {
        XCTAssertTrue(SecretDetector.looksSecret("otp 654321"))
    }

    // MARK: - Embedded in larger text

    func testEmbeddedInLogLine() {
        let line = "[2026-04-26 10:00:00] DEBUG api_key=mysecretvalue request id=42"
        XCTAssertTrue(SecretDetector.looksSecret(line))
    }

    func testEmbeddedInJSON() {
        let json = #"{"name": "alice", "api_key": "abcd-1234"}"#
        // The colon-form regex requires `api_key:` shape — JSON has it (key:value).
        XCTAssertTrue(SecretDetector.looksSecret(json))
    }

    // MARK: - Negative matches (should NOT be detected as secret)

    func testPlainSentence() {
        XCTAssertFalse(SecretDetector.looksSecret("Remember to bring your password manager tomorrow."))
    }

    func testWordContainingTokenAsSubstring() {
        // "tokens" alone shouldn't match — needs the `:= …` shape.
        XCTAssertFalse(SecretDetector.looksSecret("Two tokens of appreciation"))
    }

    func testCodeWithoutCredentials() {
        let code = """
        func add(a: Int, b: Int) -> Int {
            return a + b
        }
        """
        XCTAssertFalse(SecretDetector.looksSecret(code))
    }

    func testMarkdownLink() {
        let md = "[GitHub](https://github.com/sanwan99/magpie)"
        XCTAssertFalse(SecretDetector.looksSecret(md))
    }

    func testEmailNotASecret() {
        XCTAssertFalse(SecretDetector.looksSecret("contact: alice@example.com"))
    }

    func testShortAlphanumericNotJWT() {
        // "eyJ" prefix alone isn't enough — JWT regex requires three base64 segments.
        XCTAssertFalse(SecretDetector.looksSecret("eyJ.short"))
    }

    func testNonAKIAUppercaseString() {
        // 16 uppercase chars but not starting with AKIA — shouldn't match.
        XCTAssertFalse(SecretDetector.looksSecret("XYZAIOSFODNN7EXAMPLE"))
    }

    func testSixDigitsWithoutContext() {
        // 6 digits alone (no "code"/"otp" wording nearby) shouldn't match.
        XCTAssertFalse(SecretDetector.looksSecret("Order #123456 shipped"))
    }

    // MARK: - Empty / whitespace

    func testEmptyString() {
        XCTAssertFalse(SecretDetector.looksSecret(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(SecretDetector.looksSecret("   \n\t  "))
    }
}
