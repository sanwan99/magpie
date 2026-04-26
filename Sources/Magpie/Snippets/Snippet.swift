import Foundation

/// User-defined text template (per spec §10).
///
/// `shortcut` is the trigger string (e.g. `;sig`, `;meet`) — typing it in
/// any text field can auto-expand to `body` once the global expander lands
/// (v0.3-b2). For now the user picks snippets manually from the drawer.
struct Snippet: Equatable, Sendable, Identifiable, Codable {
    let id: String
    var shortcut: String
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date

    static func newDraft() -> Snippet {
        let now = Date()
        return Snippet(
            id: UUID().uuidString,
            shortcut: "",
            title: "",
            body: "",
            createdAt: now,
            updatedAt: now
        )
    }
}
