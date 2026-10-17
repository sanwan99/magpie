import Foundation

/// Heuristic detector for credential-shaped strings.
/// Used to skip ingestion of clips that look like API keys / tokens / passwords / OTPs.
///
/// This is best-effort only: unmarked passwords, images and unknown token
/// formats can evade detection. False positives are also possible.
/// Spec §09 calls this "Skip secret-looking content". We err on the side of
/// matching false-positives — losing a real-but-secret-looking note is fine
/// (user can re-copy), but ingesting a real API key is bad.
enum SecretDetector {
    /// Patterns that strongly suggest credential material in the body.
    /// All matched case-insensitively, anchored at word boundaries on the key side.
    private static let regexes: [NSRegularExpression] = {
        let patterns: [String] = [
            // key=value / key:value style. Allow non-word chars (e.g. JSON's
            // closing quote `"api_key":`) between keyword and the colon/equals.
            #"(?i)\b(api[_-]?key|access[_-]?key|secret[_-]?key|secret|token|password|passwd|pwd|otp|2fa|mfa)\b\W*[:=]\s*\S+"#,
            // Standalone "bearer <token>" — space-separated, not key=value.
            #"(?i)\bbearer[ \t]+[A-Za-z0-9_~+/.=-]{8,}"#,
            // Authorization header: Bearer …
            #"(?i)\b(authorization|auth)\s*:\s*bearer\s+\S+"#,
            // Standalone JWT (3 base64 segments separated by dots).
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            // GitHub fine-grained / classic tokens.
            #"\bghp_[A-Za-z0-9]{30,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{60,}\b"#,
            // Common prefixed API keys, including project/service-account keys.
            #"\bsk-(?:proj-|svcacct-|ant-api\d+-)?[A-Za-z0-9_-]{20,}"#,
            #"\b(?:gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b"#,
            #"\bxox[baprs]-[A-Za-z0-9-]{20,}\b"#,
            #"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"#,
            // AWS access keys, including temporary credentials.
            #"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#,
            #"(?:验证码|校验码|动态码|一次性密码|驗證碼)[^0-9\r\n]{0,12}[0-9]{4,8}(?![0-9])"#,
            // Contextual OTP next to "code" / "otp" wording.
            #"(?i)\b(otp|verification\s*code|one[-\s]?time)\b[^\d\r\n]{0,12}\d{4,8}\b"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// True if `text` looks like it contains credential material.
    static func looksSecret(_ text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        for re in regexes {
            if re.firstMatch(in: text, range: range) != nil {
                return true
            }
        }
        return false
    }
}

/// Only fixed event names and numeric error categories may reach diagnostics.
/// NSError descriptions / userInfo and GRDB descriptions can contain content.
enum DiagnosticLog {
    static func failure(_ event: StaticString, error: Error) {
        NSLog("[%@] failed code=%ld", String(describing: event), (error as NSError).code)
    }
}
