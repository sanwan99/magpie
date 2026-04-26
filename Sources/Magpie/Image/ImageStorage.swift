import AppKit
import Foundation

/// On-disk image cache for clipped images.
/// Files live under `~/Library/Application Support/Magpie/images/<uuid>.png`.
/// The DB only stores the path + dimensions + size; the bytes themselves stay
/// on disk so the SQLite file remains small.
enum ImageStorage {
    /// Lazy-init: ensures the directory exists on first access.
    static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Magpie/images", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }()

    struct SavedImage {
        let path: String
        let width: Int
        let height: Int
        let sizeKB: Int
    }

    /// Persist an NSImage as a PNG. Returns the saved file's metadata, or
    /// nil if encoding/writing fails.
    @discardableResult
    static func save(_ image: NSImage) -> SavedImage? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            NSLog("[image] save: failed to encode PNG")
            return nil
        }

        let id = UUID().uuidString
        let url = directoryURL.appendingPathComponent("\(id).png")
        do {
            try pngData.write(to: url)
            return SavedImage(
                path: url.path,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh,
                sizeKB: max(1, Int(pngData.count / 1024))
            )
        } catch {
            NSLog("[image] save failed: %@", "\(error)")
            return nil
        }
    }

    /// Load NSImage from a previously-saved path. Returns nil if the file
    /// is missing (e.g. user cleared cache externally).
    static func load(path: String) -> NSImage? {
        NSImage(contentsOfFile: path)
    }
}
