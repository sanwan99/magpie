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

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let t = settings.flavor.tokens(for: colorScheme)
        let isSplat = settings.flavor == .splat
        VStack(alignment: .leading, spacing: 6) {
            header
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
        .frame(height: 170, alignment: .topLeading)
        .modifier(GridTileChrome(tokens: t, isFocused: isFocused, isSplat: isSplat))
        .rotationEffect(isSplat ? splatRotation : .degrees(0))
        .environment(\.colorScheme, isSplat && isFocused ? .light : colorScheme)
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
        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 3) {
                // Grid tile 比 Stripe 还小（~150pt），256 缩略图绰绰有余。
                if let nsimg = ImageThumbnail.load(path: path, maxPixelSize: 256) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                }
                Text("\(w)×\(h) · \(sizeKB) KB")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private var splatRotation: Angle {
        if isFocused { return .degrees(-1.2) }
        guard let shortcutNumber else { return .degrees(0.4) }
        return .degrees(shortcutNumber.isMultiple(of: 2) ? 0.7 : -0.6)
    }
}

private struct GridTileChrome: ViewModifier {
    let tokens: FlavorTokens
    let isFocused: Bool
    let isSplat: Bool

    func body(content: Content) -> some View {
        content
            .background(idleShape)
            .background(focusShape)
            .background(shadowShape)
            .overlay(strokeShape)
            .shadow(
                color: isSplat ? .clear : Color.black.opacity(isFocused ? 0.10 : 0.03),
                radius: isFocused ? 5 : 1,
                x: 0,
                y: isFocused ? 2 : 1
            )
    }

    private var shadowShape: some View {
        RoundedRectangle(cornerRadius: tokens.tileCornerRadius)
            .fill(isSplat ? cardShadowColor : Color.clear)
            .offset(
                x: isSplat ? (isFocused ? 6 : 4) : 0,
                y: isSplat ? (isFocused ? 8 : 5) : 0
            )
    }

    private var idleShape: some View {
        RoundedRectangle(cornerRadius: tokens.tileCornerRadius)
            .fill(isFocused ? Color.clear : tokens.cardBgIdle)
    }

    private var focusShape: some View {
        RoundedRectangle(cornerRadius: tokens.tileCornerRadius)
            .fill(isFocused ? tokens.focusBg : Color.clear)
    }

    private var strokeShape: some View {
        RoundedRectangle(cornerRadius: tokens.tileCornerRadius)
            .strokeBorder(
                isFocused
                    ? (tokens.focusStrokeColor ?? tokens.strokeColor).opacity(tokens.focusStrokeOpacity)
                    : tokens.strokeColor.opacity(tokens.strokeOpacity),
                lineWidth: isFocused ? tokens.focusStrokeWidth : tokens.strokeWidth
            )
    }

    private var cardShadowColor: Color {
        if isFocused {
            return (tokens.focusGlowColor ?? Color.black).opacity(0.95)
        }
        return Color.black.opacity(0.82)
    }
}
