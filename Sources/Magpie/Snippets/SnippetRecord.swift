import Foundation
import GRDB

/// GRDB row mirror for the `snippets` table.
struct SnippetRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: String
    var shortcut: String
    var title: String
    var body: String
    var createdAt: Double  // unix seconds — matches REAL column
    var updatedAt: Double

    static let databaseTableName = "snippets"

    enum CodingKeys: String, CodingKey {
        case id, shortcut, title, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension SnippetRecord {
    init(_ snippet: Snippet) {
        self.id = snippet.id
        self.shortcut = snippet.shortcut
        self.title = snippet.title
        self.body = snippet.body
        self.createdAt = snippet.createdAt.timeIntervalSince1970
        self.updatedAt = snippet.updatedAt.timeIntervalSince1970
    }

    var domain: Snippet {
        Snippet(
            id: id,
            shortcut: shortcut,
            title: title,
            body: body,
            createdAt: Date(timeIntervalSince1970: createdAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
