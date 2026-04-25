import Foundation
import GRDB

/// Persistent representation of a clip. Mirrors the `clips` table 1:1.
/// `tags` is JSON-encoded `[String]`; `payload` is the per-type JSON struct from `ClipPayload.swift`.
struct ClipRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: String
    var type: String          // ClipType.rawValue
    var app: String?
    var createdAt: Double     // unix timestamp (seconds), matches the REAL column
    var pinned: Bool
    var tags: String          // JSON array of strings
    var title: String?
    var payload: Data         // JSON-encoded payload struct

    static let databaseTableName = "clips"

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case app
        case createdAt = "created_at"
        case pinned
        case tags
        case title
        case payload
    }

    var createdAtDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }
}
