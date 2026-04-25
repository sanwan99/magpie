import SwiftUI

/// Top-bar search field with magnifier icon and right-side `visible / total` counter.
/// Auto-focuses on appear so ⌘P → typing immediately filters.
struct SearchField: View {
    @Bindable var viewModel: ClipsViewModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search clips · type:code  app:vscode  tag:design", text: $viewModel.searchInput)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)

            if !viewModel.searchInput.isEmpty {
                Button {
                    viewModel.searchInput = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("\(viewModel.clips.count) / \(viewModel.totalClipCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(.background.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        )
        .onAppear {
            // Focus the field on first show; subsequent ⌘P calls also reset focus.
            focused = true
        }
    }
}
