import AppKit
import SwiftUI
import Translation
import NaturalLanguage
import UniformTypeIdentifiers

@MainActor
final class ScreenshotPinnedWindow: NSWindowController, NSWindowDelegate {
    private static var openWindows: [UUID: ScreenshotPinnedWindow] = [:]
    private let id = UUID()
    private let data: Data
    private let image: NSImage
    private var sharingPicker: NSSharingServicePicker?

    static func show(data: Data, near rect: CGRect, share: Bool = false) {
        guard let controller = ScreenshotPinnedWindow(data: data, near: rect) else { return }
        openWindows[controller.id] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if share { controller.shareImage() }
    }

    private init?(data: Data, near rect: CGRect) {
        guard let image = NSImage(data: data) else { return nil }
        self.data = data; self.image = image
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let limit = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let logicalSize = rect.size.width > 0 ? rect.size : image.size
        let scale = min(1, (limit.width * 0.8) / logicalSize.width, (limit.height * 0.8 - 40) / logicalSize.height)
        let size = CGSize(width: max(220, logicalSize.width * scale), height: max(120, logicalSize.height * scale) + 40)
        let frame = CGRect(x: min(max(limit.minX, rect.minX), limit.maxX - size.width),
                           y: min(max(limit.minY, rect.minY), limit.maxY - size.height), width: size.width, height: size.height)
        let panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = SettingsStore.shared.language.pick(zh: "贴图 · 双击关闭", en: "Pinned image · Double-click to close")
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 220, height: 160)
        super.init(window: panel)
        panel.delegate = self
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        let view = ScreenshotPinnedImageView(frame: CGRect(x: 0, y: 40, width: size.width, height: size.height - 40))
        view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        view.autoresizingMask = [.width, .height]
        view.onCopy = { [weak self] in self?.copyImage() }
        view.onSave = { [weak self] in self?.saveImage() }
        view.onShare = { [weak self] in self?.shareImage() }
        content.addSubview(view)
        let language = SettingsStore.shared.language
        for (index, entry) in [(language.pick(zh: "复制", en: "Copy"), #selector(copyImage)),
                               (language.pick(zh: "保存", en: "Save"), #selector(saveImage)),
                               (language.pick(zh: "分享", en: "Share"), #selector(shareImage))].enumerated() {
            let button = NSButton(title: entry.0, target: self, action: entry.1)
            button.frame = CGRect(x: 8 + index * 68, y: 7, width: 64, height: 26)
            button.bezelStyle = .rounded
            content.addSubview(button)
        }
        panel.contentView = content; panel.makeFirstResponder(view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { Self.openWindows[id] = nil }
    @objc private func copyImage() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .png)
    }
    @objc private func saveImage() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Magpie.png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try self.data.write(to: url, options: .atomic) }
            catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
    @objc private func shareImage() {
        guard let view = window?.contentView else { return }
        sharingPicker = NSSharingServicePicker(items: [image])
        sharingPicker?.show(relativeTo: CGRect(x: 145, y: 5, width: 60, height: 30), of: view, preferredEdge: .maxY)
    }
}

final class ScreenshotPinnedImageView: NSImageView {
    private var originalSize: CGSize?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onShare: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.close() }
        else { window?.makeFirstResponder(self); window?.performDrag(with: event) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if originalSize == nil { originalSize = window?.frame.size }
    }
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > 0 else { return }
        let factor = event.hasPreciseScrollingDeltas
            ? pow(CGFloat(1.01), min(40, max(-40, event.scrollingDeltaY)))
            : (event.scrollingDeltaY > 0 ? 1.1 : 1 / 1.1)
        zoom(factor)
    }
    private func zoom(_ factor: CGFloat) {
        guard let size = window?.frame.size else { return }
        resize(CGSize(width: size.width * factor, height: size.height * factor))
    }
    private func resize(_ size: CGSize) {
        guard let window else { return }
        let current = window.frame
        let limit = window.screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let width = min(limit.width, max(220, size.width))
        let height = min(limit.height, max(160, size.height))
        let x = min(max(limit.minX, current.midX - width / 2), limit.maxX - width)
        let y = min(max(limit.minY, current.midY - height / 2), limit.maxY - height)
        window.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": onCopy?()
        case "s": event.modifierFlags.contains(.shift) ? onShare?() : onSave?()
        case "w": window?.close()
        case "+", "=": zoom(1.1)
        case "-": zoom(1 / 1.1)
        case "0": if let originalSize { resize(originalSize) }
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { window?.close() }
        else if (123...126).contains(event.keyCode), let window {
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 30 : 10
            var frame = window.frame
            if event.keyCode == 123 { frame.origin.x -= step }
            if event.keyCode == 124 { frame.origin.x += step }
            if event.keyCode == 125 { frame.origin.y -= step }
            if event.keyCode == 126 { frame.origin.y += step }
            let limit = window.screen?.visibleFrame ?? frame
            frame.origin.x = min(max(limit.minX, frame.minX), limit.maxX - frame.width)
            frame.origin.y = min(max(limit.minY, frame.minY), limit.maxY - frame.height)
            window.setFrame(frame, display: true)
        } else { super.keyDown(with: event) }
    }
}

@MainActor
final class ScreenshotTextResultModel: ObservableObject {
    @Published var text = ""
    @Published var translated = ""
    @Published var error: String?
    @Published var loading = true
    @Published var translating = false
    @Published var source = "en"
    @Published var target = "zh-Hans"
    let language: AppLanguage
    let startsWithTranslation: Bool
    private var task: Task<Void, Never>?

    init(image: CGImage, language: AppLanguage, translate: Bool) {
        self.language = language; startsWithTranslation = translate
        task = Task { [weak self] in
            do {
                let result = try await ScreenshotAnalysis.analyze(image)
                guard let self, !Task.isCancelled else { return }
                self.text = result.text
                let detected = NLLanguageRecognizer.dominantLanguage(for: result.text)?.rawValue ?? "en"
                self.source = detected
                self.target = detected.hasPrefix("zh") ? "en" : "zh-Hans"
                self.loading = false
            } catch {
                guard let self else { return }
                self.error = error.localizedDescription; self.loading = false
            }
        }
    }
    func cancel() { task?.cancel() }
    func copy(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
}

@MainActor
final class ScreenshotTextWindow: NSWindowController, NSWindowDelegate {
    private static var openWindows: [UUID: ScreenshotTextWindow] = [:]
    private let id = UUID()
    private let model: ScreenshotTextResultModel
    static func show(data: Data, translate: Bool) {
        guard let bitmap = NSBitmapImageRep(data: data), let image = bitmap.cgImage else { return }
        let controller = ScreenshotTextWindow(image: image, translate: translate)
        openWindows[controller.id] = controller
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private init(image: CGImage, translate: Bool) {
        let language = SettingsStore.shared.language
        model = ScreenshotTextResultModel(image: image, language: language, translate: translate)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 540),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = language.pick(zh: "截图文字", en: "Screenshot text")
        window.minSize = CGSize(width: 480, height: 400)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScreenshotTextResultView(model: model))
        window.center()
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { model.cancel(); Self.openWindows[id] = nil }
}

private struct ScreenshotTextResultView: View {
    @ObservedObject var model: ScreenshotTextResultModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.language.pick(zh: "识别结果", en: "Recognized text")).font(.headline)
                Spacer()
                Button(model.language.pick(zh: "复制文字", en: "Copy text")) { model.copy(model.text) }.disabled(model.text.isEmpty)
            }
            if model.loading { ProgressView(model.language.pick(zh: "正在本机识别…", en: "Recognizing on this Mac…")) }
            TextEditor(text: $model.text).font(.system(size: 15)).frame(minHeight: 130)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.25)))
            if !model.loading, model.text.isEmpty, model.error == nil {
                Text(model.language.pick(zh: "没有识别到文字，可缩小选区后重试。", en: "No text found. Try a smaller region.")).foregroundStyle(.secondary)
            }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if #available(macOS 15.0, *) { ScreenshotTranslationControls(model: model) }
            else { Text(model.language.pick(zh: "系统本地翻译需要 macOS 15 或更新版本。", en: "Local translation requires macOS 15 or later.")).foregroundStyle(.secondary) }
        }.padding(18)
    }
}

@available(macOS 15.0, *)
private struct ScreenshotTranslationControls: View {
    @ObservedObject var model: ScreenshotTextResultModel
    @State private var configuration: TranslationSession.Configuration?
    @State private var needsDownload = false
    @State private var allowDownload = false
    @State private var input = ""
    @State private var languages = [("en", "English"), ("zh", "简体中文"), ("zh-Hant", "繁體中文"),
                             ("ja", "日本語"), ("ko", "한국어"), ("fr", "Français"), ("de", "Deutsch"), ("es", "Español")]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(model.language.pick(zh: "原文", en: "From"), selection: Binding(get: { Locale.Language(identifier: model.source).minimalIdentifier }, set: { model.source = $0 })) {
                    ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker(model.language.pick(zh: "译文", en: "To"), selection: Binding(get: { Locale.Language(identifier: model.target).minimalIdentifier }, set: { model.target = $0 })) {
                    ForEach(languages, id: \.0) { Text($0.1).tag($0.0) }
                }
                Button(model.language.pick(zh: "翻译", en: "Translate")) { begin(download: false) }
                    .disabled(model.loading || model.translating || model.text.isEmpty)
            }.disabled(model.loading || model.translating)
            if needsDownload {
                Text(model.language.pick(zh: "所需离线语言包尚未安装，点击后由系统询问是否下载。", en: "Offline languages are missing. macOS will ask before downloading."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(model.language.pick(zh: "下载语言包并翻译", en: "Download languages and translate")) { begin(download: true) }
            }
            Text(model.language.pick(zh: "系统本地翻译；Apple 可能收集语言等使用指标，不包含原文和译文。", en: "Translation runs locally. Apple may collect language usage metrics, excluding source and translated text."))
                .font(.caption).foregroundStyle(.secondary)
            if model.translating { ProgressView() }
            if !model.translated.isEmpty {
                TextEditor(text: $model.translated).font(.system(size: 15)).frame(minHeight: 120)
                Button(model.language.pick(zh: "复制译文", en: "Copy translation")) { model.copy(model.translated) }
            }
        }
        .task {
            let supported = await LanguageAvailability().supportedLanguages
            languages = supported.map {
                let id = $0.minimalIdentifier
                return (id, Locale(identifier: model.language == .zhHans ? "zh_CN" : "en_US").localizedString(forIdentifier: id) ?? id)
            }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        }
        .onChange(of: model.loading) { _, loading in
            if !loading, model.startsWithTranslation, !model.text.isEmpty { begin(download: false) }
        }
        .translationTask(configuration) { session in
            do {
                if allowDownload { try await session.prepareTranslation() }
                let response = try await session.translate(input)
                model.translated = response.targetText
                model.error = nil; needsDownload = false
            } catch { model.error = error.localizedDescription }
            model.translating = false
        }
    }
    private func begin(download: Bool) {
        guard !model.text.isEmpty, !model.translating else { return }
        model.error = nil; needsDownload = false
        if Locale.Language(identifier: model.source) == Locale.Language(identifier: model.target) { model.translated = model.text; return }
        input = model.text
        model.translating = true
        Task { @MainActor in
            let source = Locale.Language(identifier: model.source), target = Locale.Language(identifier: model.target)
            let status = await LanguageAvailability().status(from: source, to: target)
            if status == .unsupported {
                model.error = model.language.pick(zh: "系统不支持这组翻译语言。", en: "This language pair is not supported.")
                model.translating = false
                return
            }
            if status != .installed, !download { needsDownload = true; model.translating = false; return }
            allowDownload = download; input = model.text; model.translating = true; model.error = nil
            if configuration?.source == source, configuration?.target == target { configuration?.invalidate() }
            else { configuration = TranslationSession.Configuration(source: source, target: target) }
        }
    }
}
