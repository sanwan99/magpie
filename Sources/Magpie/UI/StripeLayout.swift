import SwiftUI

/// Horizontal scrolling stripe of 220×220 ClipPreview cards.
/// Default v0.1 layout per the prototype spec §08.
struct StripeLayout: View {
    let viewModel: ClipsViewModel

    var body: some View {
        // Plain HStack (not LazyHStack) so SwiftUI lays out everything up front,
        // making ScrollViewReader's scrollTo cheap. With @Observable narrowing
        // re-diffs to just this layout, the scroll cost is negligible.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipPreview(
                            clip: clip,
                            isFocused: index == viewModel.focusedIndex,
                            shortcutNumber: index < 9 ? index + 1 : nil
                        )
                            .id(clip.id)
                            // Double tap = focus + paste; declared first so it
                            // wins over the single-tap below.
                            .onTapGesture(count: 2) {
                                viewModel.requestPaste(at: index)
                            }
                            .onTapGesture {
                                viewModel.focusedIndex = index
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                guard let id = viewModel.clip(at: newIndex)?.id else { return }
                // anchor: nil = "scroll only as far as needed to be visible"
                // — much cheaper than .center, and avoids unnecessary scrolling
                // when the focused card is already on screen.
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }
}
