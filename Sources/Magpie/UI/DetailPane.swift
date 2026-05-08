import AppKit
import SwiftUI

/// 主面板右侧的详情面板。按 [magpie-preview-pane-redesign.html] 原型 §1
/// 重排为：
///
///   ┌──────────────────────────────────────────┐
///   │ Header (relative)                        │  dp-head
///   │   ├─ eyebrow (类型 · 元数据 [+ Pinned]) │
///   │   ├─ title (14pt 600, 2 行截断)         │
///   │   ├─ meta (来源 app · • · 相对时间)     │
///   │   └─ tools (右上 Pin / Open ⌘O 双按钮)  │
///   ├──────────────────────────────────────────┤  divider
///   │ Body (scroll)                            │  dp-body
///   │   类型专属内容块                          │
///   ├──────────────────────────────────────────┤  divider
///   │ Footer                                   │  dp-foot
///   │   左 hint label · 右 secondary + Paste  │
///   └──────────────────────────────────────────┘
///
/// 普通主题（mono / graphite / blue / olive）严格按原型黑白灰；splat 和
/// forest / husk / mist / club / unit / ink / gilt 等装饰主题保留各自 accent
/// 与外框风格。
struct DetailPane: View {
    let clip: ClipDisplayItem?
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    /// 点击 header 右上 ⌘O 按钮时调用 — 由 PanelController 转发到
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
        .background(Rectangle().fill(Color.clear))
    }

    // MARK: - Content shell

    @ViewBuilder
    private func content(for clip: ClipDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader(
                clip: clip,
                onTogglePin: onTogglePin,
                onExpand: onExpand
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ruleLine

            ScrollView(showsIndicators: false) {
                DetailBody(clip: clip)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            ruleLine

            DetailFooter(
                clip: clip,
                onPaste: onPaste
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Empty state（dp-empty）

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(MagpieColors.blockBg(colorScheme))
                Circle()
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
            .frame(width: 44, height: 44)

            Text(settings.language.pick(zh: "未选中条目", en: "No clip selected"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text(settings.language.pick(
                zh: "在左侧选一条记录，或直接输入开始检索全部历史。",
                en: "Select an item from the list, or start typing to search across all clipboard history."
            ))
            .font(.system(size: 11.5))
            .foregroundStyle(Color.secondary.opacity(0.85))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 220)
            .lineSpacing(2)

            HStack(spacing: 6) {
                Text(settings.language.pick(zh: "按", en: "Press"))
                kbdKey("↑↓")
                Text(settings.language.pick(zh: "翻页", en: "to navigate"))
                Text("·")
                kbdKey("↩")
                Text(settings.language.pick(zh: "粘贴", en: "to paste"))
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.secondary.opacity(0.7))
            .padding(.top, 2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func kbdKey(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MagpieColors.blockBg(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
            )
    }

    private var ruleLine: some View {
        Rectangle()
            .fill(MagpieColors.rule(colorScheme))
            .frame(height: 0.5)
    }
}

// MARK: - Header

private struct DetailHeader: View {
    let clip: ClipDisplayItem
    let onTogglePin: () -> Void
    let onExpand: (() -> Void)?

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                eyebrow
                title
                meta
            }
            tools
                .padding(.top, -2)
                .padding(.trailing, -2)
        }
    }

    /// 类型 + 元数据（如 `Text · 1,287 chars`），可选 Pinned callout。
    private var eyebrow: some View {
        HStack(spacing: 8) {
            Image(systemName: typeIcon(clip.type))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(eyebrowFg)
            Text(eyebrowText)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(eyebrowFg)
            if clip.pinned {
                pinnedCallout
            }
        }
    }

    private var pinnedCallout: some View {
        Text(settings.language.pick(zh: "已固定", en: "PINNED"))
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.4)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(MagpieColors.pin(colorScheme))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(MagpieColors.blockBg(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(MagpieColors.pin(colorScheme).opacity(0.3), lineWidth: 0.5)
            )
    }

    private var title: some View {
        Text(displayTitle(for: clip, language: settings.language))
            .font(.system(size: settings.flavor == .splat ? 16 : 14, weight: .semibold))
            .foregroundStyle(Color.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 60) // 给 tools 留位
    }

    private var meta: some View {
        HStack(spacing: 9) {
            if let app = clip.app, !app.isEmpty {
                HStack(spacing: 5) {
                    sourceIcon(for: app)
                    Text(shortAppLabel(app))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Circle()
                .fill(Color.primary.opacity(0.18))
                .frame(width: 2, height: 2)
            Text(timeAgo(clip.createdAt, language: settings.language))
                .monospacedDigit()
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.secondary.opacity(0.8))
    }

    private func sourceIcon(for app: String) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(
                colors: appIconGradient(for: app),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: 12, height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            )
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ToolButton(
                systemName: clip.pinned ? "pin.fill" : "pin",
                tint: clip.pinned ? MagpieColors.pin(colorScheme) : nil,
                helpText: clip.pinned
                    ? settings.language.pick(zh: "取消固定 (⌘D)", en: "Unpin (⌘D)")
                    : settings.language.pick(zh: "固定 (⌘D)", en: "Pin (⌘D)"),
                action: onTogglePin
            )
            if let onExpand {
                ToolButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    tint: nil,
                    helpText: settings.language.pick(zh: "放大查看 (⌘O)", en: "Open in window (⌘O)"),
                    action: onExpand
                )
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }

    private var eyebrowText: String {
        let typeName = typeDisplayName(clip.type, language: settings.language)
        let extra = eyebrowExtra(language: settings.language)
        if extra.isEmpty { return typeName }
        return "\(typeName) · \(extra)"
    }

    private func eyebrowExtra(language: AppLanguage) -> String {
        switch clip.preview {
        case .text(let body):
            let chars = body.count
            return language.pick(zh: "\(chars.formattedWithGrouping()) 字符", en: "\(chars.formattedWithGrouping()) chars")
        case .code(let body, let lang):
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
            let language0 = lang?.uppercased()
            let lineLabel = language.pick(zh: "\(lines) 行", en: "\(lines) lines")
            return [language0, lineLabel].compactMap { $0 }.joined(separator: " · ")
        case .url:
            return language.pick(zh: "链接", en: "Link")
        case .image(_, _, _, let kb):
            return "PNG · \(formatSize(kb: kb))"
        case .file(_, let kind, let kb):
            return "\(kind.uppercased()) · \(formatSize(kb: kb))"
        case .folder(_, let items):
            return language.pick(zh: "\(items) 项", en: "\(items) item\(items == 1 ? "" : "s")")
        case .unsupported:
            return ""
        }
    }

    private var eyebrowFg: Color {
        Color.secondary.opacity(0.85)
    }
}

// MARK: - Body — switch on type

private struct DetailBody: View {
    let clip: ClipDisplayItem
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch clip.preview {
        case .text(let body):
            TextPreviewBlock(source: body)
        case .code(let body, let lang):
            CodePreviewBlock(source: body, lang: lang)
        case .url(let url, let host):
            URLPreviewBlock(url: url, host: host, copiedAt: clip.createdAt)
        case .image(let path, let w, let h, let kb):
            ImagePreviewBlock(path: path, width: w, height: h, sizeKB: kb)
        case .file(let path, let kind, let kb):
            FilePreviewBlock(path: path, kind: kind, sizeKB: kb, modifiedAt: clip.createdAt)
        case .folder(let path, let items):
            FolderPreviewBlock(path: path, items: items, modifiedAt: clip.createdAt)
        case .unsupported:
            Text(settings.language.pick(zh: "暂不支持这种剪切板类型", en: "Unsupported clip type"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }
}

// MARK: - TEXT

private struct TextPreviewBlock: View {
    let source: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(source)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(Color.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CODE — 行号 + 五色高亮 + 顶右 lang callout

private struct CodePreviewBlock: View {
    let source: String
    let lang: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    codeContent
                        .padding(.vertical, 10)
                        .padding(.trailing, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MagpieColors.blockBg(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
            )

            if let lang, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(MagpieColors.paneBg(colorScheme))
                    )
                    .padding(.top, 6)
                    .padding(.trailing, 6)
            }
        }
    }

    private var codeContent: some View {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let palette = SyntaxHighlighter.Palette.mono(colorScheme)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(idx + 1)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .frame(width: 32, alignment: .trailing)
                        .padding(.trailing, 10)
                        .monospacedDigit()
                    Text(SyntaxHighlighter.highlight(
                        String(line),
                        language: lang,
                        palette: palette,
                        fontSize: 12
                    ))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                }
            }
        }
    }

}

// MARK: - URL — favicon 卡 + raw URL block + Copied info-row

private struct URLPreviewBlock: View {
    let url: URL
    let host: String?
    let copiedAt: Date

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                favicon
                VStack(alignment: .leading, spacing: 4) {
                    Text(host ?? url.host ?? "URL")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.secondary)
                    Text(url.lastPathComponent.isEmpty
                            ? (host ?? url.host ?? url.absoluteString)
                            : prettyTitle(from: url))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Text(settings.language.pick(zh: "网页链接", en: "Web link"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                Spacer(minLength: 0)
            }

            Text(url.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .textSelection(.enabled)
                .lineLimit(6)
                .truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MagpieColors.blockBg(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                )

            InfoRow(
                key: settings.language.pick(zh: "复制于", en: "Copied"),
                value: absoluteTimeText(copiedAt, language: settings.language)
            )
        }
    }

    private var favicon: some View {
        let letter = (host ?? url.host ?? "URL").prefix(1).uppercased()
        return Text(letter)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                LinearGradient(
                    colors: hostGradient(for: host ?? url.host ?? "URL"),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
            )
    }

    private func prettyTitle(from url: URL) -> String {
        // 从 URL 路径推一个可读 title — 没有真实页面 title 时的 fallback。
        let path = url.path.replacingOccurrences(of: "/", with: " / ")
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? url.absoluteString : trimmed
    }
}

// MARK: - IMAGE

private struct ImagePreviewBlock: View {
    let path: String
    let width: Int
    let height: Int
    let sizeKB: Int

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumb
            InfoRow(
                key: settings.language.pick(zh: "尺寸", en: "Dimensions"),
                value: "\(width) × \(height) px"
            )
            InfoRow(
                key: settings.language.pick(zh: "大小", en: "Size"),
                value: formatSize(kb: sizeKB)
            )
            InfoRow(
                key: settings.language.pick(zh: "路径", en: "Path"),
                value: path,
                mono: true
            )
        }
    }

    @ViewBuilder
    private var thumb: some View {
        switch ImageThumbnail.loadResult(path: path, maxPixelSize: 800) {
        case .loaded(let nsimg):
            ZStack {
                CheckerBg(tile: 12)
                Image(nsImage: nsimg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
            )
        case .failed(let reason):
            ImageErrorBlock(reason: reason)
        }
    }
}

private struct ImageErrorBlock: View {
    let reason: ImageThumbnail.LoadFailureReason
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(MagpieColors.blockBg(colorScheme))
                Circle()
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .frame(width: 36, height: 36)

            Text(reason == .missingFile
                    ? settings.language.pick(zh: "无法加载图片", en: "Couldn't load image")
                    : settings.language.pick(zh: "图片解码失败", en: "Couldn't decode image"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)

            Text(reason == .missingFile
                    ? settings.language.pick(zh: "文件可能已被移动或删除", en: "File may have been moved or deleted")
                    : settings.language.pick(zh: "文件已损坏或格式不支持", en: "File may be corrupted or unsupported"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(20)
        .background(MagpieColors.blockBg(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
        )
    }
}

// MARK: - FILE

private struct FilePreviewBlock: View {
    let path: String
    let kind: String
    let sizeKB: Int
    let modifiedAt: Date

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileLikeCard(
                icon: "doc.fill",
                title: (path as NSString).lastPathComponent,
                subtitle: "\(kind.uppercased()) · \(formatSize(kb: sizeKB))"
            )
            Rectangle()
                .fill(MagpieColors.ruleSoft(colorScheme))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 4) {
                InfoRow(
                    key: settings.language.pick(zh: "类型", en: "Kind"),
                    value: kindDescription(kind: kind, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "大小", en: "Size"),
                    value: detailedSize(kb: sizeKB, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "修改时间", en: "Modified"),
                    value: absoluteTimeText(modifiedAt, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "路径", en: "Path"),
                    value: nil
                )
            }
            PathBlock(path: path)
        }
    }
}

// MARK: - FOLDER

private struct FolderPreviewBlock: View {
    let path: String
    let items: Int
    let modifiedAt: Date

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileLikeCard(
                icon: "folder.fill",
                title: (path as NSString).lastPathComponent,
                subtitle: settings.language.pick(zh: "文件夹", en: "Folder")
            )
            FolderStats(
                items: items,
                folders: nil,
                files: nil,
                onDisk: nil
            )
            InfoRow(
                key: settings.language.pick(zh: "修改时间", en: "Modified"),
                value: absoluteTimeText(modifiedAt, language: settings.language)
            )
            InfoRow(
                key: settings.language.pick(zh: "路径", en: "Path"),
                value: nil
            )
            PathBlock(path: path)
        }
    }
}

// MARK: - Shared blocks

/// 给 ExpandedPreviewWindow 也复用 — 文件 / 文件夹"图标 + 标题 + 副标题"卡。
struct FileLikeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconSize: CGFloat = 24
    var iconBoxSize: CGFloat = 40
    var titleSize: CGFloat = 13

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundStyle(Color.secondary)
                .frame(width: iconBoxSize, height: iconBoxSize)
                .background(MagpieColors.blockBg(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 文件夹横排 stats：items / folders / files / on disk —— 也供 ExpandedWindow sidebar 复用。
struct FolderStats: View {
    let items: Int
    let folders: Int?
    let files: Int?
    let onDisk: String?

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 18) {
            stat(num: "\(items)", label: settings.language.pick(zh: "项", en: "items"))
            if let folders {
                stat(num: "\(folders)", label: settings.language.pick(zh: "目录", en: "folders"))
            }
            if let files {
                stat(num: "\(files)", label: settings.language.pick(zh: "文件", en: "files"))
            }
            if let onDisk {
                stat(num: onDisk, label: settings.language.pick(zh: "占用", en: "on disk"))
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(MagpieColors.ruleSoft(colorScheme)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(MagpieColors.ruleSoft(colorScheme)).frame(height: 1)
        }
    }

    private func stat(num: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(num)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }
}

/// 通用 key-value 行（"Modified · Today, 14:32"）。也供 ExpandedWindow sidebar 复用。
struct InfoRow: View {
    let key: String
    /// nil = 这一行只显示 key（key 下方紧跟一个 PathBlock 等场景）。
    let value: String?
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .frame(width: 76, alignment: .leading)
            if let value {
                Text(value)
                    .font(.system(size: 11, design: mono ? .monospaced : .default))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 3)
    }
}

/// 等宽路径块。也供 ExpandedWindow 复用。
struct PathBlock: View {
    let path: String
    var fontSize: CGFloat = 11
    var lineLimit: Int = 3
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(path)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Color.secondary)
            .textSelection(.enabled)
            .lineLimit(lineLimit)
            .truncationMode(.middle)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MagpieColors.blockBg(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
            )
    }
}

/// 棋盘背景（图片预览底纹）。也供 ExpandedWindow 复用。
struct CheckerBg: View {
    let tile: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / tile))
            let cols = Int(ceil(size.width / tile))
            let base = colorScheme == .dark
                ? Color(red: 0.137, green: 0.137, blue: 0.153)
                : Color(red: 0.965, green: 0.965, blue: 0.965)
            let alt = colorScheme == .dark
                ? Color(red: 0.165, green: 0.165, blue: 0.184)
                : Color(red: 0.925, green: 0.925, blue: 0.925)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            for row in 0...rows {
                for col in 0...cols where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(col) * tile,
                        y: CGFloat(row) * tile,
                        width: tile, height: tile
                    )
                    context.fill(Path(rect), with: .color(alt))
                }
            }
        }
    }
}

// MARK: - Footer

private struct DetailFooter: View {
    let clip: ClipDisplayItem
    let onPaste: () -> Void

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            footerHint
            Spacer(minLength: 0)
            actions
        }
    }

    private var footerHint: some View {
        HStack(spacing: 5) {
            Text("↩")
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MagpieColors.blockBg(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                )
            Text(settings.language.pick(zh: "粘贴", en: "paste"))
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch clip.preview {
        case .text, .code:
            HStack(spacing: 8) {
                SecondaryActionButton(
                    icon: "doc.on.doc",
                    label: settings.language.pick(zh: "复制", en: "Copy"),
                    action: { copyToClipboard() }
                )
                pasteButton
            }
        case .url(let url, _):
            HStack(spacing: 8) {
                SecondaryActionButton(
                    icon: "safari",
                    label: settings.language.pick(zh: "打开", en: "Open"),
                    action: { NSWorkspace.shared.open(url) }
                )
                pasteButton
            }
        case .image(let path, _, _, _):
            HStack(spacing: 8) {
                if FileManager.default.fileExists(atPath: path) {
                    SecondaryActionButton(
                        icon: "square.and.arrow.down",
                        label: settings.language.pick(zh: "保存…", en: "Save…"),
                        action: { saveImage(from: path) }
                    )
                    pasteButton
                } else {
                    SecondaryActionButton(
                        icon: "magnifyingglass",
                        label: settings.language.pick(zh: "在 Finder 显示", en: "Reveal"),
                        action: { revealInFinder(path: path) }
                    )
                    PrimaryActionButton(
                        label: settings.language.pick(zh: "粘贴", en: "Paste"),
                        action: onPaste,
                        disabled: true
                    )
                }
            }
        case .file(let path, _, _):
            HStack(spacing: 8) {
                SecondaryActionButton(
                    icon: "magnifyingglass",
                    label: settings.language.pick(zh: "在 Finder 显示", en: "Reveal"),
                    action: { revealInFinder(path: path) }
                )
                pasteButton
            }
        case .folder(let path, _):
            HStack(spacing: 8) {
                SecondaryActionButton(
                    icon: "folder",
                    label: settings.language.pick(zh: "打开", en: "Open"),
                    action: { openFolder(path: path) }
                )
                pasteButton
            }
        case .unsupported:
            pasteButton
        }
    }

    private var pasteButton: some View {
        PrimaryActionButton(
            label: settings.language.pick(zh: "粘贴", en: "Paste"),
            action: onPaste
        )
        .keyboardShortcut(.return, modifiers: [])
    }

    // MARK: side effects

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.preview {
        case .text(let body): pb.setString(body, forType: .string)
        case .code(let body, _): pb.setString(body, forType: .string)
        case .url(let url, _): pb.setString(url.absoluteString, forType: .string)
        case .file(let path, _, _), .folder(let path, _), .image(let path, _, _, _):
            pb.setString(path, forType: .string)
        case .unsupported: break
        }
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openFolder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func saveImage(from path: String) {
        let panel = NSSavePanel()
        panel.title = settings.language.pick(zh: "保存图片", en: "Save Image")
        panel.nameFieldStringValue = (path as NSString).lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            let src = URL(fileURLWithPath: path)
            // 覆盖模式：NSSavePanel 已替用户确认过覆盖。
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: src, to: dest)
        }
    }
}

// MARK: - Buttons

private struct ToolButton: View {
    let systemName: String
    let tint: Color?
    let helpText: String
    let action: () -> Void

    @State private var isHover = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHover ? MagpieColors.btnBgHover(colorScheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHover = $0 }
        .help(helpText)
    }
}

private struct SecondaryActionButton: View {
    let icon: String?
    let label: String
    let action: () -> Void

    @State private var isHover = false
    @Environment(\.colorScheme) private var colorScheme
    private let settings = SettingsStore.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHover ? MagpieColors.btnBgHover(colorScheme) : MagpieColors.btnBg(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MagpieColors.btnBorder(colorScheme), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHover = $0 }
    }
}

private struct PrimaryActionButton: View {
    let label: String
    let action: () -> Void
    var disabled: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    private let settings = SettingsStore.shared

    var body: some View {
        if settings.flavor == .splat {
            splatButton
        } else {
            standardButton
        }
    }

    private var standardButton: some View {
        let isDecorative = settings.flavor.isDecorative
        let tokens = settings.flavor.tokens(for: colorScheme)
        let bg: Color = isDecorative ? tokens.accent : MagpieColors.accentInk(colorScheme)
        let fg: Color = isDecorative ? .white : MagpieColors.accentInkFg(colorScheme)
        return Button(action: { if !disabled { action() } }) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("↩")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.18))
                    )
                    .opacity(0.9)
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(bg)
            )
            .opacity(disabled ? 0.45 : (isPressed ? 0.85 : 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// splat 主题保留 codex 落地的章鱼风格主按钮（紫底 + 黄字 + 黑边 + 倾斜）。
    private var splatButton: some View {
        Button(action: { if !disabled { action() } }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.up")
                    .font(.system(size: 12, weight: .bold))
                Text(label.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.6)
                Spacer(minLength: 4)
                Text("↩")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(Color(red: 1.00, green: 0.97, blue: 0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(minWidth: 130)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.48, green: 0.17, blue: 1.00))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color(red: 0.05, green: 0.05, blue: 0.06), lineWidth: 2)
            )
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.05, green: 0.05, blue: 0.06).opacity(0.85))
                    .offset(x: 3, y: 3)
            )
            .rotationEffect(.degrees(-2))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - 颜色 token

enum MagpieColors {
    static func ink1(_ scheme: ColorScheme) -> Color { Color.primary }
    static func ink2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.7)
                        : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.66)
    }
    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.45)
                        : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.42)
    }
    static func rule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
    static func ruleSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.05)
    }
    static func blockBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)
    }
    static func paneBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.78)
                        : Color(red: 0.99, green: 0.98, blue: 0.97).opacity(0.86)
    }
    static func btnBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.7)
    }
    static func btnBgHover(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.95)
    }
    static func btnBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }
    static func accentInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.95, blue: 0.96)
                        : Color(red: 0.11, green: 0.11, blue: 0.12)
    }
    static func accentInkFg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.10, green: 0.10, blue: 0.11)
                        : Color(red: 0.98, green: 0.98, blue: 0.98)
    }
    static func pin(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.84, green: 0.64, blue: 0.30)  // #d6a24b
                        : Color(red: 0.77, green: 0.52, blue: 0.12)  // #c5841f
    }
}

// MARK: - 文案 / 颜色辅助

// MARK: - Cross-file helpers (ExpandedPreviewWindow 也用)

func typeIcon(_ type: ClipType) -> String {
    switch type {
    case .text:   return "text.alignleft"
    case .code:   return "chevron.left.forwardslash.chevron.right"
    case .url:    return "link"
    case .image:  return "photo"
    case .file:   return "doc"
    case .folder: return "folder"
    }
}

func typeDisplayName(_ type: ClipType, language: AppLanguage) -> String {
    switch type {
    case .text:   return language.pick(zh: "文本", en: "Text")
    case .code:   return language.pick(zh: "代码", en: "Code")
    case .url:    return language.pick(zh: "链接", en: "Link")
    case .image:  return language.pick(zh: "图片", en: "Image")
    case .file:   return language.pick(zh: "文件", en: "File")
    case .folder: return language.pick(zh: "文件夹", en: "Folder")
    }
}

func displayTitle(for clip: ClipDisplayItem, language: AppLanguage) -> String {
    if let title = clip.title, !title.isEmpty {
        return title
    }
    switch clip.preview {
    case .url(_, let host):
        return host ?? "URL"
    case .file(let path, _, _), .folder(let path, _):
        return (path as NSString).lastPathComponent
    case .image(_, let w, let h, _):
        return language.pick(zh: "图片 · \(w)×\(h)", en: "Image · \(w)×\(h)")
    default:
        return typeDisplayName(clip.type, language: language)
    }
}

func timeAgo(_ date: Date, language: AppLanguage) -> String {
    let secs = Date().timeIntervalSince(date)
    if secs < 60     { return language.pick(zh: "刚刚", en: "just now") }
    if secs < 3600   { return language.pick(zh: "\(Int(secs / 60)) 分钟前", en: "\(Int(secs / 60)) minutes ago") }
    if secs < 86_400 { return language.pick(zh: "\(Int(secs / 3600)) 小时前", en: "\(Int(secs / 3600)) hours ago") }
    return language.pick(zh: "\(Int(secs / 86_400)) 天前", en: "\(Int(secs / 86_400)) days ago")
}

func absoluteTimeText(_ date: Date, language: AppLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language == .zhHans ? "zh_CN" : "en_US")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func shortAppLabel(_ bundleId: String) -> String {
    bundleId.split(separator: ".").last.map(String.init) ?? bundleId
}

func formatSize(kb: Int) -> String {
    if kb >= 1024 {
        let mb = Double(kb) / 1024.0
        return String(format: mb >= 10 ? "%.0f MB" : "%.1f MB", mb)
    }
    return "\(kb) KB"
}

func detailedSize(kb: Int, language: AppLanguage) -> String {
    let bytes = kb * 1024
    let bytesText = bytes.formattedWithGrouping()
    let unit = language.pick(zh: "字节", en: "bytes")
    return "\(bytesText) \(unit) (\(formatSize(kb: kb)))"
}

func kindDescription(kind: String, language: AppLanguage) -> String {
    let upper = kind.uppercased()
    return language.pick(
        zh: "\(upper) 文件 (.\(kind.lowercased()))",
        en: "\(upper) file (.\(kind.lowercased()))"
    )
}

/// 给 source app 算个稳定的渐变色 — 同一个 bundle id 永远是同一组色。
private func appIconGradient(for app: String) -> [Color] {
    let palette: [(Color, Color)] = [
        (Color(red: 0.36, green: 0.51, blue: 0.92), Color(red: 0.11, green: 0.30, blue: 0.86)), // blue
        (Color(red: 0.95, green: 0.62, blue: 0.18), Color(red: 0.89, green: 0.29, blue: 0.23)), // orange/red
        (Color(red: 0.36, green: 0.27, blue: 0.90), Color(red: 0.16, green: 0.10, blue: 0.54)), // indigo
        (Color(red: 0.04, green: 0.81, blue: 0.51), Color(red: 0.64, green: 0.35, blue: 1.00)), // figma
        (Color(red: 0.78, green: 0.78, blue: 0.81), Color(red: 0.64, green: 0.64, blue: 0.68))  // gray
    ]
    let idx = abs(app.hashValue) % palette.count
    let pair = palette[idx]
    return [pair.0, pair.1]
}

private func hostGradient(for host: String) -> [Color] {
    let palette: [(Color, Color)] = [
        (Color(red: 0.36, green: 0.27, blue: 0.90), Color(red: 0.16, green: 0.10, blue: 0.54)),
        (Color(red: 0.36, green: 0.51, blue: 0.92), Color(red: 0.11, green: 0.30, blue: 0.86)),
        (Color(red: 0.95, green: 0.62, blue: 0.18), Color(red: 0.89, green: 0.29, blue: 0.23)),
        (Color(red: 0.04, green: 0.81, blue: 0.51), Color(red: 0.16, green: 0.45, blue: 0.36)),
        (Color(red: 0.78, green: 0.16, blue: 0.46), Color(red: 0.50, green: 0.09, blue: 0.32))
    ]
    let idx = abs(host.hashValue) % palette.count
    let pair = palette[idx]
    return [pair.0, pair.1]
}

extension Int {
    func formattedWithGrouping() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
