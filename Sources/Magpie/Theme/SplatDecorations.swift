import SwiftUI

/// Decorative overlay for the Splat flavor.
///
/// The browser prototype draws the squids outside the panel via fixed DOM
/// elements. A borderless NSPanel cannot render outside its own window frame,
/// so this layer recreates the same visual priority inside the panel:
/// top-corner squids and a few small splats that stay behind the UI.
struct SplatDecorations: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var floatPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SplatterBlob(color: purpleInk, seed: 1)
                    .frame(width: 110, height: 52)
                    .rotationEffect(.degrees(-8))
                    .position(x: geo.size.width - 150, y: 102)
                    .opacity(0.86)

                SplatterBlob(color: yellowInk, seed: 2)
                    .frame(width: 126, height: 58)
                    .rotationEffect(.degrees(7))
                    .position(x: 90, y: geo.size.height - 78)
                    .opacity(0.68)

                Image("SquidYellow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-12))
                    .position(
                        x: 66,
                        y: 48 + floatPhase
                    )
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)

                Image("SquidPurple")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 146, height: 146)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(9))
                    .position(
                        x: geo.size.width - 64,
                        y: 48 - floatPhase
                    )
                    .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 5)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floatPhase = -8
            }
        }
    }

    private var purpleInk: Color {
        colorScheme == .dark
            ? Color(red: 0.48, green: 0.17, blue: 1.00)
            : Color(red: 0.61, green: 0.30, blue: 1.00)
    }

    private var yellowInk: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.91, blue: 0.00)
            : Color(red: 1.00, green: 0.84, blue: 0.10)
    }

}

/// An organic ink-splat shape built from a few overlapping circles + drips.
/// `seed` varies the geometry so different instances look different.
private struct SplatterBlob: View {
    let color: Color
    let seed: Int

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2

            // Big main blob
            context.fill(
                Path(ellipseIn: CGRect(x: cx - w * 0.30, y: cy - h * 0.28,
                                        width: w * 0.60, height: h * 0.56)),
                with: .color(color)
            )

            // Several satellite drops around it — positions vary by seed
            let drops: [(CGFloat, CGFloat, CGFloat, CGFloat)] = seedVariants[seed % seedVariants.count]
            for (rx, ry, rw, rh) in drops {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: cx + w * rx,
                        y: cy + h * ry,
                        width: w * rw,
                        height: h * rh
                    )),
                    with: .color(color)
                )
            }
        }
    }

    /// Pre-baked drop layouts. Each tuple is (x-offset, y-offset, width, height)
    /// as a fraction of the canvas — randomness frozen so reruns look identical.
    private var seedVariants: [[(CGFloat, CGFloat, CGFloat, CGFloat)]] {
        [
            [
                (-0.40, -0.20, 0.18, 0.18),
                ( 0.30, -0.30, 0.14, 0.14),
                ( 0.40,  0.20, 0.10, 0.10),
                (-0.20,  0.35, 0.16, 0.14),
                ( 0.10,  0.45, 0.08, 0.07),
            ],
            [
                ( 0.35,  0.10, 0.15, 0.15),
                (-0.40, -0.10, 0.13, 0.12),
                ( 0.10, -0.40, 0.12, 0.12),
                (-0.30,  0.40, 0.08, 0.08),
                ( 0.45, -0.30, 0.06, 0.07),
            ],
            [
                (-0.35,  0.20, 0.14, 0.14),
                ( 0.40, -0.05, 0.12, 0.13),
                (-0.20, -0.40, 0.10, 0.10),
                ( 0.15,  0.45, 0.07, 0.07),
                ( 0.30,  0.40, 0.05, 0.05),
            ],
        ]
    }
}

/// Entry point for all decorative flavor chrome.
///
/// Splat keeps the hand-tuned squid layer above. The prototype3 themes use
/// original abstract badges and ambient linework, so the shipped app does not
/// embed third-party logos or character artwork.
struct FlavorDecorations: View {
    let flavor: Flavor

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if flavor == .splat {
            SplatDecorations()
        } else if let spec = PrototypeFlavorSpec(flavor: flavor, colorScheme: colorScheme) {
            PrototypeFlavorDecorations(spec: spec)
        }
    }
}

private struct PrototypeFlavorDecorations: View {
    let spec: PrototypeFlavorSpec
    @State private var floatPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AmbientMarks(spec: spec)
                    .opacity(spec.ambientOpacity)

                CornerBadge(spec: spec.left)
                    .frame(width: spec.left.size, height: spec.left.size)
                    .rotationEffect(.degrees(spec.left.rotation))
                    .position(x: 66, y: 52 + floatPhase)
                    .shadow(color: spec.shadow, radius: 12, x: 0, y: 7)

                CornerBadge(spec: spec.right)
                    .frame(width: spec.right.size, height: spec.right.size)
                    .scaleEffect(x: -1, y: 1)
                    .rotationEffect(.degrees(spec.right.rotation))
                    .position(x: geo.size.width - 66, y: 54 - floatPhase)
                    .shadow(color: spec.shadow, radius: 12, x: 0, y: 7)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                floatPhase = -6
            }
        }
    }
}

private struct CornerBadge: View {
    let spec: PrototypeBadgeSpec

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(spec.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(spec.border, lineWidth: 1.2)
                )

            Image(systemName: spec.symbol)
                .font(.system(size: spec.size * 0.36, weight: .semibold))
                .foregroundStyle(spec.foreground)

            Image(systemName: spec.secondarySymbol)
                .font(.system(size: spec.size * 0.13, weight: .bold))
                .foregroundStyle(spec.accent)
                .padding(7)
                .background(Circle().fill(spec.badgeBackground))
                .overlay(Circle().strokeBorder(spec.border.opacity(0.65), lineWidth: 0.7))
                .offset(x: spec.size * 0.24, y: spec.size * 0.22)
        }
    }
}

private struct AmbientMarks: View {
    let spec: PrototypeFlavorSpec

    var body: some View {
        Canvas { context, size in
            switch spec.kind {
            case .forest:
                var path = Path()
                path.move(to: CGPoint(x: 48, y: 78))
                path.addCurve(
                    to: CGPoint(x: 360, y: 84),
                    control1: CGPoint(x: 120, y: 38),
                    control2: CGPoint(x: 210, y: 112)
                )
                path.move(to: CGPoint(x: size.width - 360, y: 78))
                path.addCurve(
                    to: CGPoint(x: size.width - 40, y: 106),
                    control1: CGPoint(x: size.width - 260, y: 122),
                    control2: CGPoint(x: size.width - 150, y: 54)
                )
                path.move(to: CGPoint(x: 42, y: size.height - 54))
                path.addLine(to: CGPoint(x: size.width - 42, y: size.height - 54))
                context.stroke(path, with: .color(spec.line), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                drawCircle(context, center: CGPoint(x: 90, y: size.height - 72), radius: 26, color: spec.accent.opacity(0.16))

            case .husk:
                var path = Path()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 210, y: 82))
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: 88, y: 210))
                path.move(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width - 210, y: 82))
                path.move(to: CGPoint(x: size.width, y: 0))
                path.addLine(to: CGPoint(x: size.width - 88, y: 210))
                path.move(to: CGPoint(x: 48, y: size.height - 55))
                path.addCurve(
                    to: CGPoint(x: size.width - 48, y: size.height - 55),
                    control1: CGPoint(x: size.width * 0.34, y: size.height - 82),
                    control2: CGPoint(x: size.width * 0.66, y: size.height - 28)
                )
                context.stroke(path, with: .color(spec.line), lineWidth: 0.8)

            case .mist:
                for i in 0..<5 {
                    let radius = CGFloat(46 + i * 24)
                    let rect = CGRect(x: size.width - radius - 86, y: 56 + CGFloat(i * 8), width: radius, height: radius)
                    context.stroke(Path(ellipseIn: rect), with: .color(spec.line), lineWidth: 0.7)
                }
                drawCircle(context, center: CGPoint(x: 88, y: size.height - 82), radius: 36, color: spec.accent.opacity(0.12))

            case .club:
                var path = Path()
                for x in stride(from: CGFloat(70), through: size.width - 70, by: 80) {
                    path.move(to: CGPoint(x: x, y: size.height - 70))
                    path.addLine(to: CGPoint(x: x + 26, y: size.height - 58))
                }
                context.stroke(path, with: .color(spec.line), lineWidth: 1)
                drawCircle(context, center: CGPoint(x: 92, y: 82), radius: 24, color: spec.accent.opacity(0.18))

            case .unit:
                var path = Path()
                for x in stride(from: CGFloat(-120), through: size.width + 120, by: 84) {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + 180, y: 0))
                }
                context.stroke(path, with: .color(spec.line), lineWidth: 0.7)

            case .ink:
                var path = Path()
                for y in stride(from: CGFloat(62), through: size.height - 64, by: 54) {
                    path.move(to: CGPoint(x: 46, y: y))
                    path.addLine(to: CGPoint(x: size.width - 46, y: y + 10))
                }
                context.stroke(path, with: .color(spec.line), style: StrokeStyle(lineWidth: 0.6, dash: [18, 10]))

            case .gilt:
                drawRing(context, center: CGPoint(x: size.width * 0.50, y: 68), radius: 54, color: spec.accent.opacity(0.16))
                drawRing(context, center: CGPoint(x: 106, y: size.height - 78), radius: 30, color: spec.line.opacity(0.35))
                drawRing(context, center: CGPoint(x: size.width - 106, y: size.height - 86), radius: 36, color: spec.accent.opacity(0.14))
            }
        }
    }

    private func drawCircle(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(color)
        )
    }

    private func drawRing(_ context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let innerRadius = radius * 0.42
        let inner = CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2)
        context.stroke(Path(ellipseIn: outer), with: .color(color), lineWidth: 2)
        context.stroke(Path(ellipseIn: inner), with: .color(color.opacity(0.75)), lineWidth: 1)
    }
}

private struct PrototypeFlavorSpec {
    let kind: Kind
    let accent: Color
    let line: Color
    let shadow: Color
    let ambientOpacity: Double
    let left: PrototypeBadgeSpec
    let right: PrototypeBadgeSpec

    init?(flavor: Flavor, colorScheme: ColorScheme) {
        let tokens = flavor.tokens(for: colorScheme)
        let accent = tokens.accent
        let glow = tokens.focusGlowColor ?? tokens.accent
        let border = (tokens.focusStrokeColor ?? tokens.strokeColor).opacity(max(tokens.focusStrokeOpacity, 0.45))
        let line = tokens.strokeColor.opacity(colorScheme == .dark ? 0.34 : 0.24)
        let soft = tokens.cardBgIdle.opacity(colorScheme == .dark ? 0.90 : 0.80)
        let focus = tokens.focusBg
        let fg = colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.74)
        let badge = colorScheme == .dark ? Color.black.opacity(0.62) : Color.white.opacity(0.82)

        self.accent = accent
        self.line = line
        self.shadow = glow.opacity(0.22)

        switch flavor {
        case .forest:
            self.kind = .forest
            self.ambientOpacity = 0.92
            self.left = PrototypeBadgeSpec(symbol: "leaf.fill", secondarySymbol: "circle.hexagonpath.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -11, size: 132)
            self.right = PrototypeBadgeSpec(symbol: "sparkles", secondarySymbol: "diamond.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 9, size: 128)
        case .husk:
            self.kind = .husk
            self.ambientOpacity = 0.86
            self.left = PrototypeBadgeSpec(symbol: "shield.fill", secondarySymbol: "circle.fill", background: soft, foreground: fg, accent: glow, badgeBackground: badge, border: border, rotation: -7, size: 124)
            self.right = PrototypeBadgeSpec(symbol: "needle", secondarySymbol: "circle.fill", background: focus, foreground: fg, accent: glow, badgeBackground: badge, border: border, rotation: 8, size: 124)
        case .mist:
            self.kind = .mist
            self.ambientOpacity = 0.90
            self.left = PrototypeBadgeSpec(symbol: "wand.and.stars", secondarySymbol: "moon.stars.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -8, size: 126)
            self.right = PrototypeBadgeSpec(symbol: "book.closed.fill", secondarySymbol: "sparkle", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 7, size: 122)
        case .club:
            self.kind = .club
            self.ambientOpacity = 0.94
            self.left = PrototypeBadgeSpec(symbol: "star.fill", secondarySymbol: "megaphone.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -9, size: 128)
            self.right = PrototypeBadgeSpec(symbol: "sparkles", secondarySymbol: "circle.grid.2x2.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 8, size: 122)
        case .unit:
            self.kind = .unit
            self.ambientOpacity = 0.72
            self.left = PrototypeBadgeSpec(symbol: "exclamationmark.triangle.fill", secondarySymbol: "bolt.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -6, size: 126)
            self.right = PrototypeBadgeSpec(symbol: "scope", secondarySymbol: "circle.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 7, size: 126)
        case .ink:
            self.kind = .ink
            self.ambientOpacity = 0.82
            self.left = PrototypeBadgeSpec(symbol: "scissors", secondarySymbol: "paperclip", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -8, size: 124)
            self.right = PrototypeBadgeSpec(symbol: "book.closed.fill", secondarySymbol: "eyeglasses", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 6, size: 122)
        case .gilt:
            self.kind = .gilt
            self.ambientOpacity = 0.90
            self.left = PrototypeBadgeSpec(symbol: "crown.fill", secondarySymbol: "circle.circle.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -8, size: 126)
            self.right = PrototypeBadgeSpec(symbol: "circle.circle.fill", secondarySymbol: "sparkles", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 7, size: 122)
        case .mono, .graphite, .blue, .olive, .splat:
            return nil
        }
    }

    enum Kind {
        case forest
        case husk
        case mist
        case club
        case unit
        case ink
        case gilt
    }
}

private struct PrototypeBadgeSpec {
    let symbol: String
    let secondarySymbol: String
    let background: Color
    let foreground: Color
    let accent: Color
    let badgeBackground: Color
    let border: Color
    let rotation: Double
    let size: CGFloat
}
