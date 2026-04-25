import AppKit

/// Captures the frontmost application immediately before the panel shows.
/// `.nonactivatingPanel` already prevents Magpie from stealing focus, so the
/// system's frontmost should stay correct, but we snapshot defensively for
/// the corner case where another app launches in the same beat.
@MainActor
final class FrontmostTracker {
    private(set) var savedTarget: NSRunningApplication?

    func snapshot() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard let frontmost else { return }
        // Don't capture ourselves.
        if frontmost.bundleIdentifier == "com.sanwan.magpie" {
            return
        }
        savedTarget = frontmost
    }

    func clear() {
        savedTarget = nil
    }
}
