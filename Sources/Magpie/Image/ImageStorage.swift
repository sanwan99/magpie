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
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
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
        guard let tiff = image.tiffRepresentation else {
            NSLog("[image] save: failed to encode PNG")
            return nil
        }
        return save(imageData: tiff)
    }

    /// Persist pasteboard image bytes as PNG. This is safe to run off the main
    /// thread and is the hot clipboard-ingest path.
    @discardableResult
    static func save(imageData data: Data, in directory: URL = directoryURL) -> SavedImage? {
        guard let bitmap = NSBitmapImageRep(data: data),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            NSLog("[image] save: failed to decode image data")
            return nil
        }

        let id = UUID().uuidString
        let url = directory.appendingPathComponent("\(id).png")
        do {
            try pngData.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return SavedImage(
                path: url.path,
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh,
                sizeKB: max(1, Int(pngData.count / 1024))
            )
        } catch {
            try? FileManager.default.removeItem(at: url)
            DiagnosticLog.failure("image.save", error: error)
            return nil
        }
    }

    /// Reject traversal, symlinks, directories, and paths outside our PNG cache.
    static func isManagedFile(_ url: URL, in directory: URL = directoryURL) -> Bool {
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
              candidate.pathExtension.lowercased() == "png",
              let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return true
    }

    @discardableResult
    static func removeManagedFile(at path: String, in directory: URL = directoryURL) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard isManagedFile(url, in: directory) else { return false }
        do { try FileManager.default.removeItem(at: url); return true }
        catch { DiagnosticLog.failure("image.remove", error: error); return false }
    }

    /// Caller holds Database.withStorageLock so an in-flight ingest cannot be swept.
    static func removeOrphans(keeping paths: Set<String>, in directory: URL = directoryURL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if !paths.contains(url.path), isManagedFile(url, in: directory) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Load NSImage from a previously-saved path. Returns nil if the file
    /// is missing (e.g. user cleared cache externally).
    static func load(path: String) -> NSImage? {
        NSImage(contentsOfFile: path)
    }
}
