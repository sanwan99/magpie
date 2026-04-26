import SwiftUI

/// Top-bar search field with magnifier icon and right-side `visible / total` counter.
/// Auto-focuses on appear so ⌘P → typing immediately filters.
struct SearchField: View {
    @Bindable var viewModel: ClipsViewModel
    @FocusState private var focused: Bool
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(settings.flavor == .splat ? splatCream.opacity(0.8) : Color.secondary)

            TextField("", text: $viewModel.searchInput)
                .textFieldStyle(.plain)
                .font(.system(size: settings.flavor == .splat ? 14 : 13, weight: settings.flavor == .splat ? .semibold : .regular))
                .foregroundStyle(settings.flavor == .splat ? splatCream : Color.primary)
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
                .foregroundStyle(settings.flavor == .splat ? splatCream.opacity(0.72) : Color.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, settings.flavor == .splat ? 7 : 6)
        .background(
            RoundedRectangle(cornerRadius: settings.flavor == .splat ? 18 : 999)
                .fill(searchBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: settings.flavor == .splat ? 18 : 999)
                .strokeBorder(
                    settings.flavor == .splat ? splatYellow : searchBorder,
                    lineWidth: settings.flavor == .splat ? 2 : 0.5
                )
        )
        .onAppear {
            // Focus the field on first show; subsequent ⌘P calls also reset focus.
            focused = true
        }
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var searchBackground: Color {
        if settings.flavor == .splat {
            return splatCard
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.60)
    }

    private var searchBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.06)
    }

    private var splatCard: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.04, blue: 0.23).opacity(0.94)
            : Color(red: 1.00, green: 0.99, blue: 0.90)
    }
    private var splatCream: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}
