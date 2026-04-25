import Foundation
import GRDB

extension ClipRepository {
    /// Runs a parsed `SearchQuery` against the database.
    /// Pin always sorts first (per spec §05), then created_at DESC.
    /// Empty query returns recent clips like `recent(limit:)`.
    func search(_ query: SearchQuery, limit: Int = 200) throws -> [ClipRecord] {
        if query.isEmpty {
            return try recent(limit: limit)
        }

        return try database.dbQueue.read { db in
            var sql = "SELECT clips.* FROM clips"
            var args: [DatabaseValueConvertible] = []
            var wheres: [String] = []

            // Free-text search: join FTS5 if there are terms.
            if !query.terms.isEmpty {
                // FTS5 default tokenizer is space-separated AND-of-terms when the input
                // is a bare word list. Wrap each term in double quotes to escape special
                // characters (colons, hyphens, parens) safely.
                let ftsExpression = query.terms
                    .map { sanitizeFTSTerm($0) }
                    .joined(separator: " ")
                sql += " JOIN clips_fts ON clips_fts.clip_id = clips.id"
                wheres.append("clips_fts MATCH ?")
                args.append(ftsExpression)
            }

            if !query.typeFilters.isEmpty {
                let placeholders = query.typeFilters.map { _ in "?" }.joined(separator: ", ")
                wheres.append("clips.type IN (\(placeholders))")
                args.append(contentsOf: query.typeFilters.map { $0.rawValue })
            }

            if !query.apps.isEmpty {
                let placeholders = query.apps.map { _ in "?" }.joined(separator: ", ")
                wheres.append("clips.app IN (\(placeholders))")
                args.append(contentsOf: query.apps)
            }

            if query.pinnedOnly {
                wheres.append("clips.pinned = 1")
            }

            // tags: stored as JSON array string (e.g. '["react","hook"]').
            // v0.1 always inserts '[]'; the LIKE filter is harmless until tag editing
            // lands in v0.3. Implemented now so the parser/UI can carry tag tokens
            // without dropping them on the floor.
            for tag in query.tags {
                wheres.append("clips.tags LIKE ?")
                args.append("%\"\(tag)\"%")
            }

            if !wheres.isEmpty {
                sql += " WHERE " + wheres.joined(separator: " AND ")
            }

            sql += " ORDER BY clips.pinned DESC, clips.created_at DESC LIMIT \(limit)"

            return try ClipRecord.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }
    }

    /// Toggle pinned state for a single clip.
    func togglePin(clipId: String) throws {
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET pinned = 1 - pinned WHERE id = ?",
                arguments: [clipId]
            )
        }
    }

    // MARK: - Helpers

    /// Escapes a single FTS5 term. Wraps in double quotes and doubles any embedded quotes.
    private func sanitizeFTSTerm(_ term: String) -> String {
        let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
