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
        let initialSize = NSSize(width: 920, height: 640)
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
        win.minSize = NSSize(width: 560, height: 380)
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
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
                divider
                ScrollView(showsIndicators: true) {
                    fullPreview
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 22)
                }
                divider
                footer
            }
        }
        .background(
            // 普通主题（mono/graphite/blue/olive）需要一个底色让毛玻璃别太"暗角"
            Color.primary.opacity(isSplat ? 0 : (colorScheme == .dark ? 0.02 : 0.0))
        )
        .overlay {
            // 外框：splat 黄 3px / 普通 hairline 0.5px。圆角统一 18 跟 NSView
            // container.layer.cornerRadius 一致，避免双层 mask 露白边。
            if isSplat {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(SplatPalette.yellow, lineWidth: 3)
                    .padding(1.5)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(regularBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 560, minHeight: 380)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                typeBadge
                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(isSplat ? SplatPalette.yellow : Color.secondary)
                }
                Spacer()
                Text(timeAgo(clip.createdAt))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(secondaryFg.opacity(0.7))
                if let app = clip.app, !app.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(app)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(secondaryFg)
                        .lineLimit(1)
                }
            }
            if let title = clip.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: isSplat ? 24 : 20, weight: .semibold))
                    .foregroundStyle(primaryFg)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 12, weight: .medium))
            Text(clip.type.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(isSplat ? SplatPalette.cream(colorScheme) : Color.secondary)
        .padding(.horizontal, isSplat ? 10 : 0)
        .padding(.vertical, isSplat ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSplat ? SplatPalette.ink : Color.clear)
        )
    }

    // MARK: Body

    @ViewBuilder
    private var fullPreview: some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(primaryFg)
                .textSelection(.enabled)

        case .code(let body, let lang):
            VStack(alignment: .leading, spacing: 10) {
                if let lang, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(secondaryFg)
                }
                Text(body)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(primaryFg)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(codeBg)
                    )
            }

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 10) {
                Text(host ?? url.host ?? "")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(primaryFg)
                Text(url.absoluteString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(secondaryFg)
                    .textSelection(.enabled)
                Link(destination: url) {
                    Label("在浏览器打开", systemImage: "safari")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(isSplat ? SplatPalette.yellow : Color.accentColor.opacity(0.18))
                        )
                        .foregroundStyle(isSplat ? SplatPalette.ink : Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

        case .folder(let path, let items):
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isSplat ? SplatPalette.yellow : Color.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(primaryFg)
                Text("\(items) item\(items == 1 ? "" : "s")")
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryFg)
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(secondaryFg)
                    .textSelection(.enabled)
            }

        case .file(let path, let kind, let sizeKB):
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(isSplat ? SplatPalette.yellow : Color.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(primaryFg)
                Text("\(kind.uppercased()) · \(sizeKB) KB")
                    .font(.system(size: 13))
                    .foregroundStyle(secondaryFg)
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(secondaryFg)
                    .textSelection(.enabled)
            }

        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 14) {
                if let nsimg = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isSplat ? SplatPalette.yellow.opacity(0.5) : Color.primary.opacity(0.08),
                                    lineWidth: isSplat ? 1.5 : 0.5
                                )
                        )
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text("图片文件丢失")
                                .font(.system(size: 12))
                                .foregroundStyle(secondaryFg)
                        }
                        Spacer()
                    }
                    .padding(60)
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
            Text("Unsupported clip type")
                .font(.system(size: 13))
                .foregroundStyle(secondaryFg)
                .italic()
        }
    }

    // MARK: Footer (KeyHint 风格，对齐主面板)

    private var footer: some View {
        HStack(spacing: 14) {
            Text("选中后 ⌘C 复制 · ⌘W / Esc 关闭")
                .font(.system(size: 11))
                .foregroundStyle(secondaryFg.opacity(0.85))
            Spacer()
            keyHint(["⌘", "W"], "关闭")
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
                                    isSplat ? SplatPalette.yellow : Color.primary.opacity(0.14),
                                    lineWidth: isSplat ? 1.2 : 0.5
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
            .fill(isSplat ? SplatPalette.yellow.opacity(0.35) : Color.primary.opacity(0.10))
            .frame(height: isSplat ? 1.0 : 0.5)
    }

    private var primaryFg: Color {
        isSplat ? SplatPalette.cream(colorScheme) : Color.primary
    }

    private var secondaryFg: Color {
        isSplat ? SplatPalette.cream(colorScheme).opacity(0.65) : Color.secondary
    }

    private var codeBg: Color {
        isSplat
            ? SplatPalette.ink.opacity(0.55)
            : Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)
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

    private func timeAgo(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60      { return "\(Int(secs))s 前" }
        if secs < 3600    { return "\(Int(secs / 60))m 前" }
        if secs < 86400   { return "\(Int(secs / 3600))h 前" }
        return "\(Int(secs / 86400))d 前"
    }
}
