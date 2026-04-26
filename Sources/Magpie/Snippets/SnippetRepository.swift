import Foundation
import GRDB

/// CRUD facade for snippets.
struct SnippetRepository {
    let database: Database

    init(database: Database = .shared) {
        self.database = database
    }

    /// All snippets, sorted by title (case-insensitive).
    func all() throws -> [Snippet] {
        try database.dbQueue.read { db in
            try SnippetRecord
                .order(Column("title").collating(.localizedCaseInsensitiveCompare).asc)
                .fetchAll(db)
                .map(\.domain)
        }
    }

    /// Find by exact `shortcut` (used by the v0.3-b2 expander).
    func find(shortcut: String) throws -> Snippet? {
        try database.dbQueue.read { db in
            try SnippetRecord
                .filter(Column("shortcut") == shortcut)
                .fetchOne(db)?.domain
        }
    }

    /// Insert or update. Updates `updatedAt` to now.
    func upsert(_ snippet: Snippet) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO snippets
                  (id, shortcut, title, body, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?);
            """, arguments: [
                snippet.id,
                snippet.shortcut,
                snippet.title,
                snippet.body,
                snippet.createdAt.timeIntervalSince1970,
                Date().timeIntervalSince1970
            ])
        }
    }

    func delete(id: String) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id])
        }
    }

    func count() throws -> Int {
        try database.dbQueue.read { db in
            try SnippetRecord.fetchCount(db)
        }
    }
}
