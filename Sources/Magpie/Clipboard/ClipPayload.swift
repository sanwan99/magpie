import Foundation

/// Per-type payload structs. Stored as JSON in the `clips.payload` column.
/// Decoding uses `ClipType` from the row to pick the right struct, so payloads
/// don't carry their own type tag.

struct TextPayload: Codable, Sendable, Equatable {
    let body: String
}

struct CodePayload: Codable, Sendable, Equatable {
    let body: String
    let lang: String?
}

struct URLPayload: Codable, Sendable, Equatable {
    let url: String
    let host: String?
    let title: String?
    let desc: String?
}

struct FolderPayload: Codable, Sendable, Equatable {
    let path: String
    let items: Int
}

struct FilePayload: Codable, Sendable, Equatable {
    let path: String
    let kind: String
    let sizeKB: Int
}

struct ImagePayload: Codable, Sendable, Equatable {
    let path: String
    let width: Int
    let height: Int
    let sizeKB: Int
}

/// Capture-side struct produced by `ClipDetector`. The repository turns it into a row.
struct DetectedClip: Sendable {
    let type: ClipType
    let app: String?
    let title: String?
    let payload: Data       // JSON-encoded type-specific struct
    let searchText: String  // pre-extracted text for FTS5
}
