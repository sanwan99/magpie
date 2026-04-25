import Foundation

/// One of the 6 clip kinds defined by the prototype spec §03.
/// v0.1 ingests text / code / url / folder; image and file land in v0.3.
enum ClipType: String, Codable, Sendable, CaseIterable {
    case text
    case code
    case url
    case image
    case file
    case folder
}
