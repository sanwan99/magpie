import AppKit
import SwiftUI

/// Owns the lifecycle of the Magpie panel: positioning at the bottom of the active screen,
/// hosting SwiftUI content with vibrancy, and the show/hide slide animation.
@MainActor
final class PanelController {
    private let panel: PanelWindow
    private let viewModel: ClipsViewModel
    private let snippetsViewModel: SnippetsViewModel
    private let settings = SettingsStore.shared
    private let frontmost = FrontmostTracker()
    private let biometric = BiometricGate()
    private var keyMonitor: Any?
    private var afterHide: (() -> Void)?
    private var settingsObservationTask: Task<Void, Never>?
    private weak var visualEffectView: NSVisualEffectView?
    private(set) var isVisible: Bool = false

    /// Panel size — wide enough for layout body + Detail Pane side-by-side.
    /// Height = topBar(~86) + divider + 220 卡 + Stripe v-padding 32 + footer(34)
    /// ≈ 372，取 380 留 8pt 呼吸量。codex 之前调到 420 让 Stripe 卡片上下各
    /// 浮 25pt 空白，视觉上"卡片飘在中间"——降回 380 让卡片几乎贴满 body。
    static let panelSize = NSSize(width: 1200, height: 380)
    /// Distance from the bottom of the active screen.
    /// 0 = 完全贴 dock 上沿（visibleFrame 已扣掉 dock 高度）。
    static let bottomInset: CGFloat = 0

    init(viewModel: ClipsViewModel, snippetsViewModel: SnippetsViewModel) {
        self.viewModel = viewModel
        self.snippetsViewModel = snippetsViewModel
        let frame = NSRect(origin: .zero, size: Self.panelSize)
        self.panel = PanelWindow(contentRect: frame)
        self.panel.contentView = makeContentView()
        applyAppearance()
        applyVibrancy()
        wireKeyboard()
        observeSettings()

        viewModel.onPasteRequest = { [weak self] in
            self?.paste()
        }
        snippetsViewModel.onPasteRequest = { [weak self] snippet in
            self?.pasteSnippet(snippet)
        }
    }

    // MARK: - Snippets paste flow

    /// Paste a snippet's body into the previously frontmost app.
    /// Same shape as `executePaste` but writes a string directly (no PreviewContent dispatch).
    private func pasteSnippet(_ snippet: Snippet) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snippet.body, forType: .string)
        let target = frontmost.savedTarget
        NSLog("[snippet] pasting %d chars into %@", snippet.body.count, target?.bundleIdentifier ?? "?")
        snippetsViewModel.drawerVisible = false
        afterHide = {
            Paster.paste(into: target)
        }
        hide()
    }

    /// Open the snippet editor for a brand-new snippet.
    fileprivate func openNewSnippetEditor() {
        SnippetEditorWindowController.shared.open(
            snippet: Snippet.newDraft(),
            isNew: true,
            onSave: { [weak self] s in
                self?.snippetsViewModel.upsert(s)
            },
            onDelete: { /* no-op for brand-new snippets */ }
        )
    }

    /// Open the editor on an existing snippet.
    fileprivate func openEditor(for snippet: Snippet) {
        SnippetEditorWindowController.shared.open(
            snippet: snippet,
            isNew: false,
            onSave: { [weak self] s in
                self?.snippetsViewModel.upsert(s)
            },
            onDelete: { [weak self] in
                self?.snippetsViewModel.delete(id: snippet.id)
            }
        )
    }

    /// Subscribe to SettingsStore changes via Observation tracking. Each
    /// withObservationTracking is a one-shot subscription, so we re-arm in
    /// the closure to keep listening.
    private func observeSettings() {
        let store = settings
        func track() {
            withObservationTracking {
                _ = store.theme
                _ = store.vibrancy
                _ = store.panelOpacity
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.applyAppearance()
                    self?.applyVibrancy()
                    self?.applyOpacity()
                    track()
                }
            }
        }
        track()
    }

    private func applyAppearance() {
        panel.appearance = settings.theme.appearance
    }

    private func applyVibrancy() {
        guard let effect = visualEffectView else { return }
        effect.material = mapVibrancy(settings.vibrancy)
    }

    /// 面板可见时直接应用新的透明度。隐藏中不动 alphaValue（hide 动画自己负责
    /// 把它降到 0），下次 show() 会用最新 panelOpacity 作为目标值。
    private func applyOpacity() {
        guard isVisible else { return }
        panel.animator().alphaValue = settings.panelOpacity
    }

    /// 0…60 slider → NSVisualEffectView material.
    /// Three buckets so each step is visually distinct.
    private func mapVibrancy(_ value: Double) -> NSVisualEffectView.Material {
        switch value {
        case ..<20:    return .windowBackground
        case 20..<45:  return .menu
        default:       return .hudWindow
        }
    }

    // MARK: - Show / Hide

    func toggle() {
        if isVisible {
            hide()
        } else {
            // Auth gate is async (Touch ID may prompt); wrap in Task.
            // Default biometric path (no useTouchID, or already unlocked) is
            // synchronous-fast — Task overhead is negligible.
            Task { @MainActor in
                let ok = await biometric.authenticateIfNeeded(reason: "Unlock Magpie clipboard")
                guard ok else { return }
                show()
            }
        }
    }

    func show() {
        guard !isVisible else { return }
        // Snapshot the frontmost app *before* the panel becomes key, so paste
        // can target the correct app even if .nonactivatingPanel ever flakes.
        frontmost.snapshot()
        viewModel.refresh()

        positionAtBottomCenter()
        let target = panel.frame
        let start = target.offsetBy(dx: 0, dy: -target.height - 16)
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1.0)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = settings.panelOpacity
        }
        isVisible = true
    }

    func hide() {
        guard isVisible else {
            // Even if we weren't visible, run any pending after-hide hook so
            // paste flows can't get stranded.
            afterHide?()
            afterHide = nil
            return
        }
        let target = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height - 16)
        // Drop SwiftUI's first responder (the SearchField) immediately, otherwise
        // a fast follow-up CGEvent ⌘V would land on the panel's text field
        // instead of the app behind us.
        panel.makeFirstResponder(nil)
        let pendingAfter = afterHide
        afterHide = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // orderOut tears down keyWindow + revokes frontmost focus from the panel.
            // Only after this is it safe to simulate ⌘V into the previously frontmost app.
            self?.panel.orderOut(nil)
            pendingAfter?()
        })
        isVisible = false
    }

    // MARK: - Paste flow

    /// Paste the currently focused clip into the previously frontmost app.
    private func paste() {
        guard let clip = viewModel.focusedClip else { return }
        executePaste(clip, writePasteboard: { Paster.writeToPasteboard($0) })
    }

    /// Paste the focused file/folder path as plain text.
    private func pastePath() {
        guard let clip = viewModel.focusedClip else { return }
        executePaste(clip, writePasteboard: { Paster.writePathToPasteboard($0) })
    }

    /// Paste the Nth clip directly (⌘1…⌘9).
    private func pasteAt(_ index: Int) {
        guard let clip = viewModel.clip(at: index) else { return }
        viewModel.focusedIndex = index
        executePaste(clip, writePasteboard: { Paster.writeToPasteboard($0) })
    }

    private func executePaste(
        _ clip: ClipDisplayItem,
        writePasteboard: @MainActor (ClipDisplayItem) -> String?
    ) {
        let target = frontmost.savedTarget
        guard let written = writePasteboard(clip), !written.isEmpty else {
            NSLog("[paste] clip has no pasteable content (id=%@ type=%@)", clip.id, clip.type.rawValue)
            return
        }
        NSLog("[paste] writing %d chars (type=%@) into pasteboard, target=%@",
              written.count, clip.type.rawValue, target?.bundleIdentifier ?? "?")

        // Queue Mode: paste, advance focus, and re-open the panel for the
        // next paste. The panel briefly flashes during the transition; the
        // user's hand stays on ↵ for batch fills.
        let inQueue = viewModel.queueMode
        afterHide = { [weak self, weak viewModel] in
            Paster.paste(into: target)
            if inQueue {
                viewModel?.advanceFocusForQueue()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    self?.show()
                }
            }
        }
        hide()
    }

    // MARK: - Layout

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let x = visible.midX - size.width / 2
        let y = visible.minY + Self.bottomInset
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
    }

    // MARK: - Keyboard wiring

    private func wireKeyboard() {
        panel.onCancel = { [weak self] in
            self?.handleCancel()
        }
        panel.onPaste = { [weak self] in
            self?.paste()
        }
        panel.onMoveBack = { [weak self] in
            self?.viewModel.moveBack()
        }
        panel.onMoveForward = { [weak self] in
            self?.viewModel.moveForward()
        }
        panel.onPasteAtIndex = { [weak self] index in
            self?.pasteAt(index)
        }
        panel.onTogglePin = { [weak self] in
            self?.viewModel.toggleFocusedPin()
        }

        // SwiftUI's TextField (now hosting the search field) sits at the front of
        // the responder chain and swallows several command keystrokes that we want
        // to handle at the panel level (⌘D for pin, ⌘1-9 for quick paste, Esc for
        // the clear-cascade). Install a local NSEvent monitor that catches these
        // before SwiftUI sees them, but only while the panel is the key window.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.panel.isKeyWindow else { return event }
            return self.handleLocalKey(event)
        }
    }

    private func handleLocalKey(_ event: NSEvent) -> NSEvent? {
        let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command

        // Esc — clear-cascade (always wins, even while typing in the search field).
        if event.keyCode == 53 {
            handleCancel()
            return nil
        }

        // Return / Numpad Enter — paste focused clip (always wins).
        if event.keyCode == 36 || event.keyCode == 76 {
            paste()
            return nil
        }

        if cmd, let chars = event.charactersIgnoringModifiers {
            // ⌘D toggle pin
            if chars == "d" {
                viewModel.toggleFocusedPin()
                return nil
            }
            // ⌘\ cycle layout (Stripe → Stack → Grid → Stripe)
            if chars == "\\" {
                withAnimation(.easeOut(duration: 0.18)) {
                    viewModel.cycleLayout()
                }
                return nil
            }
            // ⌘, open Settings
            if chars == "," {
                SettingsWindowController.shared.show()
                return nil
            }
            // ⌘S toggle Snippets drawer
            if chars == "s" {
                withAnimation(.easeOut(duration: 0.18)) {
                    snippetsViewModel.toggleDrawer()
                }
                return nil
            }
            // ⌘O 在独立窗口放大查看当前 focused clip（detail pane 开关无所谓）
            if chars == "o" {
                if let clip = viewModel.focusedClip {
                    ExpandedPreviewWindowController.shared.show(clip: clip)
                }
                return nil
            }
            // ⌘Q toggle Queue Mode (only when panel is key — otherwise it's the
            // user's standard "Quit App" shortcut hitting the frontmost app).
            if chars == "q" {
                viewModel.toggleQueueMode()
                NSLog("[queue] queueMode=%d", viewModel.queueMode ? 1 : 0)
                return nil
            }
            // ⌘1…⌘9 quick paste at index
            if chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               let digit = Int(String(scalar)),
               (1...9).contains(digit) {
                pasteAt(digit - 1)
                return nil
            }
        }

        // Space toggles the Detail Pane.
        // Trick: SearchField auto-focuses on panel show, so first-responder is
        // always NSTextView and `isTextFieldEditing()` always reports true.
        // Use `searchInput.isEmpty` instead — only intercept Space when the
        // search field has no content. Once the user is mid-query (e.g.
        // typing `react hook`), Space falls through as a literal character.
        if event.keyCode == 49,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [],
           viewModel.searchInput.isEmpty {
            // spring + scale 让关闭/打开有"啪"的弹性反馈（之前 0.18s easeOut
            // 太轻飘，看不清自己刚按了 Space）。
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                viewModel.toggleDetailPane()
            }
            return nil
        }

        // Arrow keys: always navigate cards. The search field is short enough
        // that ceding caret movement to it isn't worth losing primary nav.
        switch event.keyCode {
        case 123, 126: // Left, Up
            viewModel.moveBack()
            return nil
        case 124, 125: // Right, Down
            viewModel.moveForward()
            return nil
        default:
            break
        }

        return event
    }

    /// True while a SwiftUI TextField (or similar) is actively editing.
    /// SwiftUI uses `NSTextView` as the field editor when a TextField is focused.
    private func isTextFieldEditing() -> Bool {
        guard let fr = panel.firstResponder else { return false }
        return fr is NSTextView
    }

    /// Esc cascade per spec §06: clear search → clear filters → hide panel.
    private func handleCancel() {
        if !viewModel.searchInput.isEmpty {
            viewModel.searchInput = ""
            viewModel.refresh()
            return
        }
        if viewModel.typeFilter != nil {
            viewModel.typeFilter = nil
            return
        }
        if viewModel.pinnedOnly {
            viewModel.pinnedOnly = false
            return
        }
        hide()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    // MARK: - Content

    private func makeContentView() -> NSView {
        let host = NSHostingView(rootView: PanelContentView(
            viewModel: viewModel,
            snippetsViewModel: snippetsViewModel,
            onPaste: { [weak self] in self?.paste() },
            onPastePath: { [weak self] in self?.pastePath() },
            onCreateSnippet: { [weak self] in self?.openNewSnippetEditor() },
            onEditSnippet: { [weak self] s in self?.openEditor(for: s) }
        ))
        let container = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = mapVibrancy(settings.vibrancy)
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)
        self.visualEffectView = effect

        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        return container
    }
}

/// Top-level panel content — top bar (search + filter rail) + body
/// (active layout + optional Detail Pane).
private struct PanelContentView: View {
    let viewModel: ClipsViewModel
    let snippetsViewModel: SnippetsViewModel
    let onPaste: () -> Void
    let onPastePath: () -> Void
    let onCreateSnippet: () -> Void
    let onEditSnippet: (Snippet) -> Void

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let overlay = settings.flavor.tokens(for: colorScheme).panelBgOverlay {
                overlay.ignoresSafeArea()
            }
            // Decorative flavor chrome sits above the overlay but below
            // content, with hit testing off.
            if settings.flavor.isDecorative {
                FlavorDecorations(flavor: settings.flavor)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                topBar
                if snippetsViewModel.drawerVisible {
                    Divider().opacity(0.4)
                    SnippetsDrawer(
                        viewModel: snippetsViewModel,
                        onCreate: onCreateSnippet,
                        onEdit: onEditSnippet
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Divider().opacity(0.4)
                body(for: viewModel.activeLayout)
                    .frame(maxHeight: .infinity)
                PanelFooter(viewModel: viewModel)
            }
        }
        .overlay {
            let tokens = settings.flavor.tokens(for: colorScheme)
            // 主面板外框：splat 改用 hairline 灰，跟普通主题对齐 —— 用户反馈
            // "黄色条纹太抢戏"。splat 身份感保留在焦点卡片黄底 + 章鱼装饰 +
            // 紫 paste 按钮。其他装饰主题继续用 accent 1pt 描边。
            if settings.flavor == .splat {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(regularPanelBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            } else if settings.flavor.isDecorative {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(tokens.accent.opacity(0.55), lineWidth: 1)
                    .padding(0.5)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(regularPanelBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
        // 主面板焦点变化时联动放大预览窗口（仅在窗口已打开时生效）。
        // updateIfOpen 内部判断窗口可见性，关掉的窗口不会自己又被拉起来。
        .onChange(of: viewModel.focusedClip?.id) { _, _ in
            if let clip = viewModel.focusedClip {
                ExpandedPreviewWindowController.shared.updateIfOpen(clip: clip)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Magpie")
                    .font(.system(size: 13, weight: .bold))
                SearchField(viewModel: viewModel)
                if viewModel.queueMode {
                    QueueIndicator()
                }
                SnippetsToggle(viewModel: snippetsViewModel)
                LayoutSwitcher(viewModel: viewModel)
                DetailPaneToggle(viewModel: viewModel)
            }
            filterRail
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var filterRail: some View {
        FilterRail(viewModel: viewModel)
            .background(alignment: .center) {
                if filterRailMistVisible {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: filterRailMistFill, location: 0.24),
                            .init(color: filterRailMistFill, location: 0.76),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 42)
                    .padding(.horizontal, -18)
                    .blur(radius: 5)
                    .allowsHitTesting(false)
                }
            }
    }

    private var filterRailMistVisible: Bool {
        settings.flavor.isDecorative && settings.flavor != .splat
    }

    private var filterRailMistFill: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.26)
            : Color.white.opacity(0.62)
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for layout: ActiveLayout) -> some View {
        if viewModel.clips.isEmpty {
            emptyState
        } else {
            HStack(spacing: 0) {
                layoutView(layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if viewModel.detailPaneVisible {
                    detailSeparator
                        .transition(.opacity)
                    DetailPane(
                        clip: viewModel.focusedClip,
                        onPaste: onPaste,
                        onPastePath: onPastePath,
                        onTogglePin: { viewModel.toggleFocusedPin() },
                        onExpand: {
                            guard let clip = viewModel.focusedClip else { return }
                            ExpandedPreviewWindowController.shared.show(clip: clip)
                        }
                    )
                    .frame(width: detailWidth(for: layout))
                    // move + opacity + 轻微缩放：关闭时整面板向右滑出 + 透明
                    // + 缩到 94%，配合 spring 形成"啪"地一下的明显反馈。
                    .transition(
                        .move(edge: .trailing)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.94, anchor: .trailing))
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var detailSeparator: some View {
        if settings.flavor == .splat {
            VerticalDashedLine()
                .stroke(splatYellow, style: StrokeStyle(lineWidth: 2, dash: [6, 7]))
                .frame(width: 16)
                .padding(.vertical, 18)
        } else if settings.flavor.isDecorative {
            Rectangle()
                .fill(settings.flavor.tokens(for: colorScheme).accent.opacity(0.18))
                .frame(width: 0.7)
                .padding(.vertical, 18)
        } else {
            Divider().opacity(0.4)
        }
    }

    @ViewBuilder
    private func layoutView(_ layout: ActiveLayout) -> some View {
        switch layout {
        case .stripe: StripeLayout(viewModel: viewModel)
        case .stack:  StackLayout(viewModel: viewModel)
        case .grid:   GridLayout(viewModel: viewModel)
        }
    }

    private func detailWidth(for layout: ActiveLayout) -> CGFloat {
        switch layout {
        case .stripe: return 360  // spec §08
        case .stack:  return 380  // spec §08 — wider for richer detail
        case .grid:   return 360
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: viewModel.totalClipCount == 0 ? "tray" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(viewModel.totalClipCount == 0 ? "No clips yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.totalClipCount == 0
                 ? "Copy something — text, code, a link, or a folder path — to get started."
                 : "Try a different search or clear filters with Esc.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splatYellow: Color {
        Color(red: 1.00, green: 0.91, blue: 0.00)
    }

    private var regularPanelBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.08)
    }
}

private struct VerticalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct PanelFooter: View {
    let viewModel: ClipsViewModel

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let text = SettingsText(language: settings.language)
        HStack(spacing: 12) {
            focusedMeta
            Spacer(minLength: 8)
            if viewModel.queueMode {
                Text(text.hintQueueMode)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(settings.flavor == .splat ? splatInk : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(settings.flavor == .splat ? splatYellow : Color.orange.opacity(0.18)))
            }
            KeyHint(keys: ["↑", "↓"], label: text.hintNavigate)
            KeyHint(keys: ["↵"], label: text.hintPaste)
            KeyHint(keys: ["Space"], label: viewModel.detailPaneVisible ? text.hintCloseDetail : text.hintPreview)
            KeyHint(keys: ["⌘", "D"], label: text.hintPin)
            KeyHint(keys: ["Esc"], label: text.hintClose)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(settings.flavor == .splat ? splatCream : Color.secondary)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(
            Rectangle()
                .fill(settings.flavor == .splat ? Color.clear : Color.primary.opacity(0.018))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(settings.flavor == .splat ? Color.clear : footerHairline)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var focusedMeta: some View {
        if let clip = viewModel.focusedClip {
            HStack(spacing: 7) {
                Text(clip.type.rawValue.capitalized)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.flavor == .splat ? splatCream : Color.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                AppDot(app: clip.app)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(timeAgo(clip.createdAt)) ago")
                    .monospacedDigit()
            }
            .lineLimit(1)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60     { return "now" }
        if secs < 3600   { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86_400))d"
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatCream: Color { colorScheme == .dark ? Color(red: 1.00, green: 0.97, blue: 0.85) : Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var footerHairline: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.07)
    }
}

private struct AppDot: View {
    let app: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.20, green: 0.53, blue: 1.00))
                .frame(width: 7, height: 7)
            Text(shortAppLabel)
        }
    }

    private var shortAppLabel: String {
        guard let app, !app.isEmpty else { return "Unknown" }
        return app.split(separator: ".").last.map(String.init) ?? app
    }
}

private struct KeyHint: View {
    let keys: [String]
    let label: String

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(settings.flavor == .splat ? splatYellow : Color.primary.opacity(0.72))
                        .padding(.horizontal, key.count > 1 ? 5 : 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(settings.flavor == .splat ? Color(red: 0.08, green: 0.02, blue: 0.12) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(settings.flavor == .splat ? splatYellow : Color.primary.opacity(0.12), lineWidth: settings.flavor == .splat ? 1.5 : 0.5)
                        )
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(settings.flavor == .splat ? splatCream : Color.secondary)
        }
        .lineLimit(1)
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatCream: Color { colorScheme == .dark ? Color(red: 1.00, green: 0.97, blue: 0.85) : Color(red: 0.05, green: 0.05, blue: 0.06) }
}

// MARK: - Layout switcher (top-bar control)

private struct LayoutSwitcher: View {
    @Bindable var viewModel: ClipsViewModel

    var body: some View {
        Menu {
            ForEach(ActiveLayout.allCases, id: \.self) { layout in
                Button {
                    viewModel.activeLayout = layout
                } label: {
                    HStack {
                        Image(systemName: icon(layout))
                        Text(layout.displayName)
                        if viewModel.activeLayout == layout {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon(viewModel.activeLayout))
                    .font(.system(size: 11))
                Text("⌘\\")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch layout (⌘\\)")
    }

    private func icon(_ layout: ActiveLayout) -> String {
        switch layout {
        case .stripe: return "rectangle.split.3x1"
        case .stack:  return "list.bullet.rectangle"
        case .grid:   return "square.grid.2x2"
        }
    }
}

// MARK: - Queue Mode indicator

private struct QueueIndicator: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 10))
            Text("QUEUE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
            Text("⌘Q")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .opacity(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(.orange)
        .background(Capsule().fill(Color.orange.opacity(0.18)))
        .overlay(Capsule().strokeBorder(Color.orange.opacity(0.6), lineWidth: 0.5))
        .help("Queue Mode is on — paste auto-advances focus. Press ⌘Q to turn off.")
    }
}

// MARK: - Snippets toggle (top-bar control)

private struct SnippetsToggle: View {
    @Bindable var viewModel: SnippetsViewModel

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                viewModel.toggleDrawer()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.drawerVisible ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 11))
                Text("⌘S")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .help("Toggle Snippets drawer (⌘S)")
    }
}

// MARK: - Detail pane toggle (top-bar control)

private struct DetailPaneToggle: View {
    @Bindable var viewModel: ClipsViewModel

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
                viewModel.toggleDetailPane()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: viewModel.detailPaneVisible ? "sidebar.right" : "sidebar.squares.right")
                    .font(.system(size: 11))
                Text("Space")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderless)
        .help("Toggle detail pane (Space)")
    }
}
