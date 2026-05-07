import Foundation
import GRDB

/// Enforces SettingsStore retention policies on the clips table.
/// Called after each ingest (debounced internally) and on demand from Settings.
@MainActor
final class HistoryReaper {
    let database: Database
    let store: SettingsStore
    private let imageDirectoryURL: URL

    /// 各 type 独立 cap（pinned 不计入，无视全局 maxItems）。
    /// - image: 50 — 占磁盘 / 内存大，超出连 db 行 + Magpie 自存的 PNG 一起清
    /// - file:  50 — payload.path 指向用户真实文件，**只删 db 行，不动磁盘**
    /// - folder:50 — 同 file
    nonisolated static let imageCap  = 50
    nonisolated static let fileCap   = 50
    nonisolated static let folderCap = 50

    private var pendingTask: Task<Void, Never>?

    private struct RetentionPolicy: Sendable {
        let keepHistoryDays: Int
        let maxItems: Int
    }

    init(database: Database, store: SettingsStore, imageDirectoryURL: URL) {
        self.database = database
        self.store = store
        self.imageDirectoryURL = imageDirectoryURL
    }

    convenience init(database: Database) {
        self.init(database: database, store: .shared, imageDirectoryURL: ImageStorage.directoryURL)
    }

    convenience init(database: Database, imageDirectoryURL: URL) {
        self.init(database: database, store: .shared, imageDirectoryURL: imageDirectoryURL)
    }

    convenience init() {
        self.init(database: .shared, store: .shared, imageDirectoryURL: ImageStorage.directoryURL)
    }

    /// Schedule a reap. Coalesces bursts of ingests into one DELETE pass.
    func scheduleReap() {
        pendingTask?.cancel()
        let database = self.database
        let policy = retentionPolicy()
        pendingTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                Self.applyRetention(database: database, policy: policy)
            }.value
        }
    }

    /// Apply retention immediately.
    func reapNow() {
        Self.applyRetention(database: database, policy: retentionPolicy())
    }

    /// Apply retention without blocking MainActor. Used on app launch and from
    /// clipboard-ingest debounce; tests still use `reapNow()` for deterministic
    /// assertions.
    func reapInBackground() {
        let database = self.database
        let policy = retentionPolicy()
        Task.detached(priority: .utility) {
            Self.applyRetention(database: database, policy: policy)
        }
    }

    private func retentionPolicy() -> RetentionPolicy {
        RetentionPolicy(
            keepHistoryDays: store.keepHistoryDays,
            maxItems: store.maxItems
        )
    }

    nonisolated private static func applyRetention(database: Database, policy: RetentionPolicy) {
        do {
            // 先在事务里删数据库行 + 收集要清理的 image 文件路径，事务结束后
            // 再 rm 物理文件（FileManager.removeItem 不放写事务里，避免 IO
            // 长时间持锁）。
            var imageFilesToRemove: [String] = []
            try database.dbQueue.write { db in
                if policy.keepHistoryDays > 0 {
                    let cutoff = Date()
                        .addingTimeInterval(-Double(policy.keepHistoryDays) * 86_400)
                        .timeIntervalSince1970
                    // 提前捞超期 image 的路径（删行后就拿不到了）
                    imageFilesToRemove += try Self.fetchImagePaths(
                        db: db,
                        sql: "SELECT payload FROM clips WHERE type = 'image' AND pinned = 0 AND created_at < ?",
                        arguments: [cutoff]
                    )
                    try db.execute(
                        sql: "DELETE FROM clips WHERE pinned = 0 AND created_at < ?;",
                        arguments: [cutoff]
                    )
                }
                if policy.maxItems > 0 {
                    // maxItems 是针对所有 clip 的，超出的非 pinned 砍掉
                    imageFilesToRemove += try Self.fetchImagePaths(
                        db: db,
                        sql: """
                            SELECT payload FROM clips
                             WHERE type = 'image' AND pinned = 0
                               AND id NOT IN (
                                   SELECT id FROM clips
                                   WHERE pinned = 0
                                   ORDER BY created_at DESC
                                   LIMIT ?
                               )
                        """,
                        arguments: [policy.maxItems]
                    )
                    try db.execute(sql: """
                        DELETE FROM clips
                        WHERE pinned = 0
                          AND id NOT IN (
                              SELECT id FROM clips
                              WHERE pinned = 0
                              ORDER BY created_at DESC
                              LIMIT ?
                          );
                    """, arguments: [policy.maxItems])
                }
                // image 类型独立 cap：non-pinned 保留最近 imageCap 条，更老的
                // 连数据库行 + 磁盘 PNG 一起清。先 SELECT 收集要删的 path，
                // 再 DELETE 行；事务结束后再 rm 文件（事务内不做 IO 防持锁）。
                imageFilesToRemove += try Self.fetchImagePaths(
                    db: db,
                    sql: """
                        SELECT payload FROM clips
                         WHERE type = 'image' AND pinned = 0
                           AND id NOT IN (
                               SELECT id FROM clips
                               WHERE type = 'image' AND pinned = 0
                               ORDER BY created_at DESC
                               LIMIT ?
                           )
                    """,
                    arguments: [Self.imageCap]
                )
                try Self.trimTypeCap(db: db, type: "image", cap: Self.imageCap)

                // file / folder：path 是用户真实文件，**只删 db 行不动磁盘**。
                try Self.trimTypeCap(db: db, type: "file",   cap: Self.fileCap)
                try Self.trimTypeCap(db: db, type: "folder", cap: Self.folderCap)
            }

            // 事务外清磁盘文件（非关键路径，失败不影响数据完整性）
            var removed = 0
            for path in imageFilesToRemove {
                if (try? FileManager.default.removeItem(atPath: path)) != nil {
                    removed += 1
                }
            }
            if removed > 0 {
                NSLog("[history] image cap → 清理 %d 个磁盘文件", removed)
            }
        } catch {
            NSLog("[history] reap failed: %@", "\(error)")
        }
    }

    /// 在写事务内查询 image clip 的磁盘路径列表（解码 payload JSON 取 path）。
    nonisolated private static func fetchImagePaths(
        db: GRDB.Database,
        sql: String,
        arguments: StatementArguments
    ) throws -> [String] {
        let payloads = try Data.fetchAll(db, sql: sql, arguments: arguments)
        let decoder = JSONDecoder()
        return payloads.compactMap { try? decoder.decode(ImagePayload.self, from: $0).path }
    }

    /// 通用 type cap 删除：保留某类型 non-pinned 最近 cap 条，更老的删 db 行。
    /// 不动任何磁盘文件 — image 想清磁盘需在调用前自己 fetchImagePaths。
    nonisolated private static func trimTypeCap(
        db: GRDB.Database,
        type: String,
        cap: Int
    ) throws {
        try db.execute(sql: """
            DELETE FROM clips
            WHERE type = ? AND pinned = 0
              AND id NOT IN (
                  SELECT id FROM clips
                  WHERE type = ? AND pinned = 0
                  ORDER BY created_at DESC
                  LIMIT ?
              );
        """, arguments: [type, type, cap])
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
                at: imageDirectoryURL,
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
