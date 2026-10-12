import AppKit
import SwiftUI

/// SwiftUI wrapper around NSVisualEffectView so the panel can use native vibrancy.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// Keeps one hosting view alive when switching between native Liquid Glass
/// and the original behind-window vibrancy. Layout and keyboard wiring stay
/// attached to the same panel and view models.
@MainActor
final class PanelMaterialView: NSView {
    private let hostedView: NSView
    private let vibrancyView = NSVisualEffectView()
    private var nativeGlassView: NSView?

    init(content: NSView, frame: NSRect) {
        hostedView = content
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.masksToBounds = true

        vibrancyView.frame = bounds
        vibrancyView.blendingMode = .behindWindow
        vibrancyView.state = .active
        vibrancyView.isEmphasized = true
        vibrancyView.autoresizingMask = [.width, .height]
        addSubview(vibrancyView)

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = 22
            glass.autoresizingMask = [.width, .height]
            glass.isHidden = true
            addSubview(glass)
            nativeGlassView = glass
        }
        #endif

        hostedView.frame = bounds
        hostedView.autoresizingMask = [.width, .height]
        addSubview(hostedView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func prepareContent() {
        hostedView.needsLayout = true
        hostedView.layoutSubtreeIfNeeded()
        if let bitmap = hostedView.bitmapImageRepForCachingDisplay(in: hostedView.bounds) {
            hostedView.cacheDisplay(in: hostedView.bounds, to: bitmap)
        }
    }

    func update(surface: PanelSurface, material: NSVisualEffectView.Material) {
        vibrancyView.material = material
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = nativeGlassView as? NSGlassEffectView {
            let useGlass = surface == .liquidGlass && !reduceTransparency
            if useGlass {
                if glass.contentView !== hostedView {
                    let responder = window?.firstResponder
                    hostedView.removeFromSuperview()
                    hostedView.frame = glass.bounds
                    glass.contentView = hostedView
                    if let responder { window?.makeFirstResponder(responder) }
                }
            } else if glass.contentView === hostedView {
                let responder = window?.firstResponder
                glass.contentView = nil
                hostedView.frame = bounds
                addSubview(hostedView)
                if let responder { window?.makeFirstResponder(responder) }
            }
            glass.isHidden = !useGlass
            vibrancyView.isHidden = useGlass
            return
        }
        #endif

        vibrancyView.isHidden = false
    }
}

struct LiquidGlassSearchChrome: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), enabled {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Subtle compatible rim for older systems; actual refraction is provided by
/// NSGlassEffectView on macOS 26, rather than by this decorative stroke.
struct PanelGlassRim: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.42 : 0.85),
                        .white.opacity(0.08),
                        .black.opacity(colorScheme == .dark ? 0.18 : 0.08),
                        .white.opacity(0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
    }
}
