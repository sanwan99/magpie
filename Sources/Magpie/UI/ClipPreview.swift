import SwiftUI

/// Compact 220×220 card used by Stripe layout. Type-aware preview body.
struct ClipPreview: View {
    let clip: ClipDisplayItem
    var isFocused: Bool = false
    /// If set, render a `⌘N` shortcut badge in the header. Stripe layout
    /// passes 1-9 for the first nine cards (matching the ⌘1-⌘9 hotkeys).
    var shortcutNumber: Int? = nil

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let t = settings.flavor.tokens(for: colorScheme)
        let isSplat = settings.flavor == .splat
        VStack(alignment: .leading, spacing: 8) {
            header
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(12)
        .frame(width: 220, height: 220, alignment: .topLeading)
        .modifier(ClipCardChrome(tokens: t, isFocused: isFocused, isSplat: isSplat))
        .offset(y: isFocused ? -2 : 0)
        .rotationEffect(isSplat ? splatRotation : .degrees(0))
        .environment(\.colorScheme, isSplat && isFocused ? .light : colorScheme)
        // No SwiftUI animation modifier here — applying `.animation(value:)` to
        // every card causes all 9+ views to recompute styles on each focus
        // change, which compounds with ScrollViewReader's centering. The
        // visual snap is sharp and fast; we re-add motion polish in v0.3.
    }

    // MARK: - Header (type icon + label + age)

    private var header: some View {
        HStack(spacing: 6) {
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(typeLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    // MARK: - Body — switch on preview content

    @ViewBuilder
    private var previewBody: some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 12))
                .lineLimit(7)
                .lineSpacing(1.5)
                .foregroundStyle(.primary)

        case .code(let body, _):
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(8)
                .foregroundStyle(.primary.opacity(0.92))

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 4) {
                Text(host ?? url.host ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

        case .folder(let path, let items):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text("\(items) item\(items == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
            }

        case .file(let path, let kind, let sizeKB):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text("\(kind.uppercased()) · \(sizeKB) KB")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
            }

        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 4) {
                // Stripe 卡片只显示 ~190pt 宽，加载 256px 缩略图就够，
                // 比直接 NSImage(contentsOfFile:) 全分辨率解码省 ~30 倍内存。
                if let nsimg = ImageThumbnail.load(path: path, maxPixelSize: 256) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    HStack {
                        Spacer()
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                Text("\(w)×\(h) · \(sizeKB) KB")
                    .font(.system(size: 9, design: .monospaced))
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

    // MARK: - Footer (app attribution)

    private var footer: some View {
        HStack(spacing: 4) {
            if let app = clip.app, !app.isEmpty {
                Text(shortAppLabel(app))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
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
        clip.type.rawValue.uppercased()
    }

    private var timeAgo: String {
        let secs = Date().timeIntervalSince(clip.createdAt)
        if secs < 60     { return "now" }
        if secs < 3600   { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86_400))d"
    }

    private func shortAppLabel(_ bundleId: String) -> String {
        // com.apple.dt.Xcode → Xcode; com.openai.codex → codex
        return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }

    private var splatRotation: Angle {
        if isFocused { return .degrees(-1.2) }
        guard let shortcutNumber else { return .degrees(0.4) }
        return .degrees(shortcutNumber.isMultiple(of: 2) ? 0.7 : -0.6)
    }
}

private struct ClipCardChrome: ViewModifier {
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
                color: isSplat ? .clear : Color.black.opacity(isFocused ? 0.12 : 0.04),
                radius: isFocused ? 6 : 2,
                x: 0,
                y: isFocused ? 2 : 1
            )
    }

    private var shadowShape: some View {
        RoundedRectangle(cornerRadius: tokens.cardCornerRadius)
            .fill(isSplat ? cardShadowColor : Color.clear)
            .offset(
                x: isSplat ? (isFocused ? 6 : 4) : 0,
                y: isSplat ? (isFocused ? 8 : 5) : 0
            )
    }

    private var idleShape: some View {
        RoundedRectangle(cornerRadius: tokens.cardCornerRadius)
            .fill(isFocused ? Color.clear : tokens.cardBgIdle)
    }

    private var focusShape: some View {
        RoundedRectangle(cornerRadius: tokens.cardCornerRadius)
            .fill(isFocused ? tokens.focusBg : Color.clear)
    }

    private var strokeShape: some View {
        RoundedRectangle(cornerRadius: tokens.cardCornerRadius)
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
