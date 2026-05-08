import AppKit
import SwiftUI

/// 独立的"放大预览"窗口 — 把当前 focused clip 用大尺寸 + 完整渲染显示在
/// 一个标准 NSWindow 里。视觉语言和主面板一致：
///
/// - 无标题栏（fullSizeContentView + 透明 titlebar），红绿灯按钮直接叠在
///   SwiftUI 内容上方
/// - NSVisualEffectView 毛玻璃背景，跟主面板同 material
/// - flavor token 驱动颜色 / 字体 / 描边：splat 套黄色外框 + 紫色装饰底色，
///   普通主题套低调 hairline 外框
///
/// **快照模式**：show(clip:) 时锁定那条 clip；后续主面板切焦点不会动这个窗口。
/// **独立生命周期**：主面板 hide / Esc 不影响这里，"开大窗 → 收 panel → 慢慢看"。
@MainActor
final class ExpandedPreviewWindowController {
    static let shared = ExpandedPreviewWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<ExpandedPreviewView>?

    private init() {}

    func show(clip: ClipDisplayItem) {
        let view = ExpandedPreviewView(clip: clip, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        })

        if let existing = window {
            hostingController?.rootView = view
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // 自建 container：圆角 NSView + NSVisualEffectView 毛玻璃 + SwiftUI host。
        // 跟主面板 PanelController.makeContentView() 同模式，视觉一致。
        let host = NSHostingController(rootView: view)
        let initialSize = NSSize(width: 860, height: 560)
        let container = NSView(frame: NSRect(origin: .zero, size: initialSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow
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
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.contentView = container
        win.minSize = NSSize(width: 620, height: 420)
        win.isReleasedWhenClosed = false
        // 跟主面板一致：用户在 Settings 选了 dark 就强制 dark；选了 light
        // 就强制 light；Follow System 才让系统接管。否则系统是 light 时这个
        // 窗口会跑 splat-light token，跟主面板 dark splat 视觉断层。
        win.appearance = SettingsStore.shared.theme.appearance
        win.center()

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.hostingController = host
    }

    func close() {
        window?.orderOut(nil)
    }
}

// MARK: - Splat palette helpers (本地副本，跟 PanelController 一致)

private enum SplatPalette {
    static let yellow = Color(red: 1.00, green: 0.91, blue: 0.00)
    static let ink    = Color(red: 0.05, green: 0.05, blue: 0.06)
    static func cream(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}

// MARK: - View

private struct ExpandedPreviewView: View {
    let clip: ClipDisplayItem
    let onClose: () -> Void

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var isSplat: Bool { settings.flavor == .splat }
    private var isDecorative: Bool { settings.flavor.isDecorative }
    private var tokens: FlavorTokens { settings.flavor.tokens(for: colorScheme) }

    var body: some View {
        ZStack {
            // flavor token 给的整面 overlay（splat dark 是近黑色；其他 nil）
            if let overlay = tokens.panelBgOverlay {
                overlay.ignoresSafeArea()
            }
            // 主体内容：顶上留 22pt 让红绿灯按钮不压住 header
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 22)
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                divider
                ScrollView(showsIndicators: true) {
                    fullPreview
                        .frame(maxWidth: 760, alignment: .topLeading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                divider
                footer
            }
        }
        .background(
            // 普通主题（mono/graphite/blue/olive）需要一个底色让毛玻璃别太"暗角"
            Color.primary.opacity(isDecorative ? 0 : (colorScheme == .dark ? 0.02 : 0.0))
        )
        .overlay {
            // 外框：splat 黄 3px / 普通 hairline 0.5px。圆角统一 18 跟 NSView
            // container.layer.cornerRadius 一致，避免双层 mask 露白边。
            if isDecorative {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSplat ? SplatPalette.yellow : tokens.accent.opacity(0.55),
                        lineWidth: isSplat ? 1.5 : 1
                    )
                    .padding(0.75)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(regularBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        // ⌘W / Esc 关窗 — 通过透明按钮挂快捷键
        .background(
            Group {
                Button(action: onClose) { Color.clear }
                    .keyboardShortcut("w", modifiers: .command)
                Button(action: onClose) { Color.clear }
                    .keyboardShortcut(.cancelAction)  // Esc
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            typeBadge
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.system(size: isSplat ? 17 : 16, weight: .semibold))
                    .foregroundStyle(primaryFg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 7) {
                    if clip.pinned {
                        Label(localized(zh: "已固定", en: "Pinned"), systemImage: "pin.fill")
                            .foregroundStyle(isDecorative ? tokens.accent : secondaryFg)
                    }
                    Text(contentSummary)
                    if let app = clip.app, !app.isEmpty {
                        Text("·")
                        Text(shortAppLabel(app))
                    }
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(secondaryFg.opacity(0.78))
            }
            Spacer(minLength: 16)
            Text(timeAgo(clip.createdAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(secondaryFg.opacity(0.7))
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 12, weight: .medium))
            Text(typeDisplayName(clip.type))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(isSplat ? SplatPalette.cream(colorScheme) : (isDecorative ? primaryFg : Color.secondary))
        .padding(.horizontal, isDecorative ? 9 : 0)
        .padding(.vertical, isDecorative ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSplat ? SplatPalette.ink.opacity(0.82) : (isDecorative ? tokens.accent.opacity(0.12) : Color.clear))
        )
    }

    // MARK: Body

    @ViewBuilder
    private var fullPreview: some View {
        switch clip.preview {
        case .text(let body):
            previewBlock {
                Text(body)
                    .font(.system(size: 13, weight: .regular))
                    .lineSpacing(5)
                    .foregroundStyle(primaryFg)
                    .textSelection(.enabled)
            }

        case .code(let body, let lang):
            VStack(alignment: .leading, spacing: 10) {
                if let lang, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(secondaryFg)
                }
                previewBlock {
                    Text(body)
                        .font(.system(size: 12.5, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(primaryFg)
                        .textSelection(.enabled)
                }
            }

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    favicon(letter: host ?? url.host ?? "URL")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(host ?? url.host ?? "URL")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryFg)
                            .lineLimit(1)
                        Text(localized(zh: "链接", en: "Link"))
                            .font(.system(size: 11))
                            .foregroundStyle(secondaryFg.opacity(0.78))
                    }
                }
                previewBlock {
                    Text(url.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(secondaryFg)
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .truncationMode(.middle)
                }
                Link(destination: url) {
                    Label(localized(zh: "在浏览器打开", en: "Open in Browser"), systemImage: "safari")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isDecorative ? tokens.accent.opacity(isSplat ? 1 : 0.18) : Color.accentColor.opacity(0.18))
                        )
                        .foregroundStyle(isSplat ? SplatPalette.ink : (isDecorative ? tokens.accent : Color.accentColor))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
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
            VStack(alignment: .leading, spacing: 14) {
                if let nsimg = NSImage(contentsOfFile: path) {
                    ZStack {
                        ExpandedCheckerboardBackground()
                        Image(nsImage: nsimg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(ruleColor, lineWidth: 0.5)
                    )
                } else {
                    previewBlock {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text(localized(zh: "图片文件丢失", en: "Image file missing"))
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryFg)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                HStack(spacing: 18) {
                    Label("\(w) × \(h)", systemImage: "ruler")
                    Label("\(sizeKB) KB", systemImage: "internaldrive")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(secondaryFg)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(secondaryFg.opacity(0.75))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

        case .unsupported:
            Text(localized(zh: "暂不支持这种剪切板类型", en: "Unsupported clip type"))
                .font(.system(size: 13))
                .foregroundStyle(secondaryFg)
                .italic()
        }
    }

    // MARK: Footer (KeyHint 风格，对齐主面板)

    private var footer: some View {
        HStack(spacing: 14) {
            Text(localized(zh: "选中后 ⌘C 复制 · ⌘W / Esc 关闭", en: "⌘C copies selected · ⌘W / Esc closes"))
                .font(.system(size: 11))
                .foregroundStyle(secondaryFg.opacity(0.85))
            Spacer()
            keyHint(["⌘", "W"], localized(zh: "关闭", en: "Close"))
        }
        .padding(.horizontal, 22)
        .frame(height: 38)
        .background(
            Rectangle().fill(isSplat ? Color.clear : Color.primary.opacity(0.02))
        )
    }

    private func keyHint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSplat ? SplatPalette.yellow : primaryFg.opacity(0.78))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(
                                    isDecorative ? tokens.accent.opacity(isSplat ? 1 : 0.28) : Color.primary.opacity(0.14),
                                    lineWidth: isDecorative ? (isSplat ? 1.2 : 0.6) : 0.5
                                )
                        )
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(secondaryFg)
        }
    }

    // MARK: Helpers

    private var divider: some View {
        Rectangle()
            .fill(ruleColor)
            .frame(height: 0.5)
    }

    private var primaryFg: Color {
        isSplat ? SplatPalette.cream(colorScheme) : Color.primary
    }

    private var secondaryFg: Color {
        isSplat ? SplatPalette.cream(colorScheme).opacity(0.65) : Color.secondary
    }

    private var blockBg: Color {
        if isSplat {
            return Color(red: 0.13, green: 0.04, blue: 0.23).opacity(0.54)
        }
        return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.03)
    }

    private var ruleColor: Color {
        if isDecorative {
            return tokens.accent.opacity(isSplat ? 0.24 : 0.16)
        }
        return Color.primary.opacity(0.10)
    }

    private var regularBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.10)
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

    private var displayTitle: String {
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

    private var contentSummary: String {
        switch clip.preview {
        case .text(let body):
            return localized(zh: "\(body.count) 字符", en: "\(body.count) chars")
        case .code(let body, let lang):
            let language = lang?.uppercased() ?? "CODE"
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
            return "\(language) · \(localized(zh: "\(lines) 行", en: "\(lines) lines"))"
        case .url:
            return localized(zh: "可在浏览器打开", en: "Openable URL")
        case .folder(_, let items):
            return itemCount(items)
        case .file(_, let kind, let sizeKB):
            return "\(kind.uppercased()) · \(sizeKB) KB"
        case .image(_, let w, let h, let sizeKB):
            return "\(w)×\(h) · \(sizeKB) KB"
        case .unsupported:
            return localized(zh: "暂不支持", en: "Unsupported")
        }
    }

    private func shortAppLabel(_ bundleId: String) -> String {
        bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }

    private func previewBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(blockBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ruleColor, lineWidth: 0.5)
        )
    }

    private func favicon(letter: String) -> some View {
        Text(letter.prefix(1).uppercased())
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(isDecorative ? tokens.accent : primaryFg)
            .frame(width: 42, height: 42)
            .background(blockBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ruleColor, lineWidth: 0.5)
            )
    }

    private func fileLikePreview(icon: String, title: String, meta: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isDecorative ? tokens.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(blockBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryFg)
                        .lineLimit(2)
                    Text(meta)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(secondaryFg)
                }
            }
            previewBlock {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(secondaryFg)
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .truncationMode(.middle)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60      { return localized(zh: "刚刚", en: "just now") }
        if secs < 3600    { return localized(zh: "\(Int(secs / 60)) 分钟前", en: "\(Int(secs / 60))m ago") }
        if secs < 86400   { return localized(zh: "\(Int(secs / 3600)) 小时前", en: "\(Int(secs / 3600))h ago") }
        return localized(zh: "\(Int(secs / 86400)) 天前", en: "\(Int(secs / 86400))d ago")
    }
}

private struct ExpandedCheckerboardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 14
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
