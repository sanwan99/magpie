import AppKit
import SwiftUI

/// Owns the lifecycle of the Magpie panel: positioning at the bottom of the active screen,
/// hosting SwiftUI content with vibrancy, and the show/hide slide animation.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private(set) var isVisible: Bool = false

    /// Panel size — matches Stripe layout's intended footprint.
    static let panelSize = NSSize(width: 980, height: 320)
    /// Distance from the bottom of the active screen.
    static let bottomInset: CGFloat = 24

    init() {
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        self.panel = PanelWindow(contentRect: frame)
        self.panel.contentView = makeContentView()
        self.panel.onCancel = { [weak self] in
            self?.hide()
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

    // MARK: - Layout

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let x = visible.midX - size.width / 2
        let y = visible.minY + Self.bottomInset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    // MARK: - Content

    private func makeContentView() -> NSView {
        let host = NSHostingView(rootView: PanelContentView())
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

/// Placeholder content shown inside the panel during v0.1 first/second steps.
/// Replaced by Stripe layout in step 7.
private struct PanelContentView: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("Magpie")
                .font(.system(size: 22, weight: .bold))
            Text("⌘P toggles · Esc hides · v0.1 skeleton")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
