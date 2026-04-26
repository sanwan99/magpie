import SwiftUI

/// Vertical, single-line-per-clip layout per spec §08.
/// 4 columns: ⌘N · type icon · title + meta · mini preview.
/// Highest information density of the three layouts.
struct StackLayout: View {
    let viewModel: ClipsViewModel
    @State private var tapState = TapState()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        StackRow(
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                guard let id = viewModel.clip(at: newIndex)?.id else { return }
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }
}

private struct StackRow: View {
    let clip: ClipDisplayItem
    let isFocused: Bool
    let shortcutNumber: Int?

    private let settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 12) {
            // Column 1 — ⌘N badge (fixed-width slot so columns align even when nil)
            shortcutBadge
                .frame(width: 32, alignment: .leading)

            // Column 2 — type icon
            Image(systemName: typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            // Column 3 — title + meta. Layout priority 1 so it claims base
            // share; mini preview gets the remainder.
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title ?? typeLabel)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(metaLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            // Column 4 — mini preview. Flexes to fit; layout priority 2 so it
            // claims more remaining space than the title column when wide,
            // but truncates gracefully when the panel narrows.
            miniPreview
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(2)

            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isFocused ? settings.flavor.tokens.focusBg : Color.clear)
        )
    }

    @ViewBuilder
    private var shortcutBadge: some View {
        if let n = shortcutNumber {
            Text("⌘\(n)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.72))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
        } else {
            Color.clear.frame(height: 1)
        }
    }

    @ViewBuilder
    private var miniPreview: some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        case .code(let body, _):
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        case .url(let url, _):
            Text(url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        case .folder(let path, let items):
            HStack(spacing: 6) {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text("· \(items)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        case .file(let path, let kind, _):
            HStack(spacing: 6) {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text("· \(kind.uppercased())")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        case .image(let path, let w, let h, let sizeKB):
            HStack(spacing: 6) {
                if let nsimg = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 22)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Text("\(w)×\(h) · \(sizeKB) KB")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        case .unsupported:
            Text("(unsupported)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Helpers

    private var typeIcon: String {
        switch clip.type {
        case .text:   return "text.alignleft"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        case .url:    return "link"
        case .image:  return "photo"
        case .file:   return "doc"
        case .folder: return "folder"
        }
    }

    private var typeLabel: String {
        clip.type.rawValue.capitalized
    }

    private var metaLine: String {
        var parts: [String] = [timeAgo]
        if let app = clip.app, !app.isEmpty {
            parts.append(shortAppLabel(app))
        }
        return parts.joined(separator: " · ")
    }

    private var timeAgo: String {
        let secs = Date().timeIntervalSince(clip.createdAt)
        if secs < 60     { return "now" }
        if secs < 3600   { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86_400))d"
    }

    private func shortAppLabel(_ bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }
}
