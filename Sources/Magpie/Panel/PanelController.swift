import AppKit
import SwiftUI

/// Owns the lifecycle of the Magpie panel: positioning at the bottom of the active screen,
/// hosting SwiftUI content with vibrancy, and the show/hide slide animation.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private let viewModel: ClipsViewModel
    private let frontmost = FrontmostTracker()
    private(set) var isVisible: Bool = false

    /// Panel size — matches Stripe layout's intended footprint.
    static let panelSize = NSSize(width: 980, height: 320)
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
        guard isVisible else { return }
        let target = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height - 16)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
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
        hide()
        // Slight delay so the panel has time to fade out before keystroke posts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Paster.paste(into: target)
        }
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
            self?.hide()
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

/// Top-level panel content — header strip + Stripe layout (or empty state).
private struct PanelContentView: View {
    @ObservedObject var viewModel: ClipsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
    }

    private var header: some View {
        HStack {
            Text("Magpie")
                .font(.system(size: 14, weight: .bold))
            Spacer()
            Text("\(viewModel.clips.count) clip\(viewModel.clips.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.clips.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("No clips yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Copy something — text, code, a link, or a folder path — to get started.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            StripeLayout(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
