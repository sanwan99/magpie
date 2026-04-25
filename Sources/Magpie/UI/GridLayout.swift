import SwiftUI

/// Compact tile grid per spec §08.
/// `repeat(auto-fill, minmax(170px, 1fr))` — tiles flow to fill available width.
/// Best for visual content (images, folders) once those land in v0.3.
struct GridLayout: View {
    let viewModel: ClipsViewModel
    @State private var tapState = TapState()

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 8)
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, clip in
                        GridTile(
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
                .padding(12)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                guard let id = viewModel.clip(at: newIndex)?.id else { return }
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }
}

private struct GridTile: View {
    let clip: ClipDisplayItem
    let isFocused: Bool
    let shortcutNumber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(height: 170, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background.opacity(isFocused ? 0.45 : 0.32))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(isFocused ? 0.18 : 0.06), lineWidth: 0.5)
        )
        .shadow(
            color: Color.black.opacity(isFocused ? 0.10 : 0.03),
            radius: isFocused ? 5 : 1,
            x: 0,
            y: isFocused ? 2 : 1
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            if let n = shortcutNumber {
                Text("⌘\(n)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            Image(systemName: typeIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 11))
                .lineLimit(5)
                .lineSpacing(1)
        case .code(let body, _):
            Text(body)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(6)
        case .url(_, let host):
            VStack(alignment: .leading, spacing: 2) {
                Text(host ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let title = clip.title, title != host {
                    Text(title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        case .folder(let path, let items):
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(items) item\(items == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        case .file(let path, let kind, let sizeKB):
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("\(kind.uppercased()) · \(sizeKB) KB")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        case .unsupported:
            Text("(unsupported)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

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
}
