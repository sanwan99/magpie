import AppKit
import SwiftUI

/// 独立的"放大预览"窗口 — 把当前 focused clip 用大尺寸 + 完整渲染显示在一个
/// 标准 NSWindow 里，按 [magpie-preview-pane-redesign.html] 原型 §2 重做：
///
///   ┌────────────────── 标题栏（系统画 红绿灯 + 中央 win.title）─────────┐
///   │ ┌──────────── 240pt sidebar ─┐ ┌────────────── hero 主区 ──────┐ │
///   │ │ eyebrow                    │ │                                │ │
///   │ │ h1 标题                    │ │   text-hero / code-hero /     │ │
///   │ │ source · time              │ │   image-hero (含浮动 zoom bar)│ │
///   │ │ ─────                      │ │                                │ │
///   │ │ info-row 矩阵              │ │                                │ │
///   │ │ path block                 │ │                                │ │
///   │ │ Spacer                     │ │                                │ │
///   │ │ secondary buttons + Paste  │ │                                │ │
///   │ └────────────────────────────┘ └────────────────────────────────┘ │
///   ├──────────── footer 36pt（key hint · 状态文案）────────────────────┤
///   └─────────────────────────────────────────────────────────────────┘
///
/// **快照模式**：show(clip:) 锁定那条 clip；后续主面板切焦点不会动这个窗口。
/// **独立生命周期**：主面板 hide / Esc 不影响这里，"开大窗 → 收 panel → 慢慢看"。
@MainActor
final class ExpandedPreviewWindowController {
    static let shared = ExpandedPreviewWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<ExpandedPreviewView>?

    private init() {}

    func show(clip: ClipDisplayItem) {
        let title = displayTitle(for: clip, language: SettingsStore.shared.language)
        let view = ExpandedPreviewView(clip: clip, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        })

        if let existing = window {
            hostingController?.rootView = view
            existing.title = title
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let host = NSHostingController(rootView: view)
        let initialSize = NSSize(width: 920, height: 640)
        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .windowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        host.view.frame = container.bounds
        host.view.autoresizingMask = [.width, .height]
        container.addSubview(host.view)

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 让系统画红绿灯 + 中央窗口标题；SwiftUI 内容上方留约 28pt 空白以避免被压。
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        win.title = title
        win.isMovableByWindowBackground = false  // 避免误拖；标题栏本身可拖
        win.backgroundColor = .clear
        win.isOpaque = false
        win.contentView = container
        win.minSize = NSSize(width: 720, height: 460)
        win.isReleasedWhenClosed = false
        win.appearance = SettingsStore.shared.theme.appearance
        // 跟主面板 NSPanel 同 level（都是 .floating），避免被主面板遮挡。
        // 同 level 时 key window 在前 — 用户点哪个就哪个浮起来。
        win.level = .floating
        // 默认位置：屏幕顶部居中。主面板固定在屏幕底部 (`visibleFrame.minY +
        // bottomInset`)，所以放大窗放顶部能跟它垂直错开，不互相挡。
        // 用户拖动后，下一次 show 会走 `if let existing = window` 分支，保留位置。
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let x = v.midX - initialSize.width / 2
            let y = v.maxY - initialSize.height - 16
            win.setFrame(NSRect(x: x, y: y, width: initialSize.width, height: initialSize.height),
                         display: false)
        } else {
            win.center()
        }

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.hostingController = host
    }

    /// 主面板焦点变化时调用 — 只在窗口当前可见时联动更新；不开就 noop。
    /// 行为：窗口里的 clip 切换为新焦点，window 标题同步更新。
    /// 设计意图：用户在主面板上下移动时，预览窗跟着切；如果用户已经收掉主面板
    /// 或关掉窗口，这里不会"自己又把窗口拉起来"。
    func updateIfOpen(clip: ClipDisplayItem) {
        guard let win = window, win.isVisible, let host = hostingController else { return }
        host.rootView = ExpandedPreviewView(clip: clip, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        })
        win.title = displayTitle(for: clip, language: SettingsStore.shared.language)
    }

    func close() {
        window?.orderOut(nil)
    }
}

// MARK: - 主体 View

private struct ExpandedPreviewView: View {
    let clip: ClipDisplayItem
    let onClose: () -> Void

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isSplat: Bool { settings.flavor == .splat }
    private var isDecorative: Bool { settings.flavor.isDecorative }
    private var tokens: FlavorTokens { settings.flavor.tokens(for: colorScheme) }

    /// Image hero 的当前缩放（1.0 = 100%）。其它类型不读这个 state。
    @State private var imageMagnification: CGFloat = 1.0
    /// Code hero 的"软换行"开关。
    @State private var codeWrapLines: Bool = false
    /// JSON 格式化开关（仅对 text/code 类型 + 内容合法 JSON 时生效）。
    /// 切换 clip 时通过 onChange 重置，避免上条 clip 的格式化态污染下一条。
    @State private var jsonFormatted: Bool = false

    var body: some View {
        ZStack {
            // 放大窗有意"安静"：装饰主题（splat / forest / 等）的 panelBgOverlay
            // 不叠到这里，让 NSVisualEffectView 的毛玻璃直接透出，内容区严格按
            // 原型的 light/dark 黑白灰呈现。装饰主题的"身份感"通过外框 + accent
            // paste 按钮体现；主面板（PanelController）依然保留各 flavor 装饰。

            VStack(spacing: 0) {
                // 系统标题栏占用 ~28pt — 让出空间避免 SwiftUI 内容跟红绿灯打架。
                Color.clear.frame(height: 28)

                HStack(spacing: 0) {
                    ExpandedSidebar(
                        clip: clip,
                        onPaste: paste,
                        onPastePath: pastePath,
                        wrapLines: codeWrapLines,
                        onToggleWrap: { codeWrapLines.toggle() },
                        jsonFormatted: jsonFormatted,
                        onToggleJSON: { jsonFormatted.toggle() }
                    )
                    .frame(width: 240)

                    Rectangle()
                        .fill(MagpieColors.rule(colorScheme))
                        .frame(width: 0.5)

                    ExpandedMain(
                        clip: clip,
                        imageMagnification: $imageMagnification,
                        codeWrapLines: $codeWrapLines,
                        jsonFormatted: jsonFormatted
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(MagpieColors.rule(colorScheme))
                    .frame(height: 0.5)

                ExpandedFooter(clip: clip, imageMagnification: imageMagnification)
            }
        }
        .overlay {
            // ExpandedWindow 外框故意"安静"：
            // - splat：用黑细边而不是粗黄边（用户反馈"黄色条纹太抢戏"），
            //   splat 身份感保留在卡片黄底 + 章鱼装饰 + 紫 paste 按钮上。
            // - 其他装饰主题：accent 色 1pt 描边，作为弱身份标识。
            // - 普通主题：留给系统标题栏的 hairline，不画。
            if isSplat {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                    .padding(0.5)
                    .allowsHitTesting(false)
            } else if isDecorative {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tokens.accent.opacity(0.55), lineWidth: 1)
                    .padding(0.75)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        // ⌘W / Esc 关窗 + image hero 的 ⌘+ / ⌘− / ⌘0 都挂这儿
        .background(keyboardShortcuts)
        // 切到下一条 clip 时，JSON 格式化态 / Image 缩放 / Code wrap 都回到默认。
        .onChange(of: clip.id) { _, _ in
            jsonFormatted = false
            imageMagnification = 1.0
            codeWrapLines = false
        }
    }

    private var keyboardShortcuts: some View {
        Group {
            Button(action: onClose) { Color.clear }
                .keyboardShortcut("w", modifiers: .command)
            Button(action: onClose) { Color.clear }
                .keyboardShortcut(.cancelAction)
            Button(action: zoomIn) { Color.clear }
                .keyboardShortcut("=", modifiers: .command) // ⌘+
            Button(action: zoomIn) { Color.clear }
                .keyboardShortcut("+", modifiers: .command)
            Button(action: zoomOut) { Color.clear }
                .keyboardShortcut("-", modifiers: .command)
            Button(action: resetZoom) { Color.clear }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    private func paste() {
        // ExpandedWindow 不直接持有 paste 闭包（它是窗外打开的快照视图）；
        // 走 NSPasteboard + 触发 frontmost-app 粘贴的常规链路：
        // 写入 → 通过通知 / 直接调用 PanelController paste，由 PanelController 来兜。
        // 这里简化：写到 NSPasteboard 让用户自己 ⌘V，避免跨窗口耦合。
        Paster.writeToPasteboard(clip)
    }

    private func pastePath() {
        Paster.writePathToPasteboard(clip)
    }

    private func zoomIn()    { imageMagnification = min(imageMagnification * 1.25, 8.0) }
    private func zoomOut()   { imageMagnification = max(imageMagnification / 1.25, 0.1) }
    private func resetZoom() { imageMagnification = 1.0 }
}

// MARK: - Sidebar

private struct ExpandedSidebar: View {
    let clip: ClipDisplayItem
    let onPaste: () -> Void
    let onPastePath: () -> Void
    let wrapLines: Bool
    let onToggleWrap: () -> Void
    let jsonFormatted: Bool
    let onToggleJSON: () -> Void

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    private var tokens: FlavorTokens { settings.flavor.tokens(for: colorScheme) }
    private var isDecorative: Bool { settings.flavor.isDecorative }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            metaHeader
            divider
            metaInfo
            if shouldShowPath, let p = pathOf(clip) {
                PathBlock(path: p, fontSize: 11, lineLimit: 4)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var divider: some View {
        Rectangle()
            .fill(MagpieColors.rule(colorScheme))
            .frame(height: 0.5)
    }

    private var metaHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: typeIcon(clip.type))
                    .font(.system(size: 11, weight: .medium))
                Text(eyebrowText)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Color.secondary.opacity(0.85))

            Text(displayTitle(for: clip, language: settings.language))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if let app = clip.app, !app.isEmpty {
                    Text(shortAppLabel(app))
                }
                Circle()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 2, height: 2)
                Text(timeAgo(clip.createdAt, language: settings.language))
                    .monospacedDigit()
                if clip.pinned {
                    Circle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 2, height: 2)
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill")
                        Text(settings.language.pick(zh: "已固定", en: "pinned"))
                    }
                    .foregroundStyle(MagpieColors.pin(colorScheme))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.secondary.opacity(0.8))
        }
    }

    private var eyebrowText: String {
        let typeName = typeDisplayName(clip.type, language: settings.language)
        switch clip.preview {
        case .code(_, let lang):
            return "\(typeName)\(lang.map { " · \($0)" } ?? "")"
        case .image(_, _, _, _):
            return "\(typeName) · PNG"
        case .file(_, let kind, _):
            return "\(typeName) · \(kind.uppercased())"
        default:
            return typeName
        }
    }

    @ViewBuilder
    private var metaInfo: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch clip.preview {
            case .text(let body):
                let chars = body.count
                let words = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
                InfoRow(
                    key: settings.language.pick(zh: "长度", en: "Length"),
                    value: settings.language.pick(
                        zh: "\(chars.formattedWithGrouping()) 字符 · \(words) 词",
                        en: "\(chars.formattedWithGrouping()) chars · \(words) words"
                    )
                )
                InfoRow(
                    key: settings.language.pick(zh: "行数", en: "Lines"),
                    value: "\(lines)"
                )
                InfoRow(
                    key: settings.language.pick(zh: "复制于", en: "Copied"),
                    value: absoluteTimeText(clip.createdAt, language: settings.language)
                )
            case .code(let body, let lang):
                let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
                let chars = body.count
                let indent = inferIndent(body)
                InfoRow(
                    key: settings.language.pick(zh: "语言", en: "Language"),
                    value: lang?.uppercased() ?? settings.language.pick(zh: "未知", en: "Unknown")
                )
                InfoRow(
                    key: settings.language.pick(zh: "行数", en: "Lines"),
                    value: "\(lines)"
                )
                InfoRow(
                    key: settings.language.pick(zh: "字符", en: "Chars"),
                    value: chars.formattedWithGrouping()
                )
                InfoRow(
                    key: settings.language.pick(zh: "缩进", en: "Indent"),
                    value: indent
                )
            case .url(let url, let host):
                InfoRow(
                    key: settings.language.pick(zh: "主机", en: "Host"),
                    value: host ?? url.host ?? ""
                )
                InfoRow(
                    key: settings.language.pick(zh: "复制于", en: "Copied"),
                    value: absoluteTimeText(clip.createdAt, language: settings.language)
                )
            case .image(_, let w, let h, let kb):
                InfoRow(
                    key: settings.language.pick(zh: "尺寸", en: "Dimensions"),
                    value: "\(w) × \(h) px"
                )
                InfoRow(
                    key: settings.language.pick(zh: "大小", en: "Size"),
                    value: formatSize(kb: kb)
                )
                InfoRow(
                    key: settings.language.pick(zh: "复制于", en: "Copied"),
                    value: absoluteTimeText(clip.createdAt, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "路径", en: "Path"),
                    value: nil
                )
            case .file(_, let kind, let kb):
                InfoRow(
                    key: settings.language.pick(zh: "类型", en: "Kind"),
                    value: kindDescription(kind: kind, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "大小", en: "Size"),
                    value: detailedSize(kb: kb, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "修改时间", en: "Modified"),
                    value: absoluteTimeText(clip.createdAt, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "路径", en: "Path"),
                    value: nil
                )
            case .folder(_, let items):
                InfoRow(
                    key: settings.language.pick(zh: "项目", en: "Items"),
                    value: settings.language.pick(zh: "\(items) 项", en: "\(items) item\(items == 1 ? "" : "s")")
                )
                InfoRow(
                    key: settings.language.pick(zh: "修改时间", en: "Modified"),
                    value: absoluteTimeText(clip.createdAt, language: settings.language)
                )
                InfoRow(
                    key: settings.language.pick(zh: "路径", en: "Path"),
                    value: nil
                )
            case .unsupported:
                InfoRow(
                    key: settings.language.pick(zh: "类型", en: "Kind"),
                    value: settings.language.pick(zh: "暂不支持", en: "Unsupported")
                )
            }
        }
    }

    private var shouldShowPath: Bool {
        switch clip.preview {
        case .image, .file, .folder: return true
        default: return false
        }
    }

    private func pathOf(_ clip: ClipDisplayItem) -> String? {
        switch clip.preview {
        case .image(let path, _, _, _),
             .file(let path, _, _),
             .folder(let path, _):
            return path
        default: return nil
        }
    }

    /// 简单推断缩进风格：看第一个有缩进的行。
    private func inferIndent(_ source: String) -> String {
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("\t") { return settings.language.pick(zh: "Tab", en: "Tab") }
            if line.hasPrefix("    ") { return settings.language.pick(zh: "4 空格", en: "4 spaces") }
            if line.hasPrefix("  ") { return settings.language.pick(zh: "2 空格", en: "2 spaces") }
        }
        return settings.language.pick(zh: "未缩进", en: "None")
    }

    @ViewBuilder
    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch clip.preview {
            case .text, .code:
                if case .code = clip.preview {
                    SidebarSecondaryButton(
                        icon: wrapLines ? "text.alignleft" : "arrow.turn.down.right",
                        label: wrapLines
                            ? settings.language.pick(zh: "不换行", en: "No wrap")
                            : settings.language.pick(zh: "软换行", en: "Wrap lines"),
                        action: onToggleWrap
                    )
                }
                if isLikelyJSON {
                    SidebarSecondaryButton(
                        icon: jsonFormatted ? "curlybraces.square" : "curlybraces",
                        label: jsonFormatted
                            ? settings.language.pick(zh: "显示原文", en: "Show raw")
                            : settings.language.pick(zh: "JSON 格式化", en: "Format JSON"),
                        action: onToggleJSON
                    )
                }
                SidebarSecondaryButton(
                    icon: "doc.on.doc",
                    label: settings.language.pick(zh: "复制原文", en: "Copy raw"),
                    action: { copyRaw() }
                )
                sidebarPasteButton
            case .url(let url, _):
                SidebarSecondaryButton(
                    icon: "safari",
                    label: settings.language.pick(zh: "在浏览器打开", en: "Open in browser"),
                    action: { NSWorkspace.shared.open(url) }
                )
                sidebarPasteButton
            case .image(let path, _, _, _):
                if FileManager.default.fileExists(atPath: path) {
                    SidebarSecondaryButton(
                        icon: "magnifyingglass",
                        label: settings.language.pick(zh: "在 Finder 显示", en: "Reveal"),
                        action: { revealInFinder(path: path) }
                    )
                    SidebarSecondaryButton(
                        icon: "square.and.arrow.down",
                        label: settings.language.pick(zh: "另存为…", en: "Save as…"),
                        action: { saveImage(from: path) }
                    )
                    sidebarPasteButton
                } else {
                    SidebarSecondaryButton(
                        icon: "magnifyingglass",
                        label: settings.language.pick(zh: "在 Finder 显示", en: "Reveal"),
                        action: { revealInFinder(path: path) }
                    )
                    SidebarPrimaryButton(
                        label: settings.language.pick(zh: "粘贴", en: "Paste"),
                        action: onPaste,
                        disabled: true
                    )
                }
            case .file(let path, _, _):
                SidebarSecondaryButton(
                    icon: "magnifyingglass",
                    label: settings.language.pick(zh: "在 Finder 显示", en: "Reveal"),
                    action: { revealInFinder(path: path) }
                )
                sidebarPathButton
                sidebarPasteButton
            case .folder(let path, _):
                SidebarSecondaryButton(
                    icon: "folder",
                    label: settings.language.pick(zh: "打开", en: "Open"),
                    action: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                )
                sidebarPathButton
                sidebarPasteButton
            case .unsupported:
                EmptyView()
            }
        }
    }

    private var sidebarPasteButton: some View {
        SidebarPrimaryButton(
            label: settings.language.pick(zh: "粘贴", en: "Paste"),
            action: onPaste,
            disabled: false
        )
        .keyboardShortcut(.return, modifiers: [])
    }

    private var sidebarPathButton: some View {
        SidebarSecondaryButton(
            icon: "text.quote",
            label: settings.language.pick(zh: "路径", en: "Path"),
            action: onPastePath
        )
    }

    private func copyRaw() {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch clip.preview {
        case .text(let body): pb.setString(body, forType: .string)
        case .code(let body, _): pb.setString(body, forType: .string)
        default: break
        }
    }

    /// 文本 / 代码内容看起来是合法 JSON 时返回 true。其他类型一律 false。
    private var isLikelyJSON: Bool {
        let raw: String
        switch clip.preview {
        case .text(let body): raw = body
        case .code(let body, _): raw = body
        default: return false
        }
        return JSONFormatter.isLikelyJSON(raw)
    }

    private func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func saveImage(from path: String) {
        let panel = NSSavePanel()
        panel.title = settings.language.pick(zh: "保存图片", en: "Save Image")
        panel.nameFieldStringValue = (path as NSString).lastPathComponent
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: dest)
        }
    }
}

// MARK: - Main hero

private struct ExpandedMain: View {
    let clip: ClipDisplayItem
    @Binding var imageMagnification: CGFloat
    @Binding var codeWrapLines: Bool
    let jsonFormatted: Bool

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            content
            // 仅 image hero 显示 zoom toolbar；其它 type 不挂。
            if case .image = clip.preview {
                ZoomToolbar(magnification: $imageMagnification)
                    .padding(.bottom, 18)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch clip.preview {
        case .text(let body):
            if jsonFormatted, let root = JSONFormatter.parse(body) {
                JSONTreeHero(root: root)
            } else {
                TextHero(source: body)
            }
        case .code(let body, let lang):
            if jsonFormatted, let root = JSONFormatter.parse(body) {
                JSONTreeHero(root: root)
            } else {
                CodeHero(source: body, lang: lang, wrapLines: codeWrapLines)
            }
        case .url(let url, let host):
            URLHero(url: url, host: host)
        case .image(let path, _, _, _):
            ImageHero(path: path, magnification: $imageMagnification)
        case .file(let path, let kind, let kb):
            FileHero(path: path, kind: kind, sizeKB: kb)
        case .folder(let path, let items):
            FolderHero(path: path, items: items)
        case .unsupported:
            UnsupportedHero()
        }
    }
}

// MARK: - JSON formatter

/// 极简 JSON helper —— 检测是否是合法 JSON，把扁平字符串 pretty-print 成多行带缩进，
/// 或解析成 `Any` 树供折叠视图使用。用 Foundation 的 JSONSerialization；不依赖第三方。
enum JSONFormatter {
    /// 看起来是 JSON 即返回 true：trim 后必须以 `{` 或 `[` 开头，并且能被
    /// `JSONSerialization` 成功解析（含 fragments）。"123" / "true" 这种字面量
    /// 单值不算 — 因为视觉上没必要 pretty-print。
    static func isLikelyJSON(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        guard let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    /// 解析为 Foundation 对象树（NSDictionary / NSArray / NSNumber / NSString / NSNull）。
    /// 失败返回 nil。供 JSONTreeHero 渲染折叠树用。
    static func parse(_ s: String) -> Any? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// pretty-print 失败返回 nil（不是 JSON / 非法 / 编码异常）。当前 JSONTreeHero
    /// 直接用 parse 走树视图；prettyPrint 留作"另存为字符串"等场景的 fallback。
    static func prettyPrint(_ s: String) -> String? {
        guard let obj = parse(s) else { return nil }
        guard let pretty = try? JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }
}

// MARK: - JSON tree hero — 扁平化 + LazyVStack（性能关键）

/// JSON 折叠树主区。
///
/// **为什么扁平化？** 早期实现是递归 `JSONNodeView`，每个 object/array 节点的
/// `body` 内嵌一个 ForEach 渲染所有子节点 —— SwiftUI 在 view 树构建期会一次性
/// 实例化整棵树。对几千节点的 JSON，主线程被压几百毫秒到几秒，hotkey 在这期间
/// 响应不了，看起来像"假死叫不出来"（用户实测命中）。
///
/// 改法：把 JSON 整棵树扁平成 `[JSONRow]`，每行一个 row（叶子 / open-brace /
/// close-brace 三种），用 `LazyVStack` 渲染 —— 只构建可视区的子 view，几万行
/// JSON 也只渲染屏幕上的 ~50 行，主线程压力常数级。
///
/// **折叠**：collapsed Set<path>。flatten 时遇到折叠节点跳过子树、改 emit 一个
/// 带 summary 的"折叠合并行"。点 chevron 修改 Set，触发重 flatten + 重渲染。
private struct JSONTreeHero: View {
    let root: Any

    /// path → 是否折叠。默认全部展开（空集合）。path 写法：`$` 根；`$.users[0].name`
    /// 嵌套。切 clip 时由父 view 通过 onChange(of: clip.id) 重置（State 在 view
    /// 重建时清空）。
    @State private var collapsed: Set<String> = []

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 每次 collapsed 变化重新 flatten。flatten 是 O(n) 一次扫描，对几万行
        // JSON 也是毫秒级；真正的性能瓶颈是 SwiftUI view 实例化，懒渲染解决。
        let rows = JSONFlattener.flatten(root: root, collapsed: collapsed)
        let palette = SyntaxHighlighter.Palette.mono(colorScheme)

        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    JSONRowView(
                        row: row,
                        palette: palette,
                        onToggle: { path in
                            if collapsed.contains(path) {
                                collapsed.remove(path)
                            } else {
                                collapsed.insert(path)
                            }
                        }
                    )
                }
            }
            .padding(EdgeInsets(top: 22, leading: 20, bottom: 22, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(MagpieColors.blockBg(colorScheme).opacity(0.5))
    }
}

/// 单行渲染。三种 kind：openBrace（折叠时合并 close 和 summary）/ closeBrace / leaf。
/// 单行 SwiftUI view 复杂度恒定，是 LazyVStack 子项的最佳形态。
private struct JSONRowView: View {
    let row: JSONRow
    let palette: SyntaxHighlighter.Palette
    let onToggle: (String) -> Void

    private let fontSize: CGFloat = 13
    private let indentUnit: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            // 缩进
            Color.clear.frame(width: CGFloat(row.depth) * indentUnit, height: 1)
            // chevron / 占位（保持 close brace 跟 open brace 列对齐）
            switch row.kind {
            case .openBrace(let path, _, _, _, let isCollapsed, _, _):
                Button(action: { onToggle(path) }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.plain.opacity(0.55))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            case .closeBrace, .leaf:
                Color.clear.frame(width: 18, height: 1) // 14 + 4 trailing
            }

            // 内容
            content
        }
        .font(.system(size: fontSize, design: .monospaced))
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .openBrace(_, let key, let isObject, let count, let isCollapsed, let isLast, _):
            keyPrefix(key)
            Text(isObject ? "{" : "[").foregroundStyle(palette.plain)
            if isCollapsed {
                Text(" \(count) \(isObject ? (count == 1 ? "key" : "keys") : (count == 1 ? "item" : "items")) ")
                    .foregroundStyle(palette.comment)
                    .italic()
                Text(isObject ? "}" : "]").foregroundStyle(palette.plain)
                if !isLast { Text(",").foregroundStyle(palette.plain) }
            }
        case .closeBrace(let isObject, let isLast):
            Text(isObject ? "}" : "]").foregroundStyle(palette.plain)
            if !isLast { Text(",").foregroundStyle(palette.plain) }
        case .leaf(let key, let value, let color, let isLast):
            keyPrefix(key)
            Text(value)
                .foregroundStyle(colorFor(color))
                .textSelection(.enabled)
            if !isLast { Text(",").foregroundStyle(palette.plain) }
        }
    }

    @ViewBuilder
    private func keyPrefix(_ key: String?) -> some View {
        if let key {
            Text(JSONFlattener.stringLiteral(key))
                .foregroundStyle(palette.function)
            Text(": ").foregroundStyle(palette.plain)
        }
    }

    private func colorFor(_ tag: JSONRow.ColorTag) -> Color {
        switch tag {
        case .string:  return palette.string
        case .number:  return palette.number
        case .keyword: return palette.keyword
        }
    }
}

/// 单行结构体。`id` 必须稳定 + 唯一，LazyVStack 才能正确 diff。
private struct JSONRow: Identifiable {
    let id: String
    let depth: Int
    let kind: Kind

    enum Kind {
        /// 开括号行。折叠时这一行同时承担"折叠摘要 + close 括号"，下面不再 emit
        /// 子行和 close 行。
        ///   - path: 折叠用 path
        ///   - key: 父 key（数组元素或根为 nil）
        ///   - isObject: true 是 `{`，false 是 `[`
        ///   - childCount: 用于折叠摘要 "5 keys" / "12 items"
        ///   - isCollapsed: 当前是否折叠
        ///   - isLast: 是否是父集合的最后一个 — 折叠态决定要不要尾逗号
        ///   - hasChildren: 没有子节点（空对象/数组）时不画 chevron
        case openBrace(
            path: String,
            key: String?,
            isObject: Bool,
            childCount: Int,
            isCollapsed: Bool,
            isLast: Bool,
            hasChildren: Bool
        )
        case closeBrace(isObject: Bool, isLast: Bool)
        case leaf(key: String?, value: String, color: ColorTag, isLast: Bool)
    }

    enum ColorTag {
        case string
        case number
        case keyword  // bool / null
    }
}

/// 把 Foundation JSON 树（NSDictionary / NSArray / NSNumber / NSNull / NSString）
/// 扁平化成行序列。collapsed 集合命中时跳过子树并把摘要合并到 openBrace 行。
private enum JSONFlattener {
    static func flatten(root: Any, collapsed: Set<String>) -> [JSONRow] {
        var rows: [JSONRow] = []
        rows.reserveCapacity(64)
        emit(value: root, key: nil, path: "$", depth: 0, isLast: true,
             collapsed: collapsed, into: &rows)
        return rows
    }

    private static func emit(
        value: Any,
        key: String?,
        path: String,
        depth: Int,
        isLast: Bool,
        collapsed: Set<String>,
        into rows: inout [JSONRow]
    ) {
        // null
        if value is NSNull {
            rows.append(JSONRow(
                id: path,
                depth: depth,
                kind: .leaf(key: key, value: "null", color: .keyword, isLast: isLast)
            ))
            return
        }
        // object
        if let dict = value as? [String: Any] {
            let keys = dict.keys.sorted()
            let isCollapsedNow = collapsed.contains(path)
            rows.append(JSONRow(
                id: path + "#open",
                depth: depth,
                kind: .openBrace(
                    path: path,
                    key: key,
                    isObject: true,
                    childCount: keys.count,
                    isCollapsed: isCollapsedNow,
                    isLast: isLast,
                    hasChildren: !keys.isEmpty
                )
            ))
            if !isCollapsedNow && !keys.isEmpty {
                for (i, k) in keys.enumerated() {
                    emit(
                        value: dict[k] ?? NSNull(),
                        key: k,
                        path: "\(path).\(escapeForPath(k))",
                        depth: depth + 1,
                        isLast: i == keys.count - 1,
                        collapsed: collapsed,
                        into: &rows
                    )
                }
                rows.append(JSONRow(
                    id: path + "#close",
                    depth: depth,
                    kind: .closeBrace(isObject: true, isLast: isLast)
                ))
            }
            return
        }
        // array
        if let arr = value as? [Any] {
            let isCollapsedNow = collapsed.contains(path)
            rows.append(JSONRow(
                id: path + "#open",
                depth: depth,
                kind: .openBrace(
                    path: path,
                    key: key,
                    isObject: false,
                    childCount: arr.count,
                    isCollapsed: isCollapsedNow,
                    isLast: isLast,
                    hasChildren: !arr.isEmpty
                )
            ))
            if !isCollapsedNow && !arr.isEmpty {
                for i in 0..<arr.count {
                    emit(
                        value: arr[i],
                        key: nil,
                        path: "\(path)[\(i)]",
                        depth: depth + 1,
                        isLast: i == arr.count - 1,
                        collapsed: collapsed,
                        into: &rows
                    )
                }
                rows.append(JSONRow(
                    id: path + "#close",
                    depth: depth,
                    kind: .closeBrace(isObject: false, isLast: isLast)
                ))
            }
            return
        }
        // string
        if let s = value as? String {
            rows.append(JSONRow(
                id: path,
                depth: depth,
                kind: .leaf(key: key, value: stringLiteral(s), color: .string, isLast: isLast)
            ))
            return
        }
        // number / bool
        if let n = value as? NSNumber {
            // NSNumber 同时承担 Bool / Int / Double — 用 objCType 区分 Bool。
            // CFNumberGetType 对 Bool 返回 charType `c`。
            let type = String(cString: n.objCType)
            if type == "c" {
                rows.append(JSONRow(
                    id: path,
                    depth: depth,
                    kind: .leaf(key: key, value: n.boolValue ? "true" : "false",
                                color: .keyword, isLast: isLast)
                ))
            } else {
                rows.append(JSONRow(
                    id: path,
                    depth: depth,
                    kind: .leaf(key: key, value: n.stringValue,
                                color: .number, isLast: isLast)
                ))
            }
            return
        }
        // 未识别类型兜底
        rows.append(JSONRow(
            id: path,
            depth: depth,
            kind: .leaf(key: key, value: String(describing: value),
                        color: .string, isLast: isLast)
        ))
    }

    /// 转义控制字符 + 包双引号，模拟 JSON 字符串字面量。
    static func stringLiteral(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"":  out += "\\\""
            case "\\":  out += "\\\\"
            case "\n":  out += "\\n"
            case "\r":  out += "\\r"
            case "\t":  out += "\\t"
            default:
                if c.value < 0x20 {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out += String(c)
                }
            }
        }
        out += "\""
        return out
    }

    /// path 段含 `.` 或 `[` 时简单转义，仅为了 collapsed Set 唯一性。
    private static func escapeForPath(_ k: String) -> String {
        k.replacingOccurrences(of: ".", with: "\\.")
         .replacingOccurrences(of: "[", with: "\\[")
    }
}

// MARK: - 类型 hero

private struct TextHero: View {
    let source: String

    var body: some View {
        ScrollView(showsIndicators: true) {
            Text(source)
                .font(.system(size: 15))
                .lineSpacing(7)
                .foregroundStyle(Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(EdgeInsets(top: 24, leading: 32, bottom: 32, trailing: 32))
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct CodeHero: View {
    let source: String
    let lang: String?
    let wrapLines: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let palette = SyntaxHighlighter.Palette.mono(colorScheme)
        return Group {
            if wrapLines {
                ScrollView(.vertical, showsIndicators: true) {
                    content(lines: lines, palette: palette)
                        .padding(.vertical, 22)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    content(lines: lines, palette: palette)
                        .padding(.vertical, 22)
                        .padding(.horizontal, 24)
                }
            }
        }
        .background(MagpieColors.blockBg(colorScheme).opacity(0.5))
    }

    @ViewBuilder
    private func content(lines: [Substring], palette: SyntaxHighlighter.Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                HStack(alignment: .top, spacing: 0) {
                    Text("\(idx + 1)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .frame(width: 40, alignment: .trailing)
                        .padding(.trailing, 12)
                        .monospacedDigit()
                    Text(SyntaxHighlighter.highlight(
                        String(line),
                        language: lang,
                        palette: palette,
                        fontSize: 13
                    ))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                }
            }
        }
    }
}

private struct URLHero: View {
    let url: URL
    let host: String?

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Text((host ?? url.host ?? "URL").prefix(1).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.27, blue: 0.90),
                                    Color(red: 0.16, green: 0.10, blue: 0.54)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.5)
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(host ?? url.host ?? "URL")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                        Text(url.absoluteString)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }

                Text(url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MagpieColors.blockBg(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
                    )
            }
            .padding(EdgeInsets(top: 24, leading: 32, bottom: 32, trailing: 32))
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct ImageHero: View {
    let path: String
    @Binding var magnification: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @GestureState private var pinchScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            CheckerBg(tile: 16)
                .ignoresSafeArea(edges: .horizontal)

            if let img = NSImage(contentsOfFile: path) {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: img.size.width * magnification * pinchScale,
                            height: img.size.height * magnification * pinchScale
                        )
                        .padding(40)
                        .gesture(
                            MagnificationGesture()
                                .updating($pinchScale) { value, state, _ in
                                    state = value
                                }
                                .onEnded { value in
                                    let next = magnification * value
                                    magnification = min(max(next, 0.1), 8.0)
                                }
                        )
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text(SettingsStore.shared.language.pick(
                        zh: "无法加载图片",
                        en: "Couldn't load image"
                    ))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct FileHero: View {
    let path: String
    let kind: String
    let sizeKB: Int
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                FileLikeCard(
                    icon: "doc.fill",
                    title: (path as NSString).lastPathComponent,
                    subtitle: "\(kind.uppercased()) · \(formatSize(kb: sizeKB))",
                    iconSize: 32,
                    iconBoxSize: 56,
                    titleSize: 17
                )
                PathBlock(path: path, fontSize: 13, lineLimit: 8)
            }
            .padding(EdgeInsets(top: 24, leading: 32, bottom: 32, trailing: 32))
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct FolderHero: View {
    let path: String
    let items: Int
    private let settings = SettingsStore.shared

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                FileLikeCard(
                    icon: "folder.fill",
                    title: (path as NSString).lastPathComponent,
                    subtitle: settings.language.pick(zh: "文件夹", en: "Folder"),
                    iconSize: 32,
                    iconBoxSize: 56,
                    titleSize: 17
                )
                FolderStats(items: items, folders: nil, files: nil, onDisk: nil)
                PathBlock(path: path, fontSize: 13, lineLimit: 8)
            }
            .padding(EdgeInsets(top: 24, leading: 32, bottom: 32, trailing: 32))
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct UnsupportedHero: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(SettingsStore.shared.language.pick(
                zh: "暂不支持这种剪切板类型",
                en: "Unsupported clip type"
            ))
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Zoom toolbar

private struct ZoomToolbar: View {
    @Binding var magnification: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            zoomBtn(icon: "rectangle.dashed", help: "Fit (⌘0)") { magnification = 1.0 }
            zoomBtn(icon: "minus", help: "Zoom out (⌘−)") {
                magnification = max(magnification / 1.25, 0.1)
            }
            Text("\(Int(magnification * 100))%")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 48)
                .monospacedDigit()
            zoomBtn(icon: "plus", help: "Zoom in (⌘+)") {
                magnification = min(magnification * 1.25, 8.0)
            }
            zoomBtn(icon: "1.magnifyingglass", help: "Actual size") {
                magnification = 1.0
            }
        }
        .padding(3)
        .background(
            Capsule().fill(MagpieColors.paneBg(colorScheme))
        )
        .overlay(
            Capsule().strokeBorder(MagpieColors.rule(colorScheme), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 12, y: 4)
    }

    private func zoomBtn(icon: String, help: String, action: @escaping () -> Void) -> some View {
        ZoomButton(systemName: icon, help: help, action: action)
    }
}

private struct ZoomButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHover = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(isHover ? 1 : 0.85))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(isHover ? MagpieColors.btnBgHover(colorScheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHover = $0 }
        .help(help)
    }
}

// MARK: - Footer

private struct ExpandedFooter: View {
    let clip: ClipDisplayItem
    let imageMagnification: CGFloat

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            keys
            Spacer(minLength: 0)
            statusText
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .font(.system(size: 11))
        .foregroundStyle(Color.secondary.opacity(0.7))
    }

    @ViewBuilder
    private var keys: some View {
        HStack(spacing: 14) {
            keyHint(["↩"], settings.language.pick(zh: "粘贴", en: "paste"))
            if case .image = clip.preview {
                keyHint(["⌘", "+"], settings.language.pick(zh: "放大", en: "zoom in"))
                keyHint(["⌘", "0"], settings.language.pick(zh: "原始", en: "fit"))
            } else if case .code = clip.preview {
                keyHint(["⌘", "C"], settings.language.pick(zh: "复制", en: "copy"))
            } else {
                keyHint(["⌘", "D"], settings.language.pick(zh: "固定", en: "pin"))
            }
            keyHint(["⎋"], settings.language.pick(zh: "关闭", en: "close"))
        }
    }

    private func keyHint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { k in
                    Text(k)
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
            }
            Text(label)
        }
    }

    private var statusText: some View {
        Text(rightStatus)
    }

    private var rightStatus: String {
        switch clip.preview {
        case .text(let body):
            let chars = body.count
            let words = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            return settings.language.pick(
                zh: "\(chars.formattedWithGrouping()) 字符 · \(words) 词",
                en: "\(chars.formattedWithGrouping()) chars · \(words) words"
            )
        case .code(let body, let lang):
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
            return [lang?.uppercased(), "UTF-8", settings.language.pick(zh: "\(lines) 行", en: "\(lines) lines")]
                .compactMap { $0 }.joined(separator: " · ")
        case .url(let url, _):
            return url.host ?? ""
        case .image(_, let w, let h, _):
            return "\(w) × \(h) · \(Int(imageMagnification * 100))%"
        case .file(_, let kind, let kb):
            return "\(kind.uppercased()) · \(formatSize(kb: kb))"
        case .folder(_, let items):
            return settings.language.pick(zh: "\(items) 项", en: "\(items) item\(items == 1 ? "" : "s")")
        case .unsupported:
            return ""
        }
    }
}

// MARK: - Sidebar buttons

private struct SidebarSecondaryButton: View {
    let icon: String?
    let label: String
    let action: () -> Void

    @State private var isHover = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHover ? MagpieColors.btnBgHover(colorScheme) : MagpieColors.btnBg(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(MagpieColors.btnBorder(colorScheme), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onHover { isHover = $0 }
    }
}

private struct SidebarPrimaryButton: View {
    let label: String
    let action: () -> Void
    let disabled: Bool

    @Environment(\.colorScheme) private var colorScheme
    private let settings = SettingsStore.shared

    var body: some View {
        let isDecorative = settings.flavor.isDecorative
        let tokens = settings.flavor.tokens(for: colorScheme)
        let bg: Color = isDecorative ? tokens.accent : MagpieColors.accentInk(colorScheme)
        let fg: Color = isDecorative ? .white : MagpieColors.accentInkFg(colorScheme)

        return Button(action: { if !disabled { action() } }) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text("↩")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.18))
                    )
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bg)
            )
            .opacity(disabled ? 0.45 : 1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
