import Foundation
import GRDB

/// Enforces SettingsStore retention policies on the clips table.
/// Called after each ingest (debounced internally) and on demand from Settings.
@MainActor
final class HistoryReaper {
    let database: Database
    let store: SettingsStore

    private var pendingTask: Task<Void, Never>?

    init(database: Database = .shared, store: SettingsStore = .shared) {
        self.database = database
        self.store = store
    }

    /// Schedule a reap. Coalesces bursts of ingests into one DELETE pass.
    func scheduleReap() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.reapNow()
        }
    }

    /// Apply retention immediately.
    func reapNow() {
        do {
            try database.dbQueue.write { db in
                if store.keepHistoryDays > 0 {
                    let cutoff = Date()
                        .addingTimeInterval(-Double(store.keepHistoryDays) * 86_400)
                        .timeIntervalSince1970
                    try db.execute(
                        sql: "DELETE FROM clips WHERE pinned = 0 AND created_at < ?;",
                        arguments: [cutoff]
                    )
                }
                if store.maxItems > 0 {
                    try db.execute(sql: """
                        DELETE FROM clips
                        WHERE pinned = 0
                          AND id NOT IN (
                              SELECT id FROM clips
                              WHERE pinned = 0
                              ORDER BY created_at DESC
                              LIMIT ?
                          );
                    """, arguments: [store.maxItems])
                }
            }
        } catch {
            NSLog("[history] reap failed: %@", "\(error)")
        }
    }

    /// Wipe everything — clips + FTS index + on-disk image cache.
    /// Settings → History → Clear all clips.
    func clearAll() {
        do {
            try database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM clips;")
                try db.execute(sql: "DELETE FROM clips_fts;")
            }
            // Clear image cache (no clips → orphaned files).
            if let urls = try? FileManager.default.contentsOfDirectory(
                at: ImageStorage.directoryURL,
                includingPropertiesForKeys: nil
            ) {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            NSLog("[history] cleared all clips + image cache")
        } catch {
            NSLog("[history] clearAll failed: %@", "\(error)")
        }
    }
}
