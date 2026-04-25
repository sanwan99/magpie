import SwiftUI

/// Horizontal scrolling stripe of 220×220 ClipPreview cards.
/// Default v0.1 layout per the prototype spec §08.
struct StripeLayout: View {
    @ObservedObject var viewModel: ClipsViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        ClipPreview(clip: clip, isFocused: index == viewModel.focusedIndex)
                            .id(clip.id)
                            // Double tap = focus + paste; declared first so it wins
                            // over the single-tap below.
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
                if let id = viewModel.clip(at: newIndex)?.id {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .onChange(of: viewModel.clips.first?.id) { _, _ in
                viewModel.focusedIndex = 0
                if let head = viewModel.clips.first?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(head, anchor: .leading)
                    }
                }
            }
        }
    }
}
