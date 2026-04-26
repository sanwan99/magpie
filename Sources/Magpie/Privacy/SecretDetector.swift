import Foundation

/// Heuristic detector for credential-shaped strings.
/// Used to skip ingestion of clips that look like API keys / tokens / passwords / OTPs.
///
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
            #"(?i)\bbearer\s+[A-Za-z0-9_\-\.=]{8,}"#,
            // Authorization header: Bearer …
            #"(?i)\b(authorization|auth)\s*:\s*bearer\s+\S+"#,
            // Standalone JWT (3 base64 segments separated by dots).
            #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
            // GitHub fine-grained / classic tokens.
            #"\bghp_[A-Za-z0-9]{30,}\b"#,
            #"\bgithub_pat_[A-Za-z0-9_]{60,}\b"#,
            // AWS access keys.
            #"\bAKIA[0-9A-Z]{16}\b"#,
            // 6-digit OTP next to "code" / "otp" wording.
            #"(?i)\b(otp|verification\s*code|one[-\s]?time)\b[^\d]{0,8}\d{6}\b"#,
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
