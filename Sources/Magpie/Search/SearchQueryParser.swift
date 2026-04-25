import Foundation

/// Parses raw search input from the search field.
///
/// Grammar (per prototype spec §07):
///   - whitespace-separated tokens, AND-ed together
///   - tokens with `key:value` shape are facets — recognized keys: `type`, `app`, `tag`
///   - everything else is a free-text term, matched against the FTS index
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

        // Split on whitespace; tokens are short, no need for a real tokenizer.
        let tokens = input
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

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
}
