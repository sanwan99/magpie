import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotSessionOutput {
    case copied(Data)
    case copiedText(String)
    case presented
    case saved
    case cancelled
}

@MainActor
protocol ScreenshotSessionRunning: AnyObject {
    func run(completion: @escaping (Result<ScreenshotSessionOutput, Error>) -> Void)
}

enum ScreenshotSessionError: LocalizedError {
    case alreadyRunning, noDisplay, clipboardWriteFailed, imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Unable to encode the screenshot. Try a smaller region."
        case .alreadyRunning: return "A screenshot is already in progress."
        case .noDisplay: return "No available display was found."
        case .clipboardWriteFailed: return "Unable to copy the screenshot to the clipboard."
        }
    }
}

private final class ScreenshotOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NativeScreenshotSession: ScreenshotSessionRunning {
    private var windows: [ScreenshotOverlayWindow] = []
    private var completion: ((Result<ScreenshotSessionOutput, Error>) -> Void)?
    private var screenObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var isSaving = false
    private var savePanel: NSSavePanel?
    private var scrollController: LongScreenshotController?

    func run(completion: @escaping (Result<ScreenshotSessionOutput, Error>) -> Void) {
        guard self.completion == nil else {
            completion(.failure(ScreenshotSessionError.alreadyRunning))
            return
        }
        self.completion = completion
        previousApplication = NSWorkspace.shared.frontmostApplication
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Let the dismissed panel and menu leave the compositor before freezing the desktop.
                try await Task.sleep(for: .milliseconds(120))
                let frames = try await Self.captureFrames()
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                self.present(frames, windows: content.windows)
            } catch {
                self.finish(.failure(error))
            }
        }
    }

    static func captureFrames() async throws -> [(NSScreen, CGImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frames: [(NSScreen, CGImage)] = []
        let screens = NSScreen.screens
        for screen in screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
            configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            frames.append((screen, image))
        }
        guard !frames.isEmpty else { throw ScreenshotSessionError.noDisplay }
        return frames
    }

    private func present(_ frames: [(NSScreen, CGImage)], windows capturedWindows: [SCWindow]) {
        let language = SettingsStore.shared.language
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let order = Dictionary(uniqueKeysWithValues: windowInfo.enumerated().compactMap { index, item -> (CGWindowID, Int)? in
            guard let id = item[kCGWindowNumber as String] as? UInt32 else { return nil }
            return (id, index)
        })
        let targets = capturedWindows.filter { $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40 }
            .sorted { (order[$0.windowID] ?? Int.max) < (order[$1.windowID] ?? Int.max) }
        for (screen, image) in frames {
            let window = ScreenshotOverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                                 backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            let canvas = ScreenshotCanvasView(image: image, size: screen.frame.size, language: language)
            canvas.windowTargets = targets.compactMap { target in
                let global = CGRect(x: target.frame.minX, y: primaryTop - target.frame.maxY, width: target.frame.width, height: target.frame.height)
                let clipped = global.intersection(screen.frame)
                guard !clipped.isNull else { return nil }
                return ScreenshotWindowTarget(rect: clipped.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
                                              title: target.owningApplication?.applicationName ?? "")
            }
            canvas.onActivate = { [weak self, weak canvas] in
                guard let self, let canvas, !self.isSaving else { return }
                for window in self.windows {
                    (window.contentView as? ScreenshotCanvasView)?.isActive = window.contentView === canvas
                }
            }
            canvas.onCopy = { [weak self] data in self?.finish(.success(.copied(data))) }
            canvas.onSave = { [weak self, weak canvas] data in self?.save(data, from: canvas) }
            canvas.onCancel = { [weak self] in self?.finish(.success(.cancelled)) }
            canvas.onCopyColor = { [weak self] text in self?.finish(.success(.copiedText(text))) }
            canvas.onRecognize = { [weak self] data, translate in
                self?.finish(.success(.presented))
                ScreenshotTextWindow.show(data: data, translate: translate)
            }
            canvas.onPin = { [weak self, weak canvas] data in self?.showImage(data, canvas: canvas, share: false) }
            canvas.onShare = { [weak self, weak canvas] data in self?.showImage(data, canvas: canvas, share: true) }
            canvas.onLongCapture = { [weak self, weak canvas] in self?.startLongCapture(canvas: canvas, screen: screen) }
            window.contentView = canvas
            window.makeFirstResponder(canvas)
            windows.append(window)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finish(.success(.cancelled)) }
        }
        NSApp.activate(ignoringOtherApps: true)
        for window in windows { window.orderFrontRegardless() }
        let selected = windows.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? windows[0]
        for window in windows { (window.contentView as? ScreenshotCanvasView)?.isActive = window === selected }
        selected.makeKey()
    }

    private func showImage(_ data: Data, canvas: ScreenshotCanvasView?, share: Bool) {
        guard let window = canvas?.window, let selection = canvas?.model.state.selection else { return }
        let rect = selection.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
        finish(.success(.presented))
        ScreenshotPinnedWindow.show(data: data, near: rect, share: share)
    }

    private func startLongCapture(canvas: ScreenshotCanvasView?, screen: NSScreen) {
        guard scrollController == nil, let canvas, let selection = canvas.model.state.selection else { return }
        if !canvas.model.state.annotations.isEmpty {
            let language = SettingsStore.shared.language
            let alert = NSAlert()
            alert.messageText = language.pick(zh: "开始长截图？", en: "Start scrolling capture?")
            alert.informativeText = language.pick(zh: "长截图捕获当前屏幕的原始内容，不包含已画的标注。取消长截图会返回当前编辑。", en: "Scrolling captures the live screen without the existing annotations. Canceling returns to this editor.")
            alert.addButton(withTitle: language.pick(zh: "开始", en: "Start"))
            alert.addButton(withTitle: language.pick(zh: "取消", en: "Cancel"))
            guard let window = canvas.window else { return }
            alert.beginSheetModal(for: window) { [weak self, weak canvas] response in
                guard response == .alertFirstButtonReturn, let self, let canvas else { return }
                self.beginLongCapture(canvas: canvas, screen: screen, selection: selection)
            }
            return
        }
        beginLongCapture(canvas: canvas, screen: screen, selection: selection)
    }

    private func beginLongCapture(canvas: ScreenshotCanvasView, screen: NSScreen, selection: CGRect) {
        for window in windows { window.orderOut(nil) }
        let controller = LongScreenshotController(screen: screen, selection: selection, language: SettingsStore.shared.language) { [weak self, weak canvas] result in
            guard let self, self.completion != nil else { return }
            self.scrollController = nil
            switch result {
            case .success(let data):
                if let data { self.finish(.success(.copied(data))) }
                else { self.restoreEditor(canvas) }
            case .failure(let error):
                self.restoreEditor(canvas)
                if let window = canvas?.window { NSAlert(error: error).beginSheetModal(for: window) }
            }
        }
        scrollController = controller
        controller.start()
    }

    private func save(_ data: Data, from canvas: ScreenshotCanvasView?) {
        guard !isSaving else { return }
        isSaving = true
        for window in windows { window.orderOut(nil) }
        let panel = NSSavePanel()
        savePanel = panel
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "Magpie \(formatter.string(from: Date())).png"
        panel.begin { [weak self, weak canvas] response in
            guard let self, self.completion != nil else { return }
            self.isSaving = false
            self.savePanel = nil
            guard response == .OK, let url = panel.url else {
                self.restoreEditor(canvas)
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                self.finish(.success(.saved))
            } catch {
                self.restoreEditor(canvas)
                let alert = NSAlert(error: error)
                if let window = canvas?.window { alert.beginSheetModal(for: window) }
            }
        }
    }

    private func restoreEditor(_ canvas: ScreenshotCanvasView?) {
        for window in windows { window.orderFrontRegardless() }
        canvas?.window?.makeKey()
        canvas?.window?.makeFirstResponder(canvas)
    }

    private func finish(_ result: Result<ScreenshotSessionOutput, Error>) {
        guard let completion else { return }
        self.completion = nil
        scrollController?.cancel(); scrollController = nil
        savePanel?.cancel(nil)
        savePanel = nil
        isSaving = false
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        for window in windows {
            (window.contentView as? ScreenshotCanvasView)?.cancelPendingAnalysis()
            window.orderOut(nil); window.close()
        }
        windows.removeAll()
        NSCursor.arrow.set()
        if let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        completion(result)
    }
}
