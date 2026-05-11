import Foundation

/// Parses raw search input from the search field.
///
/// Grammar (per prototype spec §07):
///   - whitespace-separated tokens, AND-ed together
///   - tokens with `key:value` shape are facets — recognized keys: `type`, `app`, `tag`
///   - everything else is a free-text term, matched against the FTS index
///     (CJK terms also get a storage-layer substring fallback)
///
/// Example:
///   `type:code react hook app:vscode`
///   → terms=[react, hook], typeFilters=[.code], apps=[vscode]
enum SearchQueryParser {
    static func parse(_ input: String, pinnedOnly: Bool = false) -> SearchQuery {
        var typeFilters: [ClipType] = []
        var apps: [String] = []
        var tags: [String] = []
        var terms: [String] = []

        let tokens = tokenize(input)

        for token in tokens {
            if let colon = token.firstIndex(of: ":") {
                let key = String(token[..<colon]).lowercased()
                let value = String(token[token.index(after: colon)...])
                guard !value.isEmpty else { continue }

                switch key {
                case "type":
                    if let t = ClipType(rawValue: value.lowercased()) {
                        typeFilters.append(t)
                    }
                    // Unknown type token is silently dropped — could surface in v0.3 with a hint.
                case "app":
                    apps.append(value)
                case "tag":
                    tags.append(value)
                default:
                    // Unrecognized facet → treat the whole token as a free term.
                    terms.append(token)
                }
            } else {
                terms.append(token)
            }
        }

        return SearchQuery(
            terms: terms,
            typeFilters: typeFilters,
            apps: apps,
            tags: tags,
            pinnedOnly: pinnedOnly
        )
    }

    /// Tokenizes the raw search box input while preserving quoted phrases.
    /// Examples:
    /// - `foo bar` -> [`foo`, `bar`]
    /// - `"foo bar"` -> [`foo bar`]
    /// - `app:"Visual Studio Code"` -> [`app:Visual Studio Code`]
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false

        func flushCurrent() {
            guard !current.isEmpty else { return }
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for char in input {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }

            if char.isWhitespace && !inQuotes {
                flushCurrent()
            } else {
                current.append(char)
            }
        }

        flushCurrent()
        return tokens
    }
}
