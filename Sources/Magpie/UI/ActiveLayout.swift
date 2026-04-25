import Foundation

/// Three panel layouts per prototype spec §08.
/// `Stripe` is the default; `Stack` favors information density; `Grid` favors visual scanning.
enum ActiveLayout: String, CaseIterable, Sendable {
    case stripe
    case stack
    case grid

    /// `⌘\` cycles stripe → stack → grid → stripe.
    var next: ActiveLayout {
        switch self {
        case .stripe: return .stack
        case .stack:  return .grid
        case .grid:   return .stripe
        }
    }

    var displayName: String {
        switch self {
        case .stripe: return "Stripe"
        case .stack:  return "Stack"
        case .grid:   return "Grid"
        }
    }
}
