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
