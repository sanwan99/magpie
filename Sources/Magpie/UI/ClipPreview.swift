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
        let isSplat = settings.flavor == .splat
        VStack(alignment: .leading, spacing: 9) {
            header
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(12)
        .frame(width: 220, height: 220, alignment: .topLeading)
        .modifier(ClipCardChrome(tokens: tokens, isFocused: isFocused, isSplat: isSplat))
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
                    .foregroundStyle(primaryText.opacity(0.72))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(surfaceFill)
                    )
            }
            Image(systemName: typeIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentText)
            Text(typeLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(secondaryText)
            Spacer()
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accentText)
            }
            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(tertiaryText)
                .monospacedDigit()
        }
    }

    // MARK: - Body — switch on preview content

    @ViewBuilder
    private var previewBody: some View {
        switch clip.preview {
        case .text(let body):
            previewSurface {
                Text(body)
                    .font(.system(size: 12))
                    .lineLimit(7)
                    .lineSpacing(2)
                    .foregroundStyle(primaryText)
            }

        case .code(let body, _):
            previewSurface {
                Text(body)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(8)
                    .lineSpacing(2)
                    .foregroundStyle(primaryText.opacity(0.92))
            }

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    favicon(letter: host ?? url.host ?? "URL")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(host ?? url.host ?? "URL")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                        Text(localized(zh: "链接", en: "Link"))
                            .font(.system(size: 9))
                            .foregroundStyle(tertiaryText)
                    }
                }
                previewSurface {
                    Text(url.absoluteString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(secondaryText)
                        .lineLimit(4)
                        .truncationMode(.middle)
                }
            }

        case .folder(let path, let items):
            fileLikePreview(
                icon: "folder.fill",
                title: (path as NSString).lastPathComponent,
                meta: itemCount(items),
                path: path
            )

        case .file(let path, let kind, let sizeKB):
            fileLikePreview(
                icon: "doc.fill",
                title: (path as NSString).lastPathComponent,
                meta: "\(kind.uppercased()) · \(sizeKB) KB",
                path: path
            )

        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 6) {
                // Stripe 卡片只显示 ~190pt 宽，加载 256px 缩略图就够，
                // 比直接 NSImage(contentsOfFile:) 全分辨率解码省 ~30 倍内存。
                switch ImageThumbnail.loadResult(path: path, maxPixelSize: 256) {
                case .loaded(let nsimg):
                    ZStack(alignment: .bottomLeading) {
                        CardCheckerboardBackground()
                        Image(nsImage: nsimg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(5)
                        Text("\(w)×\(h)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(cardOverlayFill)
                            )
                            .padding(5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(ruleColor, lineWidth: 0.5)
                    )
                case .failed(let reason):
                    thumbnailPlaceholder(reason)
                }
                Text("\(sizeKB) KB")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }

        case .unsupported:
            Text(localized(zh: "暂不支持", en: "Unsupported"))
                .font(.system(size: 11))
                .foregroundStyle(tertiaryText)
                .italic()
        }
    }

    private func fileLikePreview(icon: String, title: String, meta: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(accentText)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(meta)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
            previewSurface {
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(tertiaryText)
                    .lineLimit(4)
                    .truncationMode(.middle)
            }
        }
    }

    private func previewSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(surfaceFill)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentText.opacity(settings.flavor.isDecorative ? 0.7 : 0.22))
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(ruleColor, lineWidth: 0.5)
        )
    }

    private func favicon(letter: String) -> some View {
        Text(letter.prefix(1).uppercased())
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(accentText)
            .frame(width: 28, height: 28)
            .background(surfaceFill)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(ruleColor, lineWidth: 0.5)
            )
    }

    private func thumbnailPlaceholder(_ reason: ImageThumbnail.LoadFailureReason) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(.system(size: 28))
                .foregroundStyle(tertiaryText)
            Text(thumbnailFailureText(reason))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceFill)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(ruleColor, lineWidth: 0.5)
        )
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
        switch clip.type {
        case .text:   return localized(zh: "文本", en: "TEXT")
        case .code:   return localized(zh: "代码", en: "CODE")
        case .url:    return localized(zh: "链接", en: "URL")
        case .image:  return localized(zh: "图片", en: "IMAGE")
        case .file:   return localized(zh: "文件", en: "FILE")
        case .folder: return localized(zh: "文件夹", en: "FOLDER")
        }
    }

    private var timeAgo: String {
        let secs = Date().timeIntervalSince(clip.createdAt)
        if secs < 60     { return localized(zh: "刚刚", en: "now") }
        if secs < 3600   { return localized(zh: "\(Int(secs / 60))分前", en: "\(Int(secs / 60))m") }
        if secs < 86_400 { return localized(zh: "\(Int(secs / 3600))时前", en: "\(Int(secs / 3600))h") }
        return localized(zh: "\(Int(secs / 86_400))天前", en: "\(Int(secs / 86_400))d")
    }

    private func localized(zh: String, en: String) -> String {
        settings.language.pick(zh: zh, en: en)
    }

    private func itemCount(_ count: Int) -> String {
        localized(zh: "\(count) 项", en: "\(count) item\(count == 1 ? "" : "s")")
    }

    private func thumbnailFailureText(_ reason: ImageThumbnail.LoadFailureReason) -> String {
        switch reason {
        case .missingFile:
            return localized(zh: "图片文件丢失", en: "missing")
        case .decodeFailed:
            return localized(zh: "图片解码失败", en: "decode failed")
        }
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

    private var tokens: FlavorTokens {
        settings.flavor.tokens(for: colorScheme)
    }

    private var primaryText: Color {
        settings.flavor == .splat ? Color(red: 0.05, green: 0.05, blue: 0.06) : Color.primary
    }

    private var secondaryText: Color {
        settings.flavor == .splat ? Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.72) : Color.secondary
    }

    private var tertiaryText: Color {
        settings.flavor == .splat ? Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.48) : Color.secondary.opacity(0.62)
    }

    private var accentText: Color {
        settings.flavor.isDecorative ? tokens.accent : secondaryText
    }

    private var surfaceFill: Color {
        if settings.flavor == .splat {
            return Color.white.opacity(0.36)
        }
        return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.035)
    }

    private var cardOverlayFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.58) : Color.white.opacity(0.82)
    }

    private var ruleColor: Color {
        if settings.flavor.isDecorative {
            return tokens.accent.opacity(settings.flavor == .splat ? 0.55 : 0.18)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

private struct CardCheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 10
            let rows = Int(ceil(size.height / tile))
            let cols = Int(ceil(size.width / tile))
            let base = colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.035)
            let alt = colorScheme == .dark ? Color.white.opacity(0.070) : Color.black.opacity(0.065)

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            for row in 0...rows {
                for col in 0...cols where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(col) * tile,
                        y: CGFloat(row) * tile,
                        width: tile,
                        height: tile
                    )
                    context.fill(Path(rect), with: .color(alt))
                }
            }
        }
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
