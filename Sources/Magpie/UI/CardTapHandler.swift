import Foundation
import SwiftUI

/// Per-layout state for manual double-click detection.
///
/// `class` (reference type) on purpose — SwiftUI's `@State` of a struct does
/// not always preserve mutations made through an `inout` parameter from a
/// closure (the closure may capture a stale snapshot). With a class, every
/// caller mutates the same instance, and SwiftUI doesn't need to publish
/// changes for our use (we don't read this from the body).
@MainActor
final class TapState {
    var lastTapAt: Date = .distantPast
    var lastTapIndex: Int = -1
}

/// Single-click vs double-click resolution without paying SwiftUI's
/// `onTapGesture(count: 2)` arbitration delay (which can take 250-500 ms,
/// far longer than the user's perception of "instant").
///
/// Strategy: every tap fires `.onTapGesture(count: 1)` immediately. We
/// remember `(time, index)` of the last tap. If the next tap on the same card
/// arrives within `doubleTapWindow`, it counts as a double click and we
/// trigger paste. Otherwise it's a single click — focus the card.
///
/// Side effect: the first click of a double-click sequence DOES fire the
/// single-click branch (focus shifts). Then paste happens. Visually fine.
@MainActor
func handleTap(
    index: Int,
    viewModel: ClipsViewModel,
    state: TapState
) {
    let doubleTapWindow: TimeInterval = 0.3
    let now = Date()

    // Same card tapped twice within the window → double click → paste.
    if state.lastTapIndex == index,
       now.timeIntervalSince(state.lastTapAt) < doubleTapWindow {
        NSLog("[tap] double click on index=%d → paste", index)
        viewModel.requestPaste(at: index)
        state.lastTapAt = .distantPast
        state.lastTapIndex = -1
        return
    }

    // Single click — focus immediately.
    NSLog("[tap] single click on index=%d", index)
    if viewModel.detailPaneVisible {
        viewModel.focusedIndex = index
    } else {
        withAnimation(.easeOut(duration: 0.18)) {
            viewModel.focusAndShowDetail(at: index)
        }
    }

    state.lastTapAt = now
    state.lastTapIndex = index
}
