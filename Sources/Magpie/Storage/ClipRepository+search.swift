import Foundation
import GRDB

extension ClipRepository {
    /// Runs a parsed `SearchQuery` against the database.
    /// Filtered results sort pins first, then creation time.
    /// Empty query preserves the recent-history order of `recent(limit:)`.
    func search(_ query: SearchQuery, limit: Int = 200) throws -> [ClipRecord] {
        let limit = max(0, min(limit, 1000))
        if query.isEmpty {
            return try recent(limit: limit)
        }

        return try database.dbQueue.read { db in
            var sql = "SELECT clips.* FROM clips"
            var args: [DatabaseValueConvertible] = []
            var wheres: [String] = []

            // Free-text search stays content-only. Source app matching is an
            // explicit facet (`app:vscode`), otherwise common app names such as
            // `codex` can pull in large unrelated chunks of history.
            for term in query.terms {
                if needsSubstringFallback(term) {
                    let pattern = likePattern(for: term)
                    wheres.append("""
                        (
                            clips.id IN (
                                SELECT clip_id
                                FROM clips_fts
                                WHERE clips_fts MATCH ?
                            )
                            OR clips.id IN (
                                SELECT clip_id
                                FROM clips_fts
                                WHERE LOWER(COALESCE(title, '')) LIKE ? ESCAPE '\\'
                                   OR LOWER(COALESCE(body, '')) LIKE ? ESCAPE '\\'
                                   OR LOWER(COALESCE(tags, '')) LIKE ? ESCAPE '\\'
                            )
                            OR LOWER(COALESCE(clips.note, '')) LIKE ? ESCAPE '\\'
                        )
                        """)
                    args.append(sanitizeFTSTerm(term))
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                    args.append(pattern)
                } else {
                    wheres.append("""
                        (
                            clips.id IN (
                                SELECT clip_id
                                FROM clips_fts
                                WHERE clips_fts MATCH ?
                            )
                            OR LOWER(COALESCE(clips.note, '')) LIKE ? ESCAPE '\\'
                        )
                        """)
                    args.append(sanitizeFTSTerm(term))
                    args.append(likePattern(for: term))
                }
            }

            if !query.typeFilters.isEmpty {
                let placeholders = query.typeFilters.map { _ in "?" }.joined(separator: ", ")
                wheres.append("clips.type IN (\(placeholders))")
                args.append(contentsOf: query.typeFilters.map { $0.rawValue })
            }

            if !query.apps.isEmpty {
                let clauses = query.apps.map { _ in "LOWER(COALESCE(clips.app, '')) LIKE ? ESCAPE '\\'" }
                wheres.append("(" + clauses.joined(separator: " OR ") + ")")
                args.append(contentsOf: query.apps.map(likePattern(for:)))
            }

            if query.pinnedOnly {
                wheres.append("clips.pinned = 1")
            }

            // tags: stored as JSON array string (e.g. '["react","hook"]').
            // New captures have no tags. Preserve matching for existing/imported
            // tags; the current UI does not provide a tag editor.
            for tag in query.tags {
                wheres.append("clips.tags LIKE ? ESCAPE '\\'")
                args.append(likePattern(for: "\"\(tag)\""))
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

    /// Updates the user note attached to a clip. The UI exposes this only for
    /// pinned clips, but the data is intentionally kept if the clip is unpinned.
    func updateNote(clipId: String, note: String) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET note = ? WHERE id = ?",
                arguments: [trimmed, clipId]
            )
        }
    }

    // MARK: - Helpers

    /// Escapes a single FTS5 term. Wraps in double quotes and doubles any embedded quotes.
    private func sanitizeFTSTerm(_ term: String) -> String {
        let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Builds a case-insensitive LIKE pattern for app matching.
    /// App metadata is currently stored as bundle identifiers (for example
    /// `com.microsoft.VSCode`), while the user-facing syntax uses shorter
    /// aliases such as `app:vscode`, so exact equality is too strict.
    private func likePattern(for raw: String) -> String {
        let escaped = raw
            .lowercased()
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    /// FTS5 unicode61 is strong for English/code tokens but not Chinese word
    /// segmentation. Use substring fallback only when a term contains CJK text.
    private func needsSubstringFallback(_ term: String) -> Bool {
        term.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}
