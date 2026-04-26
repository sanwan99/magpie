import SwiftUI

/// Decorative overlay for the Splat flavor — purple ink splatter shapes
/// at the corners and a yellow squid mascot floating in the lower-right.
/// Rendered above the panel content but below interactive elements (search
/// field, cards) — pointer events are disabled so it never blocks clicks.
struct SplatDecorations: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var floatPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Splatters at all four corners. Each one is sized so it's
                // mostly painted into the corner; the panel's cornerRadius
                // clips out the curve, leaving the visible portion looking
                // like ink leaking past the panel's rounded edge.
                // (Real "outside the panel" needs a separate borderless
                // window — out of scope; the corner-clip illusion is enough.)
                SplatterBlob(color: splatterColor, seed: 0)
                    .frame(width: 320, height: 300)
                    .position(x: 0, y: 0)              // top-left
                    .opacity(0.78)

                SplatterBlob(color: splatterColor, seed: 1)
                    .frame(width: 260, height: 240)
                    .position(x: geo.size.width, y: 0) // top-right
                    .opacity(0.72)

                SplatterBlob(color: splatterColor, seed: 2)
                    .frame(width: 280, height: 260)
                    .position(x: 0, y: geo.size.height) // bottom-left
                    .opacity(0.70)

                SplatterBlob(color: splatterColor, seed: 0)
                    .frame(width: 240, height: 220)
                    .position(x: geo.size.width, y: geo.size.height) // bottom-right
                    .opacity(0.65)

                // Mascots tucked into the bottom corners — out of the way of
                // the top bar (search field + Magpie label + toggles) and out
                // of the way of the card scroll body. They peek out of the
                // bottom-padding strip with a slow float.
                Image("SquidYellow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-12))
                    .position(
                        x: 50,
                        y: geo.size.height - 30 + floatPhase
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

                Image("SquidPurple")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(10))
                    .position(
                        x: geo.size.width - 50,
                        y: geo.size.height - 30 - floatPhase
                    )
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floatPhase = -8
            }
        }
    }

    /// Splatter ink color — purple in dark mode (matches squid-purple variant
    /// from prototype), white-tinted purple in light mode.
    private var splatterColor: Color {
        colorScheme == .dark
            ? Color(red: 0.48, green: 0.17, blue: 1.00)  // #7a2bff
            : Color(red: 0.65, green: 0.40, blue: 1.00)  // softer lavender on paper bg
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
