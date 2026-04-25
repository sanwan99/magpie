import AppKit

/// Polls NSPasteboard.changeCount on a 400 ms cadence and fires `onChange`
/// when the count moves. Initial pasteboard state is treated as already-seen
/// so we don't dump existing user content into history at launch.
@MainActor
final class ClipboardWatcher {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.4

    /// Fired on the main thread whenever the pasteboard changes.
    /// The closure receives the live pasteboard for inspection.
    var onChange: ((NSPasteboard) -> Void)?

    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
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

    private func pollOnce() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        onChange?(pasteboard)
    }
}
