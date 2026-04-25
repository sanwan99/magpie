import SwiftUI

/// Horizontal scrolling stripe of 220×220 ClipPreview cards.
/// Default v0.1 layout per the prototype spec §08.
struct StripeLayout: View {
    let viewModel: ClipsViewModel
    @State private var tapState = TapState()
    // (TapState is a class; @State holds it across body recomputations.)

    var body: some View {
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
                            .onTapGesture {
                                handleTap(index: index, viewModel: viewModel, state: tapState)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                guard let id = viewModel.clip(at: newIndex)?.id else { return }
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }
}
