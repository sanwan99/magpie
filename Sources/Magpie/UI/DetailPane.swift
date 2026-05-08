import SwiftUI

/// Right-hand detail pane per spec §04: heading + full type-aware preview + action buttons.
/// Width controlled by parent; this view fills its container.
struct DetailPane: View {
    let clip: ClipDisplayItem?
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    /// 点击 header 右上"扩大"按钮时调用 — 由 PanelController 转发到
    /// ExpandedPreviewWindowController.shared.show(clip:)。
    var onExpand: (() -> Void)? = nil
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let clip {
                content(for: clip)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(Color.clear)
        )
    }

    // MARK: - Filled content

    @ViewBuilder
    private func content(for clip: ClipDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: clip)
                .padding(.horizontal, 16)
                .padding(.top, 15)
                .padding(.bottom, 13)
            detailRule
            ScrollView(showsIndicators: false) {
                fullPreview(for: clip)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            detailRule
            actions(for: clip)
                .padding(12)
        }
    }

    // MARK: - Header

    private func header(for clip: ClipDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                typeBadge(for: clip.type)
                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(pinColor)
                }
                Spacer()
                HStack(spacing: 6) {
                    if let app = clip.app, !app.isEmpty {
                        Text(shortAppLabel(app))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(timeAgo(clip.createdAt))
                        .monospacedDigit()
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(tertiaryText)
                if onExpand != nil {
                    expandButton
                }
            }

            Text(displayTitle(for: clip))
                .font(.system(size: settings.flavor == .splat ? 20 : 14, weight: .semibold))
                .foregroundStyle(primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 扩大化按钮 — 把当前 clip 在独立窗口里大尺寸渲染。
    /// 视觉跟随 flavor：splat 用墨黑底 + 奶白图标；普通主题低调灰色。
    private var expandButton: some View {
        Button {
            onExpand?()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(primaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(settings.flavor == .splat
                              ? splatInk.opacity(0.85)
                              : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("放大查看（⌘O）")
    }

    private func typeBadge(for type: ClipType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon(type))
                .font(.system(size: 11, weight: .medium))
            Text(typeDisplayName(type))
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(settings.flavor == .splat ? splatCream : secondaryText)
        .padding(.horizontal, settings.flavor.isDecorative ? 8 : 0)
        .padding(.vertical, settings.flavor.isDecorative ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(settings.flavor == .splat
                      ? splatInk
                      : (settings.flavor.isDecorative ? tokens.accent.opacity(0.12) : Color.clear))
        )
    }

    // MARK: - Full preview

    @ViewBuilder
    private func fullPreview(for clip: ClipDisplayItem) -> some View {
        switch clip.preview {
        case .text(let body):
            previewBlock {
                Text(body)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(primaryText)
                    .textSelection(.enabled)
            }

        case .code(let body, let lang):
            previewBlock {
                if let lang, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tertiaryText)
                }
                Text(body)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(4)
                    .foregroundStyle(primaryText)
                    .textSelection(.enabled)
            }

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    favicon(letter: host ?? url.host ?? "URL")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host ?? url.host ?? "URL")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                        Text(localized(zh: "链接", en: "Link"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(tertiaryText)
                    }
                }
                Text(url.absoluteString)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(secondaryText)
                    .lineLimit(5)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(blockBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            VStack(alignment: .leading, spacing: 10) {
                // DetailPane 宽度 ~360-440pt，800 缩略图够清；想看原图按 ⌘O 走
                // ExpandedPreview 加载全分辨率。
                switch ImageThumbnail.loadResult(path: path, maxPixelSize: 800) {
                case .loaded(let nsimg):
                    ZStack {
                        CheckerboardBackground()
                        Image(nsImage: nsimg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(ruleColor, lineWidth: 0.5)
                    )
                case .failed(let reason):
                    previewBlock {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(tertiaryText)
                            Text(
                                reason == .missingFile
                                    ? localized(zh: "图片文件丢失", en: "Image file missing")
                                    : localized(zh: "图片解码失败", en: "Image decode failed")
                            )
                                .font(.system(size: 11))
                                .foregroundStyle(secondaryText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
                HStack(spacing: 12) {
                    Label("\(w)×\(h)", systemImage: "ruler")
                    Label("\(sizeKB) KB", systemImage: "internaldrive")
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(secondaryText)
                pathBlock(path)
            }

        case .unsupported:
            Text(localized(zh: "暂不支持这种剪切板类型", en: "Unsupported clip type"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Actions

    private func actions(for clip: ClipDisplayItem) -> some View {
        Group {
            if settings.flavor == .splat {
                HStack(spacing: 8) {
                    Button(action: onTogglePin) {
                        HStack(spacing: 6) {
                            Image(systemName: clip.pinned ? "pin.slash" : "pin")
                            Text(clip.pinned ? localized(zh: "取消固定", en: "UNPIN") : localized(zh: "固定", en: "PIN"))
                        }
                    }
                    .buttonStyle(SplatActionButtonStyle(kind: .secondary, colorScheme: colorScheme))

                    Button(action: onPaste) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.up")
                            Text(localized(zh: "粘贴", en: "PASTE"))
                            Spacer()
                            Text("↵")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                    .buttonStyle(SplatActionButtonStyle(kind: .primary, colorScheme: colorScheme))
                    .keyboardShortcut(.return, modifiers: [])
                }
            } else {
                HStack(spacing: 8) {
                    Button(action: onTogglePin) {
                        HStack(spacing: 6) {
                            Image(systemName: clip.pinned ? "pin.slash" : "pin")
                            Text(clip.pinned ? localized(zh: "取消固定", en: "Unpin") : localized(zh: "固定", en: "Pin"))
                        }
                    }
                    .buttonStyle(RegularActionButtonStyle(isPrimary: false, colorScheme: colorScheme))

                    Button(action: onPaste) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.up")
                            Text(localized(zh: "粘贴", en: "Paste"))
                            Spacer()
                            Text("↵")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RegularActionButtonStyle(isPrimary: true, colorScheme: colorScheme))
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    // MARK: - Empty state

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(localized(zh: "选择一条剪切板记录", en: "Select a clip"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func typeIcon(_ type: ClipType) -> String {
        switch type {
        case .text:   return "text.alignleft"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        case .url:    return "link"
        case .image:  return "photo"
        case .file:   return "doc"
        case .folder: return "folder"
        }
    }

    private func localized(zh: String, en: String) -> String {
        settings.language.pick(zh: zh, en: en)
    }

    private func typeDisplayName(_ type: ClipType) -> String {
        switch type {
        case .text:   return localized(zh: "文本", en: "TEXT")
        case .code:   return localized(zh: "代码", en: "CODE")
        case .url:    return localized(zh: "链接", en: "URL")
        case .image:  return localized(zh: "图片", en: "IMAGE")
        case .file:   return localized(zh: "文件", en: "FILE")
        case .folder: return localized(zh: "文件夹", en: "FOLDER")
        }
    }

    private func itemCount(_ count: Int) -> String {
        localized(zh: "\(count) 项", en: "\(count) item\(count == 1 ? "" : "s")")
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60     { return localized(zh: "刚刚", en: "just now") }
        if secs < 3600   { return localized(zh: "\(Int(secs / 60)) 分钟前", en: "\(Int(secs / 60))m ago") }
        if secs < 86_400 { return localized(zh: "\(Int(secs / 3600)) 小时前", en: "\(Int(secs / 3600))h ago") }
        return localized(zh: "\(Int(secs / 86_400)) 天前", en: "\(Int(secs / 86_400))d ago")
    }

    private func displayTitle(for clip: ClipDisplayItem) -> String {
        if let title = clip.title, !title.isEmpty {
            return title
        }
        switch clip.preview {
        case .url(_, let host):
            return host ?? "URL"
        case .file(let path, _, _), .folder(let path, _):
            return (path as NSString).lastPathComponent
        case .image(_, let w, let h, _):
            return localized(zh: "图片 · \(w)×\(h)", en: "Image · \(w)×\(h)")
        default:
            return typeDisplayName(clip.type)
        }
    }

    private func shortAppLabel(_ bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }

    private func previewBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(blockBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(ruleColor, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func fileLikePreview(icon: String, title: String, meta: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(secondaryText)
                    .frame(width: 36, height: 36)
                    .background(blockBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                    Text(meta)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(secondaryText)
                }
            }
            pathBlock(path)
        }
    }

    private func pathBlock(_ path: String) -> some View {
        Text(path)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(secondaryText)
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(blockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(ruleColor, lineWidth: 0.5)
            )
    }

    private func favicon(letter: String) -> some View {
        Text(letter.prefix(1).uppercased())
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(settings.flavor.isDecorative ? tokens.accent : primaryText)
            .frame(width: 36, height: 36)
            .background(blockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ruleColor, lineWidth: 0.5)
            )
    }

    private var detailRule: some View {
        Rectangle()
            .fill(ruleColor)
            .frame(height: 0.5)
    }

    private var tokens: FlavorTokens {
        settings.flavor.tokens(for: colorScheme)
    }

    private var primaryText: Color {
        settings.flavor == .splat ? splatCream : Color.primary
    }

    private var secondaryText: Color {
        settings.flavor == .splat ? splatCream.opacity(0.72) : Color.secondary
    }

    private var tertiaryText: Color {
        settings.flavor == .splat ? splatCream.opacity(0.48) : Color.secondary.opacity(0.62)
    }

    private var ruleColor: Color {
        if settings.flavor.isDecorative {
            return tokens.accent.opacity(settings.flavor == .splat ? 0.45 : 0.16)
        }
        return colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    private var blockBackground: Color {
        if settings.flavor == .splat {
            return Color(red: 0.13, green: 0.04, blue: 0.23).opacity(0.58)
        }
        return colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)
    }

    private var pinColor: Color {
        settings.flavor.isDecorative ? tokens.accent : Color.secondary
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}

private struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
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

private enum SplatActionKind {
    case primary
    case secondary
}

private struct SplatActionButtonStyle: ButtonStyle {
    let kind: SplatActionKind
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(kind == .primary ? splatCream : splatYellow)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: kind == .primary ? 44 : 36)
            .background(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .fill(kind == .primary ? splatPurple : Color(red: 0.13, green: 0.04, blue: 0.23).opacity(0.96))
            )
            .background(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .fill(kind == .primary ? splatInk.opacity(0.85) : Color.clear)
                    .offset(x: kind == .primary ? 4 : 0, y: kind == .primary ? 4 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .strokeBorder(kind == .primary ? splatInk : splatYellow.opacity(0.75), lineWidth: kind == .primary ? 2 : 1.5)
            )
            .rotationEffect(kind == .primary ? .degrees(-2) : .degrees(0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}

private struct RegularActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundStyle(isPrimary ? primaryForeground : secondaryForeground)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? primaryBackground : secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPrimary ? Color.clear : regularBorder, lineWidth: isPrimary ? 0 : 0.5)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }

    private var primaryBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.95, blue: 0.96)
            : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    private var primaryForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color.white
    }

    private var secondaryBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.60)
    }

    private var secondaryForeground: Color {
        Color.secondary
    }

    private var regularBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.06)
    }
}
