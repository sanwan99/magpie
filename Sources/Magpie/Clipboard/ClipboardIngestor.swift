import Foundation

struct ClipboardIngestPolicy: Sendable {
    let appBundleIdentifier: String?
    let ignoredApps: [String]
    let skipSecretLooking: Bool
}

/// Serial background ingest pipeline for clipboard snapshots.
///
/// Keeping this work off MainActor prevents image encoding, file metadata reads
/// and SQLite writes from blocking global hotkey delivery or panel wakeup.
actor ClipboardIngestor {
    private let repository: ClipRepository

    init(repository: ClipRepository) {
        self.repository = repository
    }

    /// Returns true when storage changed and the UI should refresh.
    func ingest(snapshot: ClipboardSnapshot, policy: ClipboardIngestPolicy) -> Bool {
        if let app = policy.appBundleIdentifier,
           policy.ignoredApps.contains(app) {
            NSLog("[clipboard] count=%d skipped (ignored app: %@)",
                  snapshot.changeCount, app)
            return false
        }

        guard let detected = ClipDetector.detect(snapshot: snapshot, app: policy.appBundleIdentifier) else {
            NSLog("[clipboard] count=%d skipped types=[%@]",
                  snapshot.changeCount, snapshot.typesDescription)
            return false
        }

        if policy.skipSecretLooking,
           let text = Self.textBody(of: detected),
           SecretDetector.looksSecret(text) {
            NSLog("[clipboard] count=%d skipped (looks like secret)", snapshot.changeCount)
            return false
        }

        do {
            try repository.insert(detected)
            let titlePreview = detected.title?.prefix(60).replacingOccurrences(of: "\n", with: "↵") ?? ""
            NSLog("[clipboard] count=%d type=%@ from=%@ title=\"%@\" ingested",
                  snapshot.changeCount,
                  detected.type.rawValue,
                  detected.app ?? "?",
                  String(titlePreview))
            return true
        } catch {
            NSLog("[clipboard] insert failed: %@", "\(error)")
            return false
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
