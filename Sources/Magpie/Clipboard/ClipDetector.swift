import AppKit
import Foundation

/// Heuristic dispatcher: NSPasteboard → DetectedClip.
///
/// v0.1 priority order:
///   1. NSURL items (file paths) → folder vs file based on `isDirectory`
///   2. plain string → URL (http/https) > code (heuristic) > text (default)
///
/// v0.3 will add image (NSImage / public.tiff / public.png) and richer file metadata.
enum ClipDetector {
    /// Public entry point — inspects pasteboard and produces a clip if anything is recognized.
    static func detect(pasteboard: NSPasteboard, app: String?) -> DetectedClip? {
        // 1. Real file URL items — Finder ⌘C, drag-and-drop set `.fileURL` explicitly.
        //    pbcopy / NSString string copies do *not* set this type, so plain text
        //    (including paths typed as strings) falls through to step 2 instead of
        //    being mis-parsed as a fake URL by `readObjects(forClasses:[NSURL.self])`.
        let hasFileURL = pasteboard.types?.contains(.fileURL) ?? false
        if hasFileURL,
           let nsurls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = nsurls.first,
           first.isFileURL {
            return detectFromFileURL(first, app: app)
        }

        // 2. String content
        guard let raw = pasteboard.string(forType: .string), !raw.isEmpty else {
            return nil
        }
        return detectFromString(raw, app: app)
    }

    /// Pure string-based detection — extracted so unit tests don't need a real pasteboard.
    static func detectFromString(_ raw: String, app: String?) -> DetectedClip? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = parseHTTPURL(trimmed) {
            return makeURL(url: url, app: app)
        }
        if looksLikeCode(raw) {
            return makeCode(body: raw, app: app)
        }
        return makeText(body: raw, app: app)
    }

    // MARK: - File URL detection

    private static func detectFromFileURL(_ url: URL, app: String?) -> DetectedClip {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard exists else {
            // Non-existent path — fall back to text capture of the path string.
            return makeText(body: url.absoluteString, app: app)
        }
        if isDir.boolValue {
            let items = countShallowItems(at: url)
            return makeFolder(url: url, items: items, app: app)
        } else {
            let sizeKB = fileSizeKB(at: url)
            let kind = url.pathExtension.lowercased()
            return makeFile(url: url, kind: kind.isEmpty ? "file" : kind, sizeKB: sizeKB, app: app)
        }
    }

    private static func countShallowItems(at url: URL) -> Int {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        return contents?.count ?? 0
    }

    private static func fileSizeKB(at url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attrs?[.size] as? NSNumber else { return 0 }
        return max(0, Int(bytes.doubleValue / 1024.0))
    }

    // MARK: - URL heuristics

    /// Returns a parsed URL if the string is plausibly an http(s) URL on its own.
    /// Rejects strings that contain whitespace inside (likely a sentence with a URL).
    static func parseHTTPURL(_ s: String) -> URL? {
        guard !s.contains(" "), !s.contains("\n"), !s.contains("\t") else { return nil }
        guard let url = URL(string: s) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard url.host != nil else { return nil }
        return url
    }

    // MARK: - Code heuristics

    /// Multi-line + code keywords or balanced braces = treated as code.
    /// Tunable in v0.2 once we have real false-positive samples.
    static func looksLikeCode(_ s: String) -> Bool {
        guard s.contains("\n") else { return false }
        if s.contains("{") && s.contains("}") { return true }
        let keywords: [String] = [
            "function ", "func ", "def ", "class ", "import ", "package ",
            "const ", "let ", "var ", "public ", "private ",
            "<?php", "<!DOCTYPE", "#include ", "using namespace ",
            "return ", "=>", "->",
        ]
        for kw in keywords where s.contains(kw) { return true }
        return false
    }

    // MARK: - Factories

    private static func makeText(body: String, app: String?) -> DetectedClip {
        let payload = TextPayload(body: body)
        return DetectedClip(
            type: .text,
            app: app,
            title: title(forText: body),
            payload: encode(payload),
            searchText: body
        )
    }

    private static func makeCode(body: String, app: String?) -> DetectedClip {
        let lang = guessLang(body)
        let payload = CodePayload(body: body, lang: lang)
        return DetectedClip(
            type: .code,
            app: app,
            title: title(forText: body),
            payload: encode(payload),
            searchText: body
        )
    }

    private static func makeURL(url: URL, app: String?) -> DetectedClip {
        let payload = URLPayload(url: url.absoluteString, host: url.host, title: nil, desc: nil)
        return DetectedClip(
            type: .url,
            app: app,
            title: url.host,
            payload: encode(payload),
            searchText: [url.absoluteString, url.host ?? ""].joined(separator: " ")
        )
    }

    private static func makeFolder(url: URL, items: Int, app: String?) -> DetectedClip {
        let payload = FolderPayload(path: url.path, items: items)
        return DetectedClip(
            type: .folder,
            app: app,
            title: url.lastPathComponent,
            payload: encode(payload),
            searchText: url.path
        )
    }

    private static func makeFile(url: URL, kind: String, sizeKB: Int, app: String?) -> DetectedClip {
        let payload = FilePayload(path: url.path, kind: kind, sizeKB: sizeKB)
        return DetectedClip(
            type: .file,
            app: app,
            title: url.lastPathComponent,
            payload: encode(payload),
            searchText: url.path
        )
    }

    // MARK: - Helpers

    private static func encode<T: Encodable>(_ value: T) -> Data {
        // Force-try is acceptable here: our payload structs are simple Codable
        // structs with no failure modes besides programmer error.
        return try! JSONEncoder().encode(value)
    }

    private static func title(forText body: String) -> String? {
        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? body
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(80))
    }

    private static func guessLang(_ body: String) -> String? {
        // Tiny heuristic. Expanded in v0.3.
        if body.contains("func ") && body.contains("{") { return "swift" }
        if body.contains("def ") && body.contains(":") { return "python" }
        if body.contains("function ") || body.contains("=>") { return "javascript" }
        if body.contains("#include") { return "c" }
        if body.contains("<!DOCTYPE") { return "html" }
        if body.contains("<?php") { return "php" }
        return nil
    }
}
