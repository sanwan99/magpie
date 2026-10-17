import AppKit
import Carbon
import ScreenCaptureKit

@MainActor
final class LongScreenshotController: NSObject {
    private let screen: NSScreen
    private let selection: CGRect
    private let language: AppLanguage
    private let completion: (Result<Data?, Error>) -> Void
    private var panel: NSPanel?
    private var regionPanel: NSPanel?
    private var preview: NSImageView?
    private var label: NSTextField?
    private var pauseButton: NSButton?
    private var task: Task<Void, Never>?
    private var exportTask: Task<Void, Never>?
    private var exporting = false
    private var stitcher: ScreenshotStitcher?
    var capturedFrameCount: Int { stitcher?.frames ?? 0 }
    var capturedImage: CGImage? { stitcher?.image }
    private var paused = false
    private var finished = false
    private var keys: ScreenshotCaptureKeys?

    init(screen: NSScreen, selection: CGRect, language: AppLanguage, completion: @escaping (Result<Data?, Error>) -> Void) {
        self.screen = screen; self.selection = selection; self.language = language; self.completion = completion
    }

    func start() {
        showControls()
        keys = ScreenshotCaptureKeys(onCancel: { [weak self] in self?.cancel() }, onFinish: { [weak self] in self?.complete() })
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let number = self.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                guard let display = content.displays.first(where: { $0.displayID == number?.uint32Value }) else { throw ScreenshotSessionError.noDisplay }
                let ids = [self.panel, self.regionPanel].compactMap { $0.map { CGWindowID($0.windowNumber) } }
                let excluded = content.windows.filter { ids.contains($0.windowID) }
                guard excluded.count == ids.count else { throw ScreenshotSessionError.noDisplay }
                let filter = SCContentFilter(display: display, excludingWindows: excluded)
                let config = SCStreamConfiguration()
                config.width = Int(self.screen.frame.width * self.screen.backingScaleFactor)
                config.height = Int(self.screen.frame.height * self.screen.backingScaleFactor)
                config.showsCursor = false; config.captureResolution = .best
                while !Task.isCancelled, !self.finished {
                    if !self.paused {
                        let frame = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        guard !Task.isCancelled, !self.finished else { return }
                        guard let cropped = ScreenshotRenderer.render(image: frame, pointSize: self.screen.frame.size,
                                                                      state: ScreenshotEditorState(selection: self.selection)) else { throw ScreenshotSessionError.noDisplay }
                        if let stitcher = self.stitcher {
                            self.update(result: stitcher.append(cropped))
                        } else {
                            self.stitcher = ScreenshotStitcher(image: cropped)
                            self.update(result: .unchanged)
                        }
                    }
                    try await Task.sleep(for: .milliseconds(650))
                }
            } catch is CancellationError { }
            catch { if !self.finished { self.end(.failure(error)) } }
        }
    }

    private func showControls() {
        let frame = screen.visibleFrame
        let global = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let outline = NSPanel(contentRect: global.insetBy(dx: -2, dy: -2), styleMask: .borderless, backing: .buffered, defer: false)
        outline.isOpaque = false; outline.backgroundColor = .clear; outline.hasShadow = false
        outline.ignoresMouseEvents = true; outline.level = .floating; outline.hidesOnDeactivate = false
        outline.isReleasedWhenClosed = false
        outline.contentView = ScreenshotRegionOutline(frame: CGRect(origin: .zero, size: outline.frame.size))
        outline.orderFrontRegardless(); regionPanel = outline
        let width: CGFloat = 320, height: CGFloat = 240
        let x = min(max(frame.minX, global.maxX + 12), frame.maxX - width)
        let y = min(max(frame.minY, global.maxY - height), frame.maxY - height)
        let panel = NSPanel(contentRect: CGRect(x: x, y: y, width: width, height: height),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = language.pick(zh: "长截图 · 手动向下滚动", en: "Scrolling capture · Scroll down manually")
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = NSView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let preview = NSImageView(frame: CGRect(x: 12, y: 75, width: 296, height: 155))
        preview.imageScaling = .scaleProportionallyDown
        root.addSubview(preview); self.preview = preview
        let label = NSTextField(wrappingLabelWithString: language.pick(zh: "正在准备，请稍候…", en: "Preparing…"))
        label.frame = CGRect(x: 12, y: 40, width: 296, height: 34); label.font = .systemFont(ofSize: 11)
        root.addSubview(label); self.label = label
        let entries = [(language.pick(zh: "暂停", en: "Pause"), #selector(togglePause)),
                       (language.pick(zh: "取消", en: "Cancel"), #selector(cancel)),
                       (language.pick(zh: "完成并复制", en: "Finish & copy"), #selector(complete))]
        for (index, entry) in entries.enumerated() {
            let button = NSButton(title: entry.0, target: self, action: entry.1)
            button.frame = CGRect(x: 10 + index * 100, y: 8, width: 96, height: 26); button.bezelStyle = .rounded
            root.addSubview(button)
            if index == 0 { pauseButton = button }
        }
        panel.contentView = root; self.panel = panel
        panel.orderFrontRegardless()
    }

    private func update(result: ScreenshotStitchResult) {
        guard let stitcher else { return }
        let prefix = "\(stitcher.image.width) × \(stitcher.image.height) px · \(stitcher.frames)"
        switch result {
        case .appended, .unchanged:
            label?.stringValue = prefix + language.pick(zh: " 帧 · 缓慢向下滚动，↵ 完成 / Esc 取消", en: " frames · Scroll slowly, ↵ finish / Esc cancel")
        case .insufficientOverlap:
            label?.stringValue = language.pick(zh: "重叠不足或画面不稳定，请稍向上滚回后放慢。", en: "Insufficient overlap or unstable image. Scroll back a little and slow down.")
        case .sizeChanged:
            paused = true
            label?.stringValue = language.pick(zh: "画面尺寸改变，已暂停；可完成当前结果。", en: "The capture size changed. Paused; you can finish the current result.")
        case .limitReached:
            paused = true
            label?.stringValue = language.pick(zh: "已达到 30000 px / 4000 万像素上限，请完成当前截图。", en: "Reached the 30,000 px / 40 MP limit. Finish this capture.")
        }
        preview?.image = NSImage(cgImage: stitcher.image, size: CGSize(width: stitcher.image.width, height: stitcher.image.height))
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseButton?.title = paused ? language.pick(zh: "继续", en: "Resume") : language.pick(zh: "暂停", en: "Pause")
    }
    @objc func cancel() { end(.success(nil)) }
    @objc func complete() {
        guard !exporting, let image = stitcher?.image else { NSSound.beep(); return }
        exporting = true; task?.cancel(); pauseButton?.isEnabled = false
        label?.stringValue = language.pick(zh: "正在生成 PNG，仍可按 Esc 取消…", en: "Encoding PNG. Esc still cancels…")
        exportTask = Task { [weak self] in
            let data = await Task.detached(priority: .userInitiated) { ScreenshotPNG.encode(image) }.value
            guard let self, !self.finished, !Task.isCancelled else { return }
            if let data { self.end(.success(data)) }
            else { self.end(.failure(ScreenshotSessionError.imageEncodingFailed)) }
        }
    }
    private func end(_ result: Result<Data?, Error>) {
        guard !finished else { return }
        finished = true; task?.cancel(); exportTask?.cancel(); keys = nil
        panel?.orderOut(nil); panel?.close(); panel = nil
        regionPanel?.orderOut(nil); regionPanel?.close(); regionPanel = nil
        preview?.image = nil; preview = nil; label = nil; pauseButton = nil
        stitcher = nil; task = nil; exportTask = nil
        completion(result)
    }
}

/// These keys are registered only while the scrolling capture is active.
@MainActor
private final class ScreenshotCaptureKeys {
    private var handler: EventHandlerRef?
    private var refs: [EventHotKeyRef] = []
    let onCancel: () -> Void
    let onFinish: () -> Void
    init(onCancel: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onCancel = onCancel; self.onFinish = onFinish
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard id.signature == 0x4D505343 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<ScreenshotCaptureKeys>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in id.id == 1 ? owner.onCancel() : owner.onFinish() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return }
        for (index, key) in [kVK_Escape, kVK_Return].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x4D505343, id: UInt32(index + 1))
            if RegisterEventHotKey(UInt32(key), 0, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }
    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}


private final class ScreenshotRegionOutline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()
    }
}
