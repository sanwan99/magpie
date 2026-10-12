import AppKit

enum ClipboardChangeOrigin: Sendable, Equatable {
    case observed
    case explicitScreenshot
}

/// Sendable pasteboard snapshot captured on the main thread.
///
/// AppKit pasteboard objects are not a good boundary to hand to background
/// work. The watcher copies out only the data Magpie needs, then detection and
/// storage can run without holding the main run loop.
struct ClipboardSnapshot: Sendable {
    let changeCount: Int
    let typeNames: [String]
    let fileURLs: [URL]
    let imageData: Data?
    let imageTypeName: String?
    let string: String?

    var typesDescription: String {
        typeNames.joined(separator: ", ")
    }

    @MainActor
    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let types = pasteboard.types ?? []
        let hasFileURL = types.contains(.fileURL)
        let fileURLs = hasFileURL
            ? (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? [])
            : []
        let imageType = pasteboard.availableType(from: [.png, .tiff])
        let imageData = imageType.flatMap { pasteboard.data(forType: $0) }

        return ClipboardSnapshot(
            changeCount: pasteboard.changeCount,
            typeNames: types.map(\.rawValue),
            fileURLs: fileURLs,
            imageData: imageData,
            imageTypeName: imageType?.rawValue,
            string: pasteboard.string(forType: .string)
        )
    }
}

/// Polls NSPasteboard.changeCount on a 400 ms cadence and fires `onChange`
/// when the count moves. Initial pasteboard state is treated as already-seen
/// so we don't dump existing user content into history at launch.
@MainActor
final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private var preparedOrigin: ClipboardChangeOrigin?
    private let pollInterval: TimeInterval

    /// Fired on the main thread whenever the pasteboard changes.
    /// The closure receives a copied snapshot; expensive ingest work should
    /// continue off the main thread.
    var onChange: ((ClipboardSnapshot, ClipboardChangeOrigin) -> Void)?

    init(pasteboard: NSPasteboard = .general, pollInterval: TimeInterval = 0.4) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollOnce()
            }
        }
        // RunLoop.main is the default; explicit add keeps the timer alive during modal panels.
        RunLoop.main.add(t, forMode: .common)
        self.timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reserve the next image pasteboard change immediately before an explicit
    /// image write. Cancel the reservation if that write fails.
    func prepareNextChange(origin: ClipboardChangeOrigin) {
        preparedOrigin = origin
    }

    func cancelPreparedChange(origin: ClipboardChangeOrigin) {
        guard preparedOrigin == origin else { return }
        preparedOrigin = nil
    }

    /// Immediately processes a pasteboard change and advances lastChangeCount,
    /// preventing the regular timer from ingesting the same screenshot twice.
    @discardableResult
    func pollNow() -> Bool {
        pollOnce()
    }

    @discardableResult
    func pollNow(origin: ClipboardChangeOrigin) -> Bool {
        pollOnce(forcedOrigin: origin)
    }

    @discardableResult
    private func pollOnce(forcedOrigin: ClipboardChangeOrigin? = nil) -> Bool {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else {
            if let forcedOrigin, preparedOrigin == forcedOrigin {
                preparedOrigin = nil
            }
            return false
        }
        lastChangeCount = current
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)

        let origin: ClipboardChangeOrigin
        if let forcedOrigin {
            origin = forcedOrigin
            if preparedOrigin == forcedOrigin {
                preparedOrigin = nil
            }
        } else if let preparedOrigin {
            guard let imageData = snapshot.imageData, !imageData.isEmpty else {
                // A reservation only applies to images; wait for the explicit
                // writer to finish or cancel it.
                NSLog("[clipboard] count=%d ignored non-image while origin=%@ is pending",
                      snapshot.changeCount,
                      String(describing: preparedOrigin))
                return false
            }
            origin = preparedOrigin
            self.preparedOrigin = nil
        } else {
            origin = .observed
        }

        onChange?(snapshot, origin)
        return true
    }
}
