import Foundation

/// Parsed search input — facets + free-text terms — that the repository can run.
/// Empty query (`isEmpty == true`) means "no filtering, show recent".
struct SearchQuery: Equatable, Sendable {
    /// Free-text terms. Each one must hit the FTS index. Empty = no text constraint.
    var terms: [String]
    /// Type whitelist. Empty = all types.
    var typeFilters: [ClipType]
    /// App bundle id whitelist. Empty = no constraint.
    var apps: [String]
    /// Tag whitelist. Empty = no constraint.
    var tags: [String]
    /// Whether to restrict to pinned items only.
    var pinnedOnly: Bool

    static let empty = SearchQuery(terms: [], typeFilters: [], apps: [], tags: [], pinnedOnly: false)

    var isEmpty: Bool {
        terms.isEmpty && typeFilters.isEmpty && apps.isEmpty && tags.isEmpty && !pinnedOnly
    }
}
