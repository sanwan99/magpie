import AppKit
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
            let leftPosition = mascotPosition(
                for: spec.left,
                side: .left,
                width: geo.size.width,
                floatOffset: floatPhase
            )
            let rightPosition = mascotPosition(
                for: spec.right,
                side: .right,
                width: geo.size.width,
                floatOffset: -floatPhase
            )

            ZStack {
                AmbientMarks(spec: spec)
                    .opacity(spec.ambientOpacity)

                CornerMascot(spec: spec.left)
                    .frame(width: spec.left.size, height: spec.left.size)
                    .rotationEffect(.degrees(spec.left.rotation))
                    .position(leftPosition)
                    .shadow(color: spec.shadow, radius: 12, x: 0, y: 7)

                CornerMascot(spec: spec.right)
                    .frame(width: spec.right.size, height: spec.right.size)
                    .rotationEffect(.degrees(spec.right.rotation))
                    .position(rightPosition)
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

    private func mascotPosition(
        for mascot: PrototypeBadgeSpec,
        side: PrototypeMascotSide,
        width: CGFloat,
        floatOffset: CGFloat
    ) -> CGPoint {
        let edgeInset: CGFloat = 66
        let topSafeInset: CGFloat = 32
        let x: CGFloat
        switch side {
        case .left:
            x = edgeInset
        case .right:
            x = width - edgeInset
        }
        let y = topSafeInset + mascot.size / 2 + floatOffset
        return CGPoint(x: x, y: y)
    }
}

private enum PrototypeMascotSide {
    case left
    case right
}

private struct CornerMascot: View {
    let spec: PrototypeBadgeSpec

    var body: some View {
        if let image = NSImage(named: spec.assetName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            FallbackMascot(spec: spec)
        }
    }
}

private struct FallbackMascot: View {
    let spec: PrototypeBadgeSpec

    var body: some View {
        let paint = PrototypeMascotPaint(kind: spec.mascot, fallbackAccent: spec.accent)
        ZStack {
            Circle()
                .fill(paint.halo)
                .scaleEffect(0.92)
                .offset(x: paint.haloOffset.width, y: paint.haloOffset.height)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(spec.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(spec.border.opacity(0.78), lineWidth: 1.0)
                )
                .opacity(0.54)
                .scaleEffect(x: 0.82, y: 0.78)
                .rotationEffect(.degrees(paint.panelTilt))

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Capsule()
                        .fill(paint.outfit)
                        .frame(width: side * 0.48, height: side * 0.40)
                        .overlay(
                            Capsule()
                                .strokeBorder(paint.outfitStroke, lineWidth: side * 0.018)
                        )
                        .offset(y: side * 0.27)

                    MascotHair(style: paint.hairStyle, color: paint.hair, accent: paint.accent)
                        .frame(width: side * 0.54, height: side * 0.50)
                        .offset(y: -side * 0.10)

                    Circle()
                        .fill(paint.skin)
                        .frame(width: side * 0.35, height: side * 0.35)
                        .overlay(
                            Circle()
                                .strokeBorder(paint.faceStroke, lineWidth: side * 0.012)
                        )
                        .offset(y: side * 0.02)

                    HStack(spacing: side * 0.075) {
                        Circle().fill(paint.eye)
                        Circle().fill(paint.eye)
                    }
                    .frame(width: side * 0.22, height: side * 0.032)
                    .offset(y: side * 0.01)

                    Capsule()
                        .fill(paint.eye.opacity(0.55))
                        .frame(width: side * 0.08, height: side * 0.012)
                        .offset(y: side * 0.09)

                    MascotAccessory(kind: paint.accessory, color: paint.accent, dark: paint.eye)
                        .frame(width: side * 0.34, height: side * 0.34)
                        .offset(x: paint.accessoryOffset.width * side, y: paint.accessoryOffset.height * side)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MascotHair: View {
    let style: HairStyle
    let color: Color
    let accent: Color

    var body: some View {
        ZStack {
            switch style {
            case .cap:
                Capsule()
                    .fill(color)
                    .frame(width: 70, height: 46)
                    .offset(y: -4)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: -18, y: -24)
            case .long:
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(color)
                    .frame(width: 68, height: 82)
                    .offset(y: 6)
                Capsule()
                    .fill(color.opacity(0.92))
                    .frame(width: 74, height: 34)
                    .offset(y: -18)
            case .horns:
                Capsule()
                    .fill(color)
                    .frame(width: 62, height: 54)
                HStack(spacing: 34) {
                    Capsule().fill(accent)
                    Capsule().fill(accent)
                }
                .frame(width: 84, height: 36)
                .rotationEffect(.degrees(-8))
                .offset(y: -22)
            case .bob:
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(color)
                    .frame(width: 66, height: 66)
                    .offset(y: 2)
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: 72, height: 28)
                    .offset(y: -22)
            case .ribbon:
                Capsule()
                    .fill(color)
                    .frame(width: 64, height: 44)
                    .offset(y: -6)
                Image(systemName: "bowtie")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: -18, y: -28)
            case .swept:
                Capsule()
                    .fill(color)
                    .frame(width: 68, height: 48)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -4, y: -8)
                Capsule()
                    .fill(color.opacity(0.88))
                    .frame(width: 30, height: 58)
                    .offset(x: 24, y: 8)
            case .crown:
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(color)
                    .frame(width: 68, height: 70)
                    .offset(y: 8)
                Image(systemName: "crown.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(y: -30)
            }
        }
    }
}

private struct MascotAccessory: View {
    let kind: MascotAccessoryKind
    let color: Color
    let dark: Color

    var body: some View {
        switch kind {
        case .tiara:
            Image(systemName: "crown.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
        case .needle:
            Image(systemName: "needle")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(-28))
        case .staff:
            Image(systemName: "wand.and.stars")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(color)
        case .book:
            Image(systemName: "book.closed.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(color)
        case .star:
            Image(systemName: "star.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(color)
        case .glasses:
            Image(systemName: "eyeglasses")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(dark)
        case .pilot:
            Image(systemName: "bolt.fill")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(color)
        case .scope:
            Image(systemName: "scope")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(color)
        case .staple:
            Image(systemName: "paperclip")
                .font(.system(size: 29, weight: .bold))
                .foregroundStyle(color)
        case .ring:
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

private enum PrototypeMascotKind {
    case forestLeft
    case forestRight
    case huskLeft
    case huskRight
    case mistLeft
    case mistRight
    case clubLeft
    case clubRight
    case unitLeft
    case unitRight
    case inkLeft
    case inkRight
    case giltLeft
    case giltRight
}

private enum HairStyle {
    case cap
    case long
    case horns
    case bob
    case ribbon
    case swept
    case crown
}

private enum MascotAccessoryKind {
    case tiara
    case needle
    case staff
    case book
    case star
    case glasses
    case pilot
    case scope
    case staple
    case ring
}

private struct PrototypeMascotPaint {
    let skin: Color
    let hair: Color
    let outfit: Color
    let outfitStroke: Color
    let eye: Color
    let faceStroke: Color
    let accent: Color
    let halo: Color
    let hairStyle: HairStyle
    let accessory: MascotAccessoryKind
    let accessoryOffset: CGSize
    let haloOffset: CGSize
    let panelTilt: Double

    init(kind: PrototypeMascotKind, fallbackAccent: Color) {
        let ivory = Color(red: 0.98, green: 0.85, blue: 0.68)
        let pale = Color(red: 0.95, green: 0.82, blue: 0.78)
        let porcelain = Color(red: 0.98, green: 0.90, blue: 0.84)
        let ink = Color(red: 0.09, green: 0.09, blue: 0.12)

        switch kind {
        case .forestLeft:
            self.init(
                skin: ivory,
                hair: Color(red: 0.22, green: 0.44, blue: 0.22),
                outfit: Color(red: 0.13, green: 0.48, blue: 0.25),
                outfitStroke: Color(red: 0.75, green: 0.68, blue: 0.30),
                eye: ink,
                faceStroke: Color(red: 0.18, green: 0.30, blue: 0.14).opacity(0.42),
                accent: Color(red: 0.95, green: 0.82, blue: 0.26),
                halo: fallbackAccent.opacity(0.22),
                hairStyle: .cap,
                accessory: .staple,
                accessoryOffset: CGSize(width: 0.24, height: -0.02),
                haloOffset: CGSize(width: -7, height: 7),
                panelTilt: -12
            )
        case .forestRight:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.96, green: 0.76, blue: 0.32),
                outfit: Color(red: 0.40, green: 0.72, blue: 0.56),
                outfitStroke: Color(red: 0.84, green: 0.66, blue: 0.30),
                eye: Color(red: 0.12, green: 0.20, blue: 0.19),
                faceStroke: Color(red: 0.45, green: 0.32, blue: 0.16).opacity(0.34),
                accent: Color(red: 0.98, green: 0.78, blue: 0.24),
                halo: fallbackAccent.opacity(0.25),
                hairStyle: .long,
                accessory: .tiara,
                accessoryOffset: CGSize(width: 0.16, height: -0.22),
                haloOffset: CGSize(width: 8, height: -4),
                panelTilt: 9
            )
        case .huskLeft:
            self.init(
                skin: Color(red: 0.96, green: 0.94, blue: 0.88),
                hair: Color(red: 0.10, green: 0.10, blue: 0.12),
                outfit: Color(red: 0.12, green: 0.13, blue: 0.15),
                outfitStroke: Color.white.opacity(0.62),
                eye: Color.black.opacity(0.85),
                faceStroke: Color.white.opacity(0.45),
                accent: Color(red: 0.92, green: 0.92, blue: 0.82),
                halo: fallbackAccent.opacity(0.22),
                hairStyle: .horns,
                accessory: .ring,
                accessoryOffset: CGSize(width: 0.24, height: 0.08),
                haloOffset: CGSize(width: -8, height: 2),
                panelTilt: -7
            )
        case .huskRight:
            self.init(
                skin: Color(red: 0.98, green: 0.92, blue: 0.86),
                hair: Color(red: 0.88, green: 0.15, blue: 0.16),
                outfit: Color(red: 0.72, green: 0.05, blue: 0.08),
                outfitStroke: Color(red: 0.98, green: 0.80, blue: 0.75),
                eye: ink,
                faceStroke: Color(red: 0.50, green: 0.05, blue: 0.07).opacity(0.36),
                accent: Color(red: 0.96, green: 0.88, blue: 0.68),
                halo: fallbackAccent.opacity(0.28),
                hairStyle: .horns,
                accessory: .needle,
                accessoryOffset: CGSize(width: 0.23, height: 0.08),
                haloOffset: CGSize(width: 7, height: -3),
                panelTilt: 8
            )
        case .mistLeft:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.87, green: 0.88, blue: 0.78),
                outfit: Color(red: 0.56, green: 0.74, blue: 0.52),
                outfitStroke: Color(red: 0.92, green: 0.88, blue: 0.58),
                eye: Color(red: 0.11, green: 0.24, blue: 0.18),
                faceStroke: Color(red: 0.40, green: 0.55, blue: 0.38).opacity(0.36),
                accent: Color(red: 0.94, green: 0.88, blue: 0.54),
                halo: fallbackAccent.opacity(0.22),
                hairStyle: .long,
                accessory: .staff,
                accessoryOffset: CGSize(width: 0.25, height: 0.02),
                haloOffset: CGSize(width: -7, height: 3),
                panelTilt: -8
            )
        case .mistRight:
            self.init(
                skin: pale,
                hair: Color(red: 0.43, green: 0.31, blue: 0.53),
                outfit: Color(red: 0.64, green: 0.52, blue: 0.73),
                outfitStroke: Color(red: 0.86, green: 0.76, blue: 0.92),
                eye: Color(red: 0.12, green: 0.10, blue: 0.18),
                faceStroke: Color(red: 0.38, green: 0.29, blue: 0.52).opacity(0.34),
                accent: Color(red: 0.93, green: 0.84, blue: 0.58),
                halo: fallbackAccent.opacity(0.24),
                hairStyle: .bob,
                accessory: .book,
                accessoryOffset: CGSize(width: 0.25, height: 0.10),
                haloOffset: CGSize(width: 8, height: 1),
                panelTilt: 7
            )
        case .clubLeft:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.54, green: 0.29, blue: 0.16),
                outfit: Color(red: 0.76, green: 0.30, blue: 0.22),
                outfitStroke: Color(red: 0.96, green: 0.82, blue: 0.30),
                eye: ink,
                faceStroke: Color(red: 0.45, green: 0.23, blue: 0.12).opacity(0.34),
                accent: Color(red: 0.98, green: 0.79, blue: 0.22),
                halo: fallbackAccent.opacity(0.24),
                hairStyle: .ribbon,
                accessory: .star,
                accessoryOffset: CGSize(width: 0.25, height: 0.02),
                haloOffset: CGSize(width: -7, height: -3),
                panelTilt: -8
            )
        case .clubRight:
            self.init(
                skin: pale,
                hair: Color(red: 0.23, green: 0.38, blue: 0.56),
                outfit: Color(red: 0.36, green: 0.48, blue: 0.70),
                outfitStroke: Color(red: 0.78, green: 0.84, blue: 0.96),
                eye: Color(red: 0.06, green: 0.10, blue: 0.18),
                faceStroke: Color(red: 0.22, green: 0.34, blue: 0.52).opacity(0.36),
                accent: Color(red: 0.88, green: 0.80, blue: 0.96),
                halo: fallbackAccent.opacity(0.22),
                hairStyle: .bob,
                accessory: .book,
                accessoryOffset: CGSize(width: 0.24, height: 0.10),
                haloOffset: CGSize(width: 7, height: 2),
                panelTilt: 7
            )
        case .unitLeft:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.92, green: 0.28, blue: 0.08),
                outfit: Color(red: 0.78, green: 0.18, blue: 0.10),
                outfitStroke: Color(red: 0.98, green: 0.75, blue: 0.25),
                eye: ink,
                faceStroke: Color(red: 0.56, green: 0.12, blue: 0.08).opacity(0.32),
                accent: Color(red: 0.98, green: 0.82, blue: 0.24),
                halo: fallbackAccent.opacity(0.28),
                hairStyle: .swept,
                accessory: .pilot,
                accessoryOffset: CGSize(width: 0.24, height: 0.06),
                haloOffset: CGSize(width: -8, height: 0),
                panelTilt: -6
            )
        case .unitRight:
            self.init(
                skin: pale,
                hair: Color(red: 0.55, green: 0.76, blue: 0.88),
                outfit: Color(red: 0.68, green: 0.78, blue: 0.90),
                outfitStroke: Color(red: 0.88, green: 0.94, blue: 1.00),
                eye: Color(red: 0.08, green: 0.12, blue: 0.18),
                faceStroke: Color(red: 0.42, green: 0.58, blue: 0.72).opacity(0.34),
                accent: Color(red: 0.72, green: 0.95, blue: 1.00),
                halo: fallbackAccent.opacity(0.22),
                hairStyle: .bob,
                accessory: .scope,
                accessoryOffset: CGSize(width: 0.24, height: 0.08),
                haloOffset: CGSize(width: 8, height: -1),
                panelTilt: 6
            )
        case .inkLeft:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.38, green: 0.27, blue: 0.56),
                outfit: Color(red: 0.30, green: 0.22, blue: 0.48),
                outfitStroke: Color(red: 0.84, green: 0.72, blue: 0.96),
                eye: ink,
                faceStroke: Color(red: 0.32, green: 0.23, blue: 0.46).opacity(0.34),
                accent: Color(red: 0.86, green: 0.68, blue: 0.98),
                halo: fallbackAccent.opacity(0.24),
                hairStyle: .swept,
                accessory: .staple,
                accessoryOffset: CGSize(width: 0.23, height: 0.06),
                haloOffset: CGSize(width: -7, height: 2),
                panelTilt: -8
            )
        case .inkRight:
            self.init(
                skin: pale,
                hair: Color(red: 0.12, green: 0.13, blue: 0.18),
                outfit: Color(red: 0.72, green: 0.67, blue: 0.84),
                outfitStroke: Color(red: 0.92, green: 0.86, blue: 0.98),
                eye: Color(red: 0.05, green: 0.06, blue: 0.09),
                faceStroke: Color(red: 0.18, green: 0.18, blue: 0.24).opacity(0.34),
                accent: Color(red: 0.82, green: 0.74, blue: 0.96),
                halo: fallbackAccent.opacity(0.20),
                hairStyle: .bob,
                accessory: .glasses,
                accessoryOffset: CGSize(width: 0.00, height: 0.02),
                haloOffset: CGSize(width: 7, height: 2),
                panelTilt: 6
            )
        case .giltLeft:
            self.init(
                skin: porcelain,
                hair: Color(red: 0.96, green: 0.80, blue: 0.38),
                outfit: Color(red: 0.78, green: 0.30, blue: 0.16),
                outfitStroke: Color(red: 0.98, green: 0.86, blue: 0.46),
                eye: ink,
                faceStroke: Color(red: 0.46, green: 0.24, blue: 0.12).opacity(0.32),
                accent: Color(red: 0.98, green: 0.82, blue: 0.25),
                halo: fallbackAccent.opacity(0.28),
                hairStyle: .crown,
                accessory: .ring,
                accessoryOffset: CGSize(width: 0.24, height: 0.08),
                haloOffset: CGSize(width: -8, height: -1),
                panelTilt: -7
            )
        case .giltRight:
            self.init(
                skin: pale,
                hair: Color(red: 0.08, green: 0.08, blue: 0.10),
                outfit: Color(red: 0.88, green: 0.68, blue: 0.32),
                outfitStroke: Color(red: 0.98, green: 0.88, blue: 0.56),
                eye: Color(red: 0.05, green: 0.05, blue: 0.07),
                faceStroke: Color(red: 0.20, green: 0.16, blue: 0.10).opacity(0.34),
                accent: Color(red: 0.98, green: 0.82, blue: 0.26),
                halo: fallbackAccent.opacity(0.24),
                hairStyle: .bob,
                accessory: .ring,
                accessoryOffset: CGSize(width: 0.24, height: 0.10),
                haloOffset: CGSize(width: 8, height: 0),
                panelTilt: 6
            )
        }
    }

    private init(
        skin: Color,
        hair: Color,
        outfit: Color,
        outfitStroke: Color,
        eye: Color,
        faceStroke: Color,
        accent: Color,
        halo: Color,
        hairStyle: HairStyle,
        accessory: MascotAccessoryKind,
        accessoryOffset: CGSize,
        haloOffset: CGSize,
        panelTilt: Double
    ) {
        self.skin = skin
        self.hair = hair
        self.outfit = outfit
        self.outfitStroke = outfitStroke
        self.eye = eye
        self.faceStroke = faceStroke
        self.accent = accent
        self.halo = halo
        self.hairStyle = hairStyle
        self.accessory = accessory
        self.accessoryOffset = accessoryOffset
        self.haloOffset = haloOffset
        self.panelTilt = panelTilt
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
            self.left = PrototypeBadgeSpec(symbol: "leaf.fill", secondarySymbol: "circle.hexagonpath.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -9, size: 156, assetName: "ThemeForestLeft", mascot: .forestLeft)
            self.right = PrototypeBadgeSpec(symbol: "sparkles", secondarySymbol: "diamond.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 7, size: 154, assetName: "ThemeForestRight", mascot: .forestRight)
        case .husk:
            self.kind = .husk
            self.ambientOpacity = 0.86
            self.left = PrototypeBadgeSpec(symbol: "shield.fill", secondarySymbol: "circle.fill", background: soft, foreground: fg, accent: glow, badgeBackground: badge, border: border, rotation: -6, size: 150, assetName: "ThemeHuskLeft", mascot: .huskLeft)
            self.right = PrototypeBadgeSpec(symbol: "needle", secondarySymbol: "circle.fill", background: focus, foreground: fg, accent: glow, badgeBackground: badge, border: border, rotation: 6, size: 150, assetName: "ThemeHuskRight", mascot: .huskRight)
        case .mist:
            self.kind = .mist
            self.ambientOpacity = 0.90
            self.left = PrototypeBadgeSpec(symbol: "wand.and.stars", secondarySymbol: "moon.stars.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -6, size: 154, assetName: "ThemeMistLeft", mascot: .mistLeft)
            self.right = PrototypeBadgeSpec(symbol: "book.closed.fill", secondarySymbol: "sparkle", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 6, size: 150, assetName: "ThemeMistRight", mascot: .mistRight)
        case .club:
            self.kind = .club
            self.ambientOpacity = 0.94
            self.left = PrototypeBadgeSpec(symbol: "star.fill", secondarySymbol: "megaphone.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -7, size: 154, assetName: "ThemeClubLeft", mascot: .clubLeft)
            self.right = PrototypeBadgeSpec(symbol: "sparkles", secondarySymbol: "circle.grid.2x2.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 6, size: 150, assetName: "ThemeClubRight", mascot: .clubRight)
        case .unit:
            self.kind = .unit
            self.ambientOpacity = 0.72
            self.left = PrototypeBadgeSpec(symbol: "exclamationmark.triangle.fill", secondarySymbol: "bolt.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -5, size: 154, assetName: "ThemeUnitLeft", mascot: .unitLeft)
            self.right = PrototypeBadgeSpec(symbol: "scope", secondarySymbol: "circle.fill", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 5, size: 154, assetName: "ThemeUnitRight", mascot: .unitRight)
        case .ink:
            self.kind = .ink
            self.ambientOpacity = 0.82
            self.left = PrototypeBadgeSpec(symbol: "scissors", secondarySymbol: "paperclip", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -6, size: 150, assetName: "ThemeInkLeft", mascot: .inkLeft)
            self.right = PrototypeBadgeSpec(symbol: "book.closed.fill", secondarySymbol: "eyeglasses", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 5, size: 150, assetName: "ThemeInkRight", mascot: .inkRight)
        case .gilt:
            self.kind = .gilt
            self.ambientOpacity = 0.90
            self.left = PrototypeBadgeSpec(symbol: "crown.fill", secondarySymbol: "circle.circle.fill", background: focus, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: -6, size: 152, assetName: "ThemeGiltLeft", mascot: .giltLeft)
            self.right = PrototypeBadgeSpec(symbol: "circle.circle.fill", secondarySymbol: "sparkles", background: soft, foreground: fg, accent: accent, badgeBackground: badge, border: border, rotation: 5, size: 150, assetName: "ThemeGiltRight", mascot: .giltRight)
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
    let assetName: String
    let mascot: PrototypeMascotKind
}
