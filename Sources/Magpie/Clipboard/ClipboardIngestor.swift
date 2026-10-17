import Foundation

struct ClipboardIngestPolicy: Sendable {
    let appBundleIdentifier: String?
    let ignoredApps: [String]
    let skipSecretLooking: Bool

    static func forChange(
        origin: ClipboardChangeOrigin,
        observedAppBundleIdentifier: String?,
        magpieBundleIdentifier: String,
        ignoredApps: [String],
        skipSecretLooking: Bool
    ) -> ClipboardIngestPolicy {
        switch origin {
        case .observed:
            return ClipboardIngestPolicy(
                appBundleIdentifier: observedAppBundleIdentifier,
                ignoredApps: ignoredApps,
                skipSecretLooking: skipSecretLooking
            )
        case .explicitScreenshot:
            // An explicit user action must not be discarded just because the
            // app underneath the screenshot is on the passive-watch ignore list.
            return ClipboardIngestPolicy(
                appBundleIdentifier: magpieBundleIdentifier,
                ignoredApps: [],
                skipSecretLooking: skipSecretLooking
            )
        }
    }
}

/// Serial background ingest pipeline for clipboard snapshots.
///
/// Keeping this work off MainActor prevents image encoding, file metadata reads
/// and SQLite writes from blocking global hotkey delivery or panel wakeup.
actor ClipboardIngestor {
    private let repository: ClipRepository

    private let imageDirectoryURL: URL

    init(repository: ClipRepository, imageDirectoryURL: URL = ImageStorage.directoryURL) {
        self.repository = repository
        self.imageDirectoryURL = imageDirectoryURL
    }

    /// Returns true when storage changed and the UI should refresh.
    func ingest(snapshot: ClipboardSnapshot, policy: ClipboardIngestPolicy,
                expectedGeneration: UInt64? = nil) -> Bool {
        guard !snapshot.isPrivate else { return false }
        if let app = policy.appBundleIdentifier, policy.ignoredApps.contains(app) { return false }
        // Check the string before image detection can persist a file. Mixed
        // image/text pasteboards must not bypass the secret filter.
        if policy.skipSecretLooking, let text = snapshot.string,
           SecretDetector.looksSecret(text) { return false }

        return repository.database.withStorageLock {
            if let expectedGeneration,
               expectedGeneration != repository.database.currentIngestGeneration { return false }
            guard let detected = ClipDetector.detect(snapshot: snapshot, app: policy.appBundleIdentifier, imageDirectoryURL: imageDirectoryURL) else {
                return false
            }
            if policy.skipSecretLooking, let text = Self.textBody(of: detected),
               SecretDetector.looksSecret(text) { return false }
            do {
                try repository.insert(detected)
                NSLog("[clipboard] ingested")
                return true
            } catch {
                if detected.type == .image,
                   let image = try? JSONDecoder().decode(ImagePayload.self, from: detected.payload) {
                    _ = ImageStorage.removeManagedFile(at: image.path, in: imageDirectoryURL)
                }
                DiagnosticLog.failure("clipboard.insert", error: error)
                return false
            }
        }
    }

    private static func textBody(of detected: DetectedClip) -> String? {
        switch detected.type {
        case .text:
            return (try? JSONDecoder().decode(TextPayload.self, from: detected.payload))?.body
        case .code:
            return (try? JSONDecoder().decode(CodePayload.self, from: detected.payload))?.body
        case .url:
            return (try? JSONDecoder().decode(URLPayload.self, from: detected.payload))?.url
        case .folder, .file, .image:
            return nil
        }
    }
}
