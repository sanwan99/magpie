import AppKit
import SwiftUI

/// Owns the lifecycle of the Magpie panel: positioning at the bottom of the active screen,
/// hosting SwiftUI content with vibrancy, and the show/hide slide animation.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private let viewModel: ClipsViewModel
    private let frontmost = FrontmostTracker()
    private var keyMonitor: Any?
    private var afterHide: (() -> Void)?
    private(set) var isVisible: Bool = false

    /// Panel size — wide enough for Stripe layout + top bar (search + filter rail).
    static let panelSize = NSSize(width: 980, height: 380)
    /// Distance from the bottom of the active screen.
    static let bottomInset: CGFloat = 24

    init(viewModel: ClipsViewModel) {
        self.viewModel = viewModel
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        self.panel = PanelWindow(contentRect: frame)
        self.panel.contentView = makeContentView()
        wireKeyboard()

        viewModel.onPasteRequest = { [weak self] in
            self?.paste()
        }
    }

    // MARK: - Show / Hide

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard !isVisible else { return }
        // Snapshot the frontmost app *before* the panel becomes key, so paste
        // can target the correct app even if .nonactivatingPanel ever flakes.
        frontmost.snapshot()
        viewModel.refresh()

        positionAtBottomCenter()
        let target = panel.frame
        let start = target.offsetBy(dx: 0, dy: -target.height - 16)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1.0)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        isVisible = true
    }

    func hide() {
        guard isVisible else {
            // Even if we weren't visible, run any pending after-hide hook so
            // paste flows can't get stranded.
            afterHide?()
            afterHide = nil
            return
        }
        let target = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height - 16)
        // Drop SwiftUI's first responder (the SearchField) immediately, otherwise
        // a fast follow-up CGEvent ⌘V would land on the panel's text field
        // instead of the app behind us.
        panel.makeFirstResponder(nil)
        let pendingAfter = afterHide
        afterHide = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // orderOut tears down keyWindow + revokes frontmost focus from the panel.
            // Only after this is it safe to simulate ⌘V into the previously frontmost app.
            self?.panel.orderOut(nil)
            pendingAfter?()
        })
        isVisible = false
    }

    // MARK: - Paste flow

    /// Paste the currently focused clip into the previously frontmost app.
    private func paste() {
        guard let clip = viewModel.focusedClip else { return }
        executePaste(clip)
    }

    /// Paste the Nth clip directly (⌘1…⌘9).
    private func pasteAt(_ index: Int) {
        guard let clip = viewModel.clip(at: index) else { return }
        viewModel.focusedIndex = index
        executePaste(clip)
    }

    private func executePaste(_ clip: ClipDisplayItem) {
        let target = frontmost.savedTarget
        guard let written = Paster.writeToPasteboard(clip), !written.isEmpty else {
            NSLog("[paste] clip has no pasteable content (id=%@ type=%@)", clip.id, clip.type.rawValue)
            return
        }
        NSLog("[paste] writing %d chars (type=%@) into pasteboard, target=%@",
              written.count, clip.type.rawValue, target?.bundleIdentifier ?? "?")
        // Schedule the actual ⌘V to fire only AFTER the panel's hide animation
        // completes and orderOut runs — that way the panel is no longer the
        // keyWindow, and the synthetic ⌘V lands on the previously frontmost app.
        afterHide = {
            Paster.paste(into: target)
        }
        hide()
    }

    // MARK: - Layout

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let x = visible.midX - size.width / 2
        let y = visible.minY + Self.bottomInset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    // MARK: - Keyboard wiring

    private func wireKeyboard() {
        panel.onCancel = { [weak self] in
            self?.handleCancel()
        }
        panel.onPaste = { [weak self] in
            self?.paste()
        }
        panel.onMoveBack = { [weak self] in
            self?.viewModel.moveBack()
        }
        panel.onMoveForward = { [weak self] in
            self?.viewModel.moveForward()
        }
        panel.onPasteAtIndex = { [weak self] index in
            self?.pasteAt(index)
        }
        panel.onTogglePin = { [weak self] in
            self?.viewModel.toggleFocusedPin()
        }

        // SwiftUI's TextField (now hosting the search field) sits at the front of
        // the responder chain and swallows several command keystrokes that we want
        // to handle at the panel level (⌘D for pin, ⌘1-9 for quick paste, Esc for
        // the clear-cascade). Install a local NSEvent monitor that catches these
        // before SwiftUI sees them, but only while the panel is the key window.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isKeyWindow else { return event }
            return self.handleLocalKey(event)
        }
    }

    private func handleLocalKey(_ event: NSEvent) -> NSEvent? {
        let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command

        // Esc — clear-cascade (always wins, even while typing in the search field).
        if event.keyCode == 53 {
            handleCancel()
            return nil
        }

        // Return / Numpad Enter — paste focused clip (always wins).
        if event.keyCode == 36 || event.keyCode == 76 {
            paste()
            return nil
        }

        if cmd, let chars = event.charactersIgnoringModifiers {
            // ⌘D toggle pin
            if chars == "d" {
                viewModel.toggleFocusedPin()
                return nil
            }
            // ⌘1…⌘9 quick paste at index
            if chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               let digit = Int(String(scalar)),
               (1...9).contains(digit) {
                pasteAt(digit - 1)
                return nil
            }
        }

        // Arrow keys: always navigate cards. The search field is short enough
        // that ceding caret movement to it isn't worth losing primary nav.
        switch event.keyCode {
        case 123, 126: // Left, Up
            viewModel.moveBack()
            return nil
        case 124, 125: // Right, Down
            viewModel.moveForward()
            return nil
        default:
            break
        }

        return event
    }

    /// Esc cascade per spec §06: clear search → clear filters → hide panel.
    private func handleCancel() {
        if !viewModel.searchInput.isEmpty {
            viewModel.searchInput = ""
            viewModel.refresh()
            return
        }
        if viewModel.typeFilter != nil {
            viewModel.typeFilter = nil
            return
        }
        if viewModel.pinnedOnly {
            viewModel.pinnedOnly = false
            return
        }
        hide()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: - Content

    private func makeContentView() -> NSView {
        let host = NSHostingView(rootView: PanelContentView(viewModel: viewModel))
        let container = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        return container
    }
}

/// Top-level panel content — top bar (search + filter rail) + body (Stripe / empty state).
private struct PanelContentView: View {
    let viewModel: ClipsViewModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            content
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Magpie")
                    .font(.system(size: 13, weight: .bold))
                SearchField(viewModel: viewModel)
            }
            FilterRail(viewModel: viewModel)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.clips.isEmpty {
            emptyState
        } else {
            StripeLayout(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: viewModel.totalClipCount == 0 ? "tray" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(viewModel.totalClipCount == 0 ? "No clips yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.totalClipCount == 0
                 ? "Copy something — text, code, a link, or a folder path — to get started."
                 : "Try a different search or clear filters with Esc.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
