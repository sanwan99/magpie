import AppKit

@MainActor
final class ScreenshotCanvasView: NSView, NSTextFieldDelegate {
    let image: CGImage
    private(set) var model = ScreenshotEditorModel()
    var onActivate: (() -> Void)?
    var onCopy: ((Data) -> Void)?
    var onSave: ((Data) -> Void)?
    var onCancel: (() -> Void)?
    var onCopyColor: ((String) -> Void)?
    var onRecognize: ((Data, Bool) -> Void)?
    var onPin: ((Data) -> Void)?
    var onShare: ((Data) -> Void)?
    var onLongCapture: (() -> Void)?
    var windowTargets: [ScreenshotWindowTarget] = []
    private var selectedAnnotationID: UUID?
    private var editingTextID: UUID?
    private var textSize: CGFloat = 21
    private var filled = false
    private var mosaicBrush = true
    private var sticker = "🙂"
    private var stickerSize: CGFloat = 40
    private var pointer: CGPoint?
    private var hoverWindow: ScreenshotWindowTarget?
    private lazy var pixelSampler = ScreenshotPixelSampler(image: image, pointSize: bounds.size)
    private var analysisTask: Task<Void, Never>?
    private var analyzing = false
    private var statusMessage: String?
    private var sizeControl: NSSegmentedControl!
    private var fillControl: NSButton!
    private var mosaicControl: NSSegmentedControl!
    private var stickerButtons: [NSButton] = []
    private var customStickerField: NSTextField!
    private let stickers = ["🙂", "😂", "👍", "❤️", "⭐️", "✅", "❗️", "❓"]
    private var selectedAnnotation: ScreenshotAnnotation? { model.state.annotations.first { $0.id == selectedAnnotationID } }
    private var effectiveTool: ScreenshotTool { selectedAnnotation?.tool ?? tool }
    private var hasToolOptions: Bool { effectiveTool != .selection }
    var isActive = true {
        didSet {
            if !isActive { commitText() }
            refresh()
        }
    }

    private let language: AppLanguage
    private var tool: ScreenshotTool = .selection
    private var ink: ScreenshotInk = .red
    private var strokeWidth: CGFloat = 3
    private var draft: ScreenshotAnnotation?
    private var mosaicImage: CGImage?
    private var textEditor: NSTextField?
    private var textOrigin = CGPoint.zero
    private var drag: Drag?
    private var toolbar = NSView()
    private var toolButtons: [ScreenshotTool: NSButton] = [:]
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var colorButton: NSButton!
    private var widthButton: NSButton!
    private var tracking: NSTrackingArea?
    private let palette = NSView()
    private var paletteButtons: [ScreenshotInk: NSButton] = [:]
    private var showsPalette = false
    private let hoverHelpView = ScreenshotHoverHelpView()
    private var hoverHelp: [NSView: String] = [:]
    private weak var hoveredControl: NSView?
    private var hoverTask: Task<Void, Never>?

    private var supportsInk: Bool { ![.selection, .mosaic, .sticker].contains(effectiveTool) }

    private enum Drag {
        case select(CGPoint)
        case move(CGPoint, CGRect)
        case resize(ScreenshotHandle, CGRect)
        case annotate
        case moveAnnotation(CGPoint, ScreenshotAnnotation)
        case resizeAnnotation(ScreenshotHandle, ScreenshotAnnotation, CGRect)
    }

    init(image: CGImage, size: CGSize, language: AppLanguage) {
        self.image = image
        self.language = language
        super.init(frame: CGRect(origin: .zero, size: size))
        buildToolbar()
        buildPalette()
        hoverHelpView.isHidden = true
        hoverHelpView.identifier = NSUserInterfaceItemIdentifier("screenshot.hoverHelp")
        addSubview(hoverHelpView)
        setAccessibilityLabel(language.pick(zh: "截图编辑器", en: "Screenshot editor"))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hideHoverHelp()
        if let point = window?.mouseLocationOutsideOfEventStream, bounds.contains(point) {
            pointer = point
            hoverWindow = windowTargets.first { $0.rect.contains(point) }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        if isActive, let rect = model.state.selection {
            context.saveGState()
            context.clip(to: rect)
            ScreenshotRenderer.draw(model.state.annotations.filter { $0.id != editingTextID } + (draft.map { [$0] } ?? []), in: context,
                                    imageBounds: bounds, pixelatedImage: mosaicImage)
            context.restoreGState()
            let mask = NSBezierPath(rect: bounds)
            mask.append(NSBezierPath(rect: rect))
            mask.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.45).setFill()
            mask.fill()
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1
            border.stroke()
            if drag == nil || tool == .selection {
                for handle in ScreenshotHandle.allCases {
                    let p = handle.point(in: rect)
                    let dot = NSBezierPath(roundedRect: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1)
                    NSColor.white.setFill()
                    dot.fill()
                    NSColor.systemBlue.setStroke()
                    dot.stroke()
                }
            }
            if let annotation = selectedAnnotation {
                NSColor.white.setStroke()
                let outline = NSBezierPath(rect: annotation.drawingBounds.insetBy(dx: -4, dy: -4))
                outline.setLineDash([3, 3], count: 2, phase: 0)
                outline.stroke()
                for handle in ScreenshotHandle.allCases {
                    let point = handle.point(in: annotation.drawingBounds)
                    NSColor.white.setFill()
                    CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6).fill()
                }
            }
            let scale = CGFloat(image.width) / bounds.width
            let pixelRect = ScreenshotGeometry.pixelAligned(rect, scale: scale, within: bounds)
            let size = "\(Int((pixelRect.width * scale).rounded())) × \(Int((pixelRect.height * scale).rounded())) px"
            drawBadge(size, at: CGPoint(x: rect.minX, y: rect.maxY + 8))
        } else {
            NSColor.black.withAlphaComponent(0.35).setFill()
            bounds.fill()
            if let target = hoverWindow {
                context.saveGState()
                context.clip(to: target.rect)
                context.draw(image, in: bounds)
                context.restoreGState()
                NSColor.systemBlue.setStroke()
                NSBezierPath(rect: target.rect).stroke()
            }
            let hint = language.pick(zh: "拖动框选 · 单击选择窗口 · ⌘A 全屏 · Esc 取消", en: "Drag a region · Click a window · ⌘A Full screen · Esc Cancel")
            drawBadge(hint, at: CGPoint(x: bounds.midX - 180, y: bounds.midY + 48))
            drawMagnifier()
        }
        if let statusMessage {
            drawBadge(statusMessage, at: CGPoint(x: bounds.midX - 160, y: bounds.maxY - 48))
        }
    }

    private func drawBadge(_ text: String, at origin: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: min(max(8, origin.x), bounds.maxX - size.width - 24),
                          y: min(max(8, origin.y), bounds.maxY - size.height - 16),
                          width: size.width + 16, height: size.height + 10)
        NSColor(white: 0.1, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 5), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        hideHoverHelp()
        guard !analyzing else { return }
        onActivate?()
        window?.makeKey()
        commitText()
        window?.makeFirstResponder(self)
        let point = ScreenshotGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        statusMessage = nil
        if model.state.selection == nil { hoverWindow = windowTargets.first { $0.rect.contains(point) } }
        if let annotation = selectedAnnotation,
           let handle = ScreenshotHandle.allCases.first(where: { hypot($0.point(in: annotation.drawingBounds).x - point.x, $0.point(in: annotation.drawingBounds).y - point.y) < 8 }) {
            model.beginChange()
            drag = .resizeAnnotation(handle, annotation, annotation.drawingBounds)
            return
        }
        if let hit = model.state.annotations.last(where: { $0.contains(point) }), tool == .selection || event.clickCount == 2 {
            selectedAnnotationID = hit.id
            ink = hit.ink; strokeWidth = hit.width; textSize = hit.textSize; filled = hit.filled
            mosaicBrush = hit.mosaicBrush
            if hit.tool == .sticker { sticker = hit.text; stickerSize = hit.textSize }
            showsPalette = true
            if event.clickCount == 2, hit.tool == .text {
                beginText(at: hit.points[0], existing: hit)
            } else {
                model.beginChange()
                drag = .moveAnnotation(point, hit)
            }
            refresh()
            return
        }
        selectedAnnotationID = nil
        if event.clickCount == 2, tool == .selection, model.state.selection?.contains(point) == true {
            copyImage()
            return
        }
        model.beginChange()
        if let rect = model.state.selection {
            if let handle = handle(at: point) {
                drag = .resize(handle, rect)
            } else if rect.contains(point) {
                if tool == .selection {
                    drag = .move(point, rect)
                } else if tool == .sticker {
                    model.commitChange()
                    let fittedSize = min(stickerSize, max(12, min(rect.width, rect.height) * 0.7))
                    var annotation = ScreenshotAnnotation(tool: .sticker, points: [point], text: sticker, textSize: fittedSize)
                    let fitted = ScreenshotGeometry.moved(annotation.drawingBounds, by: .zero, within: rect)
                    annotation.points = [fitted.origin]
                    model.add(annotation)
                    refresh()
                    return
                } else if tool == .text {
                    model.commitChange()
                    beginText(at: point)
                    return
                } else {
                    if tool == .mosaic, mosaicImage == nil {
                        mosaicImage = ScreenshotRenderer.pixelated(image, pointSize: bounds.size)
                    }
                    draft = ScreenshotAnnotation(tool: tool, points: [point], ink: ink, width: strokeWidth,
                                                 textSize: textSize, filled: filled, mosaicBrush: tool == .mosaic && mosaicBrush)
                    drag = .annotate
                }
            } else {
                model.state = ScreenshotEditorState()
                tool = .selection
                drag = .select(point)
            }
        } else {
            drag = .select(point)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = ScreenshotGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        switch drag {
        case .select(let start):
            model.state.selection = ScreenshotGeometry.rectangle(from: start, to: point)
        case .move(let start, let original):
            model.state.selection = ScreenshotGeometry.moved(original, by: CGPoint(x: point.x - start.x, y: point.y - start.y), within: bounds)
        case .resize(let handle, let original):
            model.state.selection = ScreenshotGeometry.resized(original, handle: handle, to: point, within: bounds)
        case .annotate:
            guard let rect = model.state.selection else { return }
            let end = ScreenshotGeometry.clamp(point, to: rect)
            if draft?.tool == .pen || draft?.mosaicBrush == true {
                draft?.points.append(end)
            } else if let first = draft?.points.first {
                let constrained = event.modifierFlags.contains(.shift)
                    ? ScreenshotGeometry.constrainedEnd(start: first, end: end, tool: tool) : end
                draft?.points = [first, ScreenshotGeometry.clamp(constrained, to: rect)]
            }
        case .moveAnnotation(let start, let annotation):
            let region = model.state.selection ?? bounds
            let moved = ScreenshotGeometry.moved(annotation.drawingBounds,
                by: CGPoint(x: point.x - start.x, y: point.y - start.y), within: region)
            replace(annotation.translated(by: CGPoint(x: moved.minX - annotation.drawingBounds.minX, y: moved.minY - annotation.drawingBounds.minY)))
        case .resizeAnnotation(let handle, let annotation, let original):
            let resized = ScreenshotGeometry.resized(original, handle: handle, to: point, within: model.state.selection ?? bounds)
            var changed = annotation
            changed.points = annotation.points.map { CGPoint(x: resized.minX + ($0.x - original.minX) * resized.width / max(1, original.width),
                                                            y: resized.minY + ($0.y - original.minY) * resized.height / max(1, original.height)) }
            if annotation.tool == .text || annotation.tool == .sticker {
                changed.textSize = min(180, max(10, annotation.textSize * resized.height / max(1, original.height)))
                if let width = annotation.textBoxWidth { changed.textBoxWidth = max(20, width * resized.width / max(1, original.width)) }
            }
            replace(changed)
        case nil: break
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        if case .select = drag, model.state.selection == nil, let target = hoverWindow {
            model.state.selection = target.rect
        }
        if let draft, draft.tool == .pen || draft.mosaicBrush || draft.rect.width > 1 || draft.rect.height > 1 {
            model.state.annotations.append(draft)
        }
        if let rect = model.state.selection, rect.width < 2 || rect.height < 2 {
            model.state.selection = nil
        }
        draft = nil
        drag = nil
        model.commitChange()
        refresh()
    }

    override func rightMouseDown(with event: NSEvent) {
        hideHoverHelp()
        if selectedAnnotationID != nil { selectedAnnotationID = nil }
        else if showsPalette { showsPalette = false }
        else if tool != .selection { tool = .selection }
        else if model.state.selection != nil {
            model.beginChange(); model.state = ScreenshotEditorState(); model.commitChange()
        } else { onCancel?() }
        refresh()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        updateHoverHelp(at: point)
        if model.state.selection == nil {
            hoverWindow = windowTargets.first { $0.rect.contains(point) }
            needsDisplay = true
        }
        if (!toolbar.isHidden && toolbar.frame.contains(point)) || (!palette.isHidden && palette.frame.contains(point)) {
            NSCursor.arrow.set()
            return
        }
        if isActive, let handle = handle(at: point) {
            switch handle {
            case .left, .right: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        } else if isActive, tool == .selection, model.state.selection?.contains(point) == true {
            NSCursor.openHand.set()
        } else if tool == .text {
            NSCursor.iBeam.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hideHoverHelp() }

    private func setHoverHelp(_ text: String, for control: NSView) {
        hoverHelp[control] = text
        control.toolTip = nil
        control.setAccessibilityHelp(text)
    }

    private func hideHoverHelp() {
        hoverTask?.cancel()
        hoverTask = nil
        hoveredControl = nil
        hoverHelpView.isHidden = true
    }

    private func updateHoverHelp(at point: CGPoint) {
        guard isActive, drag == nil,
              let control = hoverHelp.keys.first(where: { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.contains($0.convert(point, from: self)) }) else {
            hideHoverHelp()
            return
        }
        guard control !== hoveredControl else { return }
        hideHoverHelp()
        hoveredControl = control
        hoverTask = Task { @MainActor [weak self, weak control] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, let control, !Task.isCancelled, self.window != nil,
                  self.hoveredControl === control, !control.isHiddenOrHasHiddenAncestor,
                  let text = self.hoverHelp[control] else { return }
            self.showHoverHelp(text, for: control)
        }
    }

    private func showHoverHelp(_ text: String, for control: NSView) {
        var message = text
        if analyzing, (control as? NSControl)?.isEnabled == false {
            message += language.pick(zh: "\n正在识别，请稍候。", en: "\nRecognition is in progress. Please wait.")
        }
        hoverHelpView.setText(message, maxWidth: min(320, bounds.width - 32))
        let anchor = convert(control.bounds, from: control)
        let obstacles = palette.isHidden ? toolbar.frame : toolbar.frame.union(palette.frame)
        let size = hoverHelpView.frame.size
        let below = obstacles.minY - size.height - 8
        let y = below >= 8 ? below : obstacles.maxY + 8
        hoverHelpView.setFrameOrigin(CGPoint(x: min(max(8, anchor.midX - size.width / 2), bounds.maxX - size.width - 8),
                                             y: min(max(8, y), bounds.maxY - size.height - 8)))
        addSubview(hoverHelpView, positioned: .above, relativeTo: nil)
        hoverHelpView.isHidden = false
    }

    private func handle(at point: CGPoint) -> ScreenshotHandle? {
        guard let rect = model.state.selection else { return nil }
        return ScreenshotHandle.allCases.first {
            let center = $0.point(in: rect)
            return abs(center.x - point.x) <= 7 && abs(center.y - point.y) <= 7
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // A field editor owns copy, select-all and undo while entering text.
        let fieldIsEditing = textEditor != nil || (window?.firstResponder as? NSTextView)?.isFieldEditor == true
        if fieldIsEditing, event.charactersIgnoringModifiers?.lowercased() != "s" {
            return super.performKeyEquivalent(with: event)
        }
        if event.modifierFlags.contains(.command) { return handleKey(event) }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        hideHoverHelp()
        if analyzing, event.keyCode != 53 { return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            switch key {
            case "c": copyImage()
            case "s": event.modifierFlags.contains(.shift) ? shareImage() : saveImage()
            case "z": event.modifierFlags.contains(.shift) ? redoEdit() : undoEdit()
            case "a":
                commitText()
                model.beginChange()
                model.state.selection = bounds
                model.commitChange()
                refresh()
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case 53:
            if selectedAnnotationID != nil { selectedAnnotationID = nil; refresh() }
            else { analysisTask?.cancel(); onCancel?() }
        case 36, 76: copyImage()
        case 51, 117:
            if let id = selectedAnnotationID {
                model.beginChange(); model.state.annotations.removeAll { $0.id == id }; model.commitChange()
                selectedAnnotationID = nil; refresh()
            } else { undoEdit() }
        case 123...126:
            guard let rect = model.state.selection else { return true }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            let delta: CGPoint
            switch event.keyCode {
            case 123: delta = CGPoint(x: -step, y: 0)
            case 124: delta = CGPoint(x: step, y: 0)
            case 125: delta = CGPoint(x: 0, y: -step)
            default: delta = CGPoint(x: 0, y: step)
            }
            model.beginChange()
            if let selected = selectedAnnotation {
                let moved = ScreenshotGeometry.moved(selected.drawingBounds, by: delta, within: rect)
                replace(selected.translated(by: CGPoint(x: moved.minX - selected.drawingBounds.minX, y: moved.minY - selected.drawingBounds.minY)))
            } else if event.modifierFlags.contains(.option) {
                let handle: ScreenshotHandle = delta.x == 0 ? .top : .right
                let point = handle.point(in: rect)
                model.state.selection = ScreenshotGeometry.resized(rect, handle: handle,
                    to: CGPoint(x: point.x + delta.x, y: point.y + delta.y), within: bounds)
            } else {
                model.state.selection = ScreenshotGeometry.moved(rect, by: delta, within: bounds)
            }
            model.commitChange()
            refresh()
        default:
            if let selected = ScreenshotTool.allCases.first(where: { $0.shortcut == key }) {
                commitText()
                selectedAnnotationID = nil
                tool = selected
                showsPalette = hasToolOptions
                refresh()
            } else if key == "x" { recognizeText() }
            else if key == "l" { translateText() }
            else if key == "n" { pinImage() }
            else if key == "g" { longCapture() }
            else if key == "d" { redactPrivateInfo() }
            else if key == "c" { cycleColor() }
            else if key == "[" { changeWidth(by: -1) }
            else if key == "]" { changeWidth(by: 1) }
            else { return false }
        }
        return true
    }

    private func beginText(at point: CGPoint, existing: ScreenshotAnnotation? = nil) {
        guard let rect = model.state.selection else { return }
        let height = textSize + 14
        let origin = CGPoint(x: min(point.x, max(rect.minX, rect.maxX - 100)),
                             y: min(point.y, max(rect.minY, rect.maxY - height)))
        textOrigin = CGPoint(x: origin.x + 3, y: origin.y + 3)
        let field = NSTextField(frame: CGRect(x: origin.x, y: origin.y,
                                             width: max(40, min(300, rect.maxX - origin.x)), height: height))
        field.font = .systemFont(ofSize: textSize, weight: .medium)
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.textColor = ink.color
        field.backgroundColor = NSColor(white: ink == .black || ink == .olive ? 0.95 : 0.18, alpha: 0.95)
        field.isBordered = true
        field.placeholderString = language.pick(zh: "输入文字，回车确认", en: "Type, Return to apply")
        field.delegate = self
        if let existing {
            editingTextID = existing.id
            textOrigin = existing.points[0]
            field.setFrameOrigin(CGPoint(x: textOrigin.x - 3, y: textOrigin.y - 3))
            field.stringValue = existing.text
            field.frame.size = CGSize(width: (existing.textBoxWidth ?? existing.drawingBounds.width) + 6,
                                      height: existing.drawingBounds.height + 6)
        }
        field.focusRingType = .none
        addSubview(field)
        textEditor = field
        window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === customStickerField, commandSelector == #selector(NSResponder.insertNewline(_:)) {
            acceptCustomSticker(); window?.makeFirstResponder(self); return true
        }
        if commandSelector == NSSelectorFromString("insertLineBreak:") || commandSelector == NSSelectorFromString("insertNewlineIgnoringFieldEditor:") ||
            (commandSelector == #selector(NSResponder.insertNewline(_:)) && NSApp.currentEvent?.modifierFlags.contains(.shift) == true) {
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textEditor?.removeFromSuperview()
            textEditor = nil
            editingTextID = nil
            refresh()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        if notification.object as? NSTextField === customStickerField { acceptCustomSticker(); return }
        guard let field = textEditor, let selection = model.state.selection else { return }
        let measured = (field.stringValue as NSString).boundingRect(with: CGSize(width: max(20, field.frame.width - 6), height: selection.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: field.font ?? NSFont.systemFont(ofSize: textSize)])
        let height = min(selection.height, max(textSize + 14, ceil(measured.height) + 10))
        let top = field.frame.maxY
        field.frame.size.height = height
        field.frame.origin.y = max(selection.minY, top - height)
        textOrigin = CGPoint(x: field.frame.minX + 3, y: field.frame.minY + 3)
    }

    private func commitText() {
        guard let field = textEditor else { return }
        let text = field.stringValue
        textEditor = nil
        field.removeFromSuperview()
        if let id = editingTextID, var existing = model.state.annotations.first(where: { $0.id == id }) {
            model.beginChange()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.state.annotations.removeAll { $0.id == id }
            } else {
                existing.text = text; existing.ink = ink; existing.textSize = textSize
                existing.textBoxWidth = max(20, field.frame.width - 6); existing.points = [textOrigin]
                replace(existing)
            }
            model.commitChange()
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.add(ScreenshotAnnotation(tool: .text, points: [textOrigin], ink: ink, width: strokeWidth, text: text, textSize: textSize, textBoxWidth: max(20, field.frame.width - 6)))
        }
        editingTextID = nil
        refresh()
    }

    private func buildToolbar() {
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.98).cgColor
        toolbar.layer?.cornerRadius = 9
        toolbar.layer?.borderWidth = 1
        toolbar.layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        toolbar.appearance = NSAppearance(named: .darkAqua)
        addSubview(toolbar)
        var x: CGFloat = 8
        func button(_ symbol: String, _ help: String, _ action: Selector) -> NSButton {
            let b = NSButton(image: (NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage(systemSymbolName: "square", accessibilityDescription: help))!, target: self, action: action)
            b.frame = CGRect(x: x, y: 6, width: 32, height: 32)
            b.bezelStyle = .regularSquare
            b.isBordered = false
            setHoverHelp(help, for: b)
            b.setAccessibilityLabel(String(help.split(separator: "\n").first ?? ""))
            b.contentTintColor = .white
            toolbar.addSubview(b)
            x += 34
            return b
        }
        for (index, tool) in ScreenshotTool.allCases.enumerated() {
            let b = button(tool.symbol, tool.help(language), #selector(selectTool(_:)))
            b.tag = index
            b.identifier = NSUserInterfaceItemIdentifier("screenshot.tool.\(tool.rawValue)")
            toolButtons[tool] = b
        }
        x += 6
        colorButton = button("circle.fill", language.pick(zh: "选择颜色（C 切换）", en: "Choose color (C to cycle)"), #selector(togglePalette))
        widthButton = button("lineweight", language.pick(zh: "线宽 / 字号 ([ / ])", en: "Width / Size ([ / ])"), #selector(toggleOptions))
        _ = button("text.viewfinder", language.pick(zh: "提取文字  (X)\n识别选区里的文字，打开结果窗口编辑或复制。", en: "Extract text  (X)\nRecognize text in the selection, then edit or copy the result."), #selector(recognizeText))
        _ = button("character.bubble", language.pick(zh: "翻译文字  (L)\n先识别选区文字，再翻译；可选语言，需要 macOS 15 或更新版本。", en: "Translate text  (L)\nRecognize and translate the selected text. Choose languages on macOS 15 or later."), #selector(translateText))
        _ = button("rectangle.expand.vertical", language.pick(zh: "长截图  (G)\n框选滚动区域后，手动向下滚动，拼接成长图。", en: "Scrolling capture  (G)\nSelect a scrollable area, then scroll down manually to stitch a long image."), #selector(longCapture))
        _ = button("eye.slash", language.pick(zh: "一键打码  (D)\n识别人脸、电话等隐私并打码；请检查遗漏，可撤销。", en: "Redact private info  (D)\nFind and pixelate faces, phone numbers and more. Check for missed areas; undo is available."), #selector(redactPrivateInfo))
        x += 6
        undoButton = button("arrow.uturn.backward", language.pick(zh: "撤销  (⌘Z)\n撤回上一步选区或标注修改。", en: "Undo  (⌘Z)\nUndo the last selection or annotation change."), #selector(undoEdit))
        redoButton = button("arrow.uturn.forward", language.pick(zh: "重做  (⇧⌘Z)\n恢复刚刚撤销的操作。", en: "Redo  (⇧⌘Z)\nRestore the last undone change."), #selector(redoEdit))
        x += 6
        _ = button("square.and.arrow.down", language.pick(zh: "保存图片  (⌘S)\n选择保存位置，将截图和标注存为 PNG 文件。", en: "Save image  (⌘S)\nChoose a location and save the annotated screenshot as a PNG file."), #selector(saveImage))
        _ = button("pin", language.pick(zh: "贴图  (N)\n将截图悬浮在其他窗口上方，方便对照；双击关闭。", en: "Pin image  (N)\nKeep the screenshot above other windows for reference. Double-click to close."), #selector(pinImage))
        _ = button("arrowshape.turn.up.right", language.pick(zh: "分享  (⇧⌘S)\n打开系统分享菜单，由你选择发送方式。", en: "Share  (⇧⌘S)\nOpen the system sharing menu and choose how to send the image."), #selector(shareImage))
        _ = button("xmark", language.pick(zh: "取消截图  (Esc)\n退出截图，不复制或保存。", en: "Cancel capture  (Esc)\nClose the editor without copying or saving."), #selector(cancelCapture))
        let copy = button("checkmark", language.pick(zh: "完成并复制  (↵ / ⌘C)\n复制截图和标注，随后可粘贴到聊天或文档中。", en: "Finish and copy  (↵ / ⌘C)\nCopy the annotated screenshot, ready to paste into a chat or document."), #selector(copyImage))
        copy.contentTintColor = .systemBlue
        let buttons = toolbar.subviews.compactMap { $0 as? NSButton }.sorted { $0.frame.minX < $1.frame.minX }
        let columns = max(1, min(buttons.count, Int((bounds.width - 32) / 34)))
        let rows = (buttons.count + columns - 1) / columns
        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(CGPoint(x: 8 + (index % columns) * 34, y: 6 + (rows - 1 - index / columns) * 34))
        }
        toolbar.frame.size = CGSize(width: columns * 34 + 16, height: rows * 34 + 12)
        toolbar.isHidden = true
    }

    @objc private func selectTool(_ sender: NSButton) {
        commitText()
        selectedAnnotationID = nil
        tool = ScreenshotTool.allCases[sender.tag]
        showsPalette = hasToolOptions
        window?.makeFirstResponder(self)
        refresh()
    }

    private func buildPalette() {
        palette.identifier = NSUserInterfaceItemIdentifier("screenshot.colorPalette")
        palette.wantsLayer = true
        palette.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.98).cgColor
        palette.layer?.cornerRadius = 7
        palette.layer?.borderWidth = 1
        palette.layer?.borderColor = NSColor(white: 1, alpha: 0.2).cgColor
        palette.appearance = NSAppearance(named: .darkAqua)
        palette.setAccessibilityLabel(language.pick(zh: "标注颜色", en: "Annotation colors"))
        for (index, ink) in ScreenshotInk.allCases.enumerated() {
            let name = ink.title(language)
            let button = ScreenshotColorSwatch(ink: ink)
            button.target = self
            button.action = #selector(selectInk(_:))
            button.frame = CGRect(x: 7 + index * 30, y: 5, width: 28, height: 28)
            button.tag = ink.rawValue
            button.identifier = NSUserInterfaceItemIdentifier("screenshot.ink.\(ink)")
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.setButtonType(.toggle)
            button.contentTintColor = ink.color
            setHoverHelp(language.pick(zh: "\(name)\n将当前标注颜色设为\(name)。", en: "\(name)\nUse \(name.lowercased()) for the current annotation."), for: button)
            button.setAccessibilityLabel(name)
            palette.addSubview(button)
            paletteButtons[ink] = button
        }
        sizeControl = NSSegmentedControl(labels: ["细", "中", "粗"], trackingMode: .selectOne, target: self, action: #selector(selectSize(_:)))
        sizeControl.frame = CGRect(x: 8, y: 44, width: 140, height: 24)
        sizeControl.setAccessibilityLabel(language.pick(zh: "线宽或字号", en: "Stroke width or font size"))
        palette.addSubview(sizeControl)
        fillControl = NSButton(checkboxWithTitle: language.pick(zh: "填充", en: "Fill"), target: self, action: #selector(toggleFill(_:)))
        fillControl.frame = CGRect(x: 172, y: 44, width: 84, height: 24)
        setHoverHelp(language.pick(zh: "填充形状\n勾选后，用当前颜色填满矩形或椭圆。", en: "Fill shape\nFill the rectangle or ellipse with the current color."), for: fillControl)
        palette.addSubview(fillControl)
        customStickerField = NSTextField(frame: CGRect(x: 158, y: 44, width: 118, height: 24))
        customStickerField.placeholderString = language.pick(zh: "其他表情…", en: "Other emoji…")
        setHoverHelp(language.pick(zh: "自定义表情\n输入或粘贴表情后，点击截图放置；使用第一个完整表情。", en: "Custom emoji\nType or paste an emoji, then click to place it. The first complete character is used."), for: customStickerField)
        customStickerField.delegate = self
        customStickerField.identifier = NSUserInterfaceItemIdentifier("screenshot.customSticker")
        palette.addSubview(customStickerField)
        mosaicControl = NSSegmentedControl(labels: [language.pick(zh: "画笔", en: "Brush"), language.pick(zh: "框选", en: "Rectangle")], trackingMode: .selectOne, target: self, action: #selector(selectMosaicMode(_:)))
        mosaicControl.frame = CGRect(x: 8, y: 7, width: 170, height: 26)
        setHoverHelp(language.pick(zh: "马赛克方式\n画笔：按住鼠标涂抹。框选：拖出矩形区域整体打码。", en: "Mosaic mode\nBrush: drag to paint. Rectangle: drag a box to pixelate the whole area."), for: mosaicControl)
        palette.addSubview(mosaicControl)
        for (index, emoji) in stickers.enumerated() {
            let button = NSButton(title: emoji, target: self, action: #selector(selectSticker(_:)))
            button.frame = CGRect(x: 7 + index * 33, y: 5, width: 31, height: 30)
            button.isBordered = false; button.font = .systemFont(ofSize: 21); button.tag = index
            setHoverHelp(language.pick(zh: "表情 \(emoji)\n选中后点击截图放置，可调整大小。", en: "Sticker \(emoji)\nSelect, then click the screenshot to place it. Its size is adjustable."), for: button)
            palette.addSubview(button); stickerButtons.append(button)
        }
        palette.frame.size = CGSize(width: 14 + ScreenshotInk.allCases.count * 30, height: 78)
        palette.isHidden = true
        addSubview(palette)
    }

    @objc private func togglePalette() {
        guard supportsInk else { return }
        showsPalette.toggle()
        refresh()
    }

    @objc private func selectInk(_ sender: NSButton) {
        guard supportsInk, let selected = ScreenshotInk(rawValue: sender.tag) else { return }
        ink = selected
        if !applyActiveTextStyle() { updateSelectedStyle(); window?.makeFirstResponder(self) }
        refresh()
    }

    @objc private func cycleColor() {
        guard supportsInk else { return }
        ink = ScreenshotInk(rawValue: (ink.rawValue + 1) % ScreenshotInk.allCases.count)!
        if !applyActiveTextStyle() { updateSelectedStyle() }
        refresh()
    }

    @objc private func cycleWidth() { changeWidth(by: strokeWidth >= 7 ? -6 : 2) }
    private func changeWidth(by delta: CGFloat) {
        if effectiveTool == .text { textSize = min(96, max(10, textSize + delta * 2)) }
        else if effectiveTool == .sticker { stickerSize = min(180, max(20, stickerSize + delta * 4)) }
        else { strokeWidth = min(9, max(1, strokeWidth + delta)) }
        if !applyActiveTextStyle() { updateSelectedStyle() }
        refresh()
    }

    @objc private func undoEdit() { commitText(); model.undo(); selectedAnnotationID = nil; refresh() }
    @objc private func redoEdit() { model.redo(); selectedAnnotationID = nil; refresh() }
    @objc private func cancelCapture() { hideHoverHelp(); onCancel?() }

    @objc private func copyImage() {
        if model.state.selection == nil, let pointer { onCopyColor?(pixelSampler.hex(at: pointer)); return }
        guard let data = exportPNG() else { return }
        onCopy?(data)
    }

    @objc private func saveImage() {
        guard let data = exportPNG() else { return }
        onSave?(data)
    }

    func exportPNG() -> Data? {
        hideHoverHelp()
        guard !analyzing else { NSSound.beep(); return nil }
        commitText()
        guard model.state.selection != nil else { NSSound.beep(); return nil }
        guard let data = ScreenshotRenderer.png(image: image, pointSize: bounds.size, state: model.state) else {
            let alert = NSAlert()
            alert.messageText = language.pick(zh: "无法生成截图", en: "Unable to render screenshot")
            alert.informativeText = language.pick(zh: "请缩小选区后重试。当前编辑已保留。", en: "Try a smaller selection. Your edits are preserved.")
            if let window { alert.beginSheetModal(for: window) }
            return nil
        }
        return data
    }

    private func replace(_ annotation: ScreenshotAnnotation) {
        guard let index = model.state.annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        model.state.annotations[index] = annotation
    }

    @discardableResult
    private func applyActiveTextStyle() -> Bool {
        guard let field = textEditor else { return false }
        field.textColor = ink.color
        field.font = .systemFont(ofSize: textSize, weight: .medium)
        field.backgroundColor = NSColor(white: ink == .black || ink == .olive ? 0.95 : 0.18, alpha: 0.95)
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        window?.makeFirstResponder(field)
        return true
    }

    private func updateSelectedStyle() {
        guard var annotation = selectedAnnotation else { return }
        model.beginChange()
        annotation.ink = ink; annotation.width = strokeWidth; annotation.filled = filled
        if annotation.tool == .text { annotation.textSize = textSize }
        if annotation.tool == .sticker { annotation.textSize = stickerSize; annotation.text = sticker }
        replace(annotation); model.commitChange()
    }

    @objc private func toggleOptions() { showsPalette.toggle(); refresh() }
    @objc private func selectSize(_ sender: NSSegmentedControl) {
        let index = max(0, sender.selectedSegment)
        if effectiveTool == .text { textSize = [14, 21, 32][index] }
        else if effectiveTool == .sticker { stickerSize = [24, 40, 64][index] }
        else { strokeWidth = [1, 3, 6][index] }
        if !applyActiveTextStyle() { updateSelectedStyle(); window?.makeFirstResponder(self) }
        refresh()
    }
    @objc private func toggleFill(_ sender: NSButton) { filled = sender.state == .on; updateSelectedStyle(); refresh() }
    @objc private func selectMosaicMode(_ sender: NSSegmentedControl) {
        selectedAnnotationID = nil; tool = .mosaic; mosaicBrush = sender.selectedSegment == 0; refresh()
    }
    private func acceptCustomSticker() {
        guard let first = customStickerField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).first else { return }
        sticker = String(first); updateSelectedStyle(); refresh()
    }
    @objc private func selectSticker(_ sender: NSButton) { sticker = stickers[sender.tag]; updateSelectedStyle(); refresh() }
    @objc private func recognizeText() { if let data = exportPNG() { onRecognize?(data, false) } }
    @objc private func translateText() { if let data = exportPNG() { onRecognize?(data, true) } }
    @objc private func pinImage() { if let data = exportPNG() { onPin?(data) } }
    @objc private func shareImage() { if let data = exportPNG() { onShare?(data) } }
    @objc private func longCapture() { hideHoverHelp(); commitText(); if model.state.selection != nil { onLongCapture?() } }

    @objc private func redactPrivateInfo() {
        commitText()
        guard !analyzing, let selection = model.state.selection,
              let crop = ScreenshotRenderer.render(image: image, pointSize: bounds.size, state: ScreenshotEditorState(selection: selection)) else { return }
        analyzing = true
        statusMessage = language.pick(zh: "正在本机识别隐私区域…", en: "Finding private information on this Mac…")
        refresh()
        analysisTask = Task { [weak self] in
            do {
                let result = try await ScreenshotAnalysis.analyze(crop, privacy: true)
                guard !Task.isCancelled, let self else { return }
                self.model.beginChange()
                for region in result.privateRegions {
                    let rect = ScreenshotAnalysis.localRect(region, in: selection)
                    self.model.state.annotations.append(ScreenshotAnnotation(tool: .mosaic,
                        points: [rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)]))
                }
                self.model.commitChange()
                self.mosaicImage = ScreenshotRenderer.pixelated(self.image, pointSize: self.bounds.size)
                self.statusMessage = self.language.pick(zh: "已打码 \(result.privateRegions.count) 处 · 请检查并手动补涂遗漏", en: "Redacted \(result.privateRegions.count) regions · Check and cover anything missed")
                self.analyzing = false; self.refresh()
            } catch {
                guard let self else { return }
                self.analyzing = false
                self.statusMessage = self.language.pick(zh: "识别失败，请手动打码", en: "Recognition failed. Use the mosaic tool.")
                self.refresh()
            }
        }
    }

    func cancelPendingAnalysis() { analysisTask?.cancel(); hideHoverHelp() }

    private func drawMagnifier() {
        guard let pointer, let context = NSGraphicsContext.current?.cgContext else { return }
        let pixelWidth = CGFloat(image.width), pixelHeight = CGFloat(image.height)
        let rawX = floor(pointer.x * pixelWidth / bounds.width)
        let rawY = pixelHeight - 1 - floor(pointer.y * pixelHeight / bounds.height)
        let pixel = CGPoint(x: min(pixelWidth - 1, max(0, rawX)), y: min(pixelHeight - 1, max(0, rawY)))
        let sampleWidth = min(CGFloat(11), pixelWidth), sampleHeight = min(CGFloat(11), pixelHeight)
        let sampleX = min(max(0, pixel.x - 5), pixelWidth - sampleWidth)
        let sampleY = min(max(0, pixel.y - 5), pixelHeight - sampleHeight)
        let sample = CGRect(x: sampleX, y: sampleY, width: sampleWidth, height: sampleHeight)
        let x = min(max(8, pointer.x + 22), bounds.maxX - 174)
        let y = min(max(42, pointer.y - 116), bounds.maxY - 92)
        let magnifier = CGRect(x: x, y: y, width: 88, height: 88)
        if let pixels = image.cropping(to: sample) {
            context.saveGState(); context.interpolationQuality = .none
            context.draw(pixels, in: magnifier)
            context.setStrokeColor(NSColor.white.cgColor); context.stroke(magnifier, width: 2)
            let cellWidth = magnifier.width / sample.width, cellHeight = magnifier.height / sample.height
            let cell = CGRect(x: magnifier.minX + (pixel.x - sample.minX) * cellWidth,
                              y: magnifier.maxY - (pixel.y - sample.minY + 1) * cellHeight,
                              width: cellWidth, height: cellHeight)
            context.stroke(cell, width: 2)
            context.setStrokeColor(NSColor.black.cgColor)
            context.stroke(cell, width: 1)
            context.restoreGState()
        }
        drawBadge(pixelSampler.hex(at: pointer) + " · ⌘C", at: CGPoint(x: x, y: y - 30))
    }

    private func refresh() {
        hideHoverHelp()
        for button in toolbar.subviews.compactMap({ $0 as? NSButton }) {
            button.isEnabled = !analyzing || button.action == #selector(cancelCapture)
        }
        toolbar.isHidden = !isActive || model.state.selection == nil || drag != nil
        if let rect = model.state.selection {
            let width = toolbar.frame.width
            let y: CGFloat
            let space = toolbar.frame.height + 10
            if rect.minY >= space + 8 { y = rect.minY - space }
            else if rect.maxY + space <= bounds.maxY { y = rect.maxY + 10 }
            else { y = max(8, rect.minY + 10) }
            toolbar.setFrameOrigin(CGPoint(x: max(8, min(rect.maxX - width, bounds.maxX - width - 8)), y: y))
        }
        for (item, button) in toolButtons { button.contentTintColor = item == tool ? .systemBlue : .white }
        undoButton?.isEnabled = model.canUndo && !analyzing
        redoButton?.isEnabled = model.canRedo && !analyzing
        colorButton?.contentTintColor = ink.color
        colorButton?.isEnabled = supportsInk && !analyzing
        widthButton?.isEnabled = hasToolOptions && !analyzing && (effectiveTool != .mosaic || mosaicBrush)
        let colorLabel = supportsInk
            ? language.pick(zh: "标注颜色  (C 切换)\n当前为\(ink.title(language))。点击打开色板，选择其他颜色。", en: "Annotation color  (C to cycle)\nCurrent: \(ink.title(language)). Click to open the palette.")
            : language.pick(zh: "标注颜色\n先选择矩形、椭圆、箭头、画笔或文字，再设置颜色。", en: "Annotation color\nChoose a rectangle, ellipse, arrow, pen or text tool to set its color.")
        setHoverHelp(colorLabel, for: colorButton)
        palette.isHidden = toolbar.isHidden || !hasToolOptions || !showsPalette || analyzing
        if !palette.isHidden {
            let anchor = toolButtons[effectiveTool]?.frame.midX ?? colorButton.frame.midX
            let x = min(max(8, toolbar.frame.minX + anchor - palette.frame.width / 2), bounds.maxX - palette.frame.width - 8)
            let below = toolbar.frame.minY - palette.frame.height - 6
            let y = below >= 8 ? below : min(bounds.maxY - palette.frame.height - 8, toolbar.frame.maxY + 6)
            palette.setFrameOrigin(CGPoint(x: x, y: y))
        }
        for (color, button) in paletteButtons {
            button.isHidden = !supportsInk
            button.state = color == ink ? .on : .off
            button.needsDisplay = true
        }
        if sizeControl != nil {
            let text = effectiveTool == .text || effectiveTool == .sticker
            for (index, label) in (text ? ["小", "中", "大"] : ["细", "中", "粗"]).enumerated() {
                sizeControl.setLabel(language == .zhHans ? label : (text ? ["S", "M", "L"] : ["1", "3", "6"])[index], forSegment: index)
            }
            let value = effectiveTool == .text ? textSize : effectiveTool == .sticker ? stickerSize : strokeWidth
            let sizes: [CGFloat] = effectiveTool == .text ? [14, 21, 32] : effectiveTool == .sticker ? [24, 40, 64] : [1, 3, 6]
            sizeControl.isEnabled = effectiveTool != .mosaic || mosaicBrush
            sizeControl.selectedSegment = sizes.enumerated().min(by: { abs($0.element - value) < abs($1.element - value) })?.offset ?? 1
            fillControl.isHidden = ![.rectangle, .ellipse].contains(effectiveTool)
            fillControl.state = filled ? .on : .off
            customStickerField.isHidden = effectiveTool != .sticker
            mosaicControl.isHidden = effectiveTool != .mosaic
            mosaicControl.selectedSegment = mosaicBrush ? 0 : 1
            for button in stickerButtons {
                button.isHidden = effectiveTool != .sticker
                button.alphaValue = stickers[button.tag] == sticker ? 1 : 0.55
            }
        }
        let sizeHelp: String
        switch effectiveTool {
        case .selection:
            sizeHelp = language.pick(zh: "线宽 / 字号\n先选择标注工具，或点选已有标注，再调整大小。", en: "Width / Size\nChoose a drawing tool or select an existing annotation to adjust its size.")
        case .text:
            sizeHelp = language.pick(zh: "字号  ([ / ] 调整)\n当前 \(Int(textSize))。点击选择小、中、大字号。", en: "Text size  ([ / ] to adjust)\nCurrent: \(Int(textSize)). Click to choose small, medium or large text.")
        case .sticker:
            sizeHelp = language.pick(zh: "表情大小  ([ / ] 调整)\n当前 \(Int(stickerSize))。点击选择小、中、大表情。", en: "Sticker size  ([ / ] to adjust)\nCurrent: \(Int(stickerSize)). Click to choose a sticker size.")
        case .mosaic where !mosaicBrush:
            sizeHelp = language.pick(zh: "马赛克画笔粗细\n框选模式不使用线宽；切换为画笔后可调整涂抹粗细。", en: "Mosaic brush width\nRectangle mode has no stroke width. Switch to Brush to adjust it.")
        default:
            sizeHelp = language.pick(zh: "线宽  ([ / ] 调整)\n当前 \(Int(strokeWidth))。点击选择细、中、粗线条。", en: "Stroke width  ([ / ] to adjust)\nCurrent: \(Int(strokeWidth)). Click to choose thin, medium or thick strokes.")
        }
        setHoverHelp(sizeHelp, for: widthButton)
        setHoverHelp(sizeHelp, for: sizeControl)
        setHoverHelp(language.pick(zh: "撤销  (⌘Z)\n" + (model.canUndo ? "撤回上一步选区或标注修改。" : "当前没有可撤销的操作。"), en: "Undo  (⌘Z)\n" + (model.canUndo ? "Undo the last selection or annotation change." : "There are no changes to undo.")), for: undoButton)
        setHoverHelp(language.pick(zh: "重做  (⇧⌘Z)\n" + (model.canRedo ? "恢复刚刚撤销的操作。" : "当前没有可恢复的操作。"), en: "Redo  (⇧⌘Z)\n" + (model.canRedo ? "Restore the last undone change." : "There are no changes to redo.")), for: redoButton)
        needsDisplay = true
    }
}

@MainActor
private final class ScreenshotHoverHelpView: NSView {
    private var text = NSAttributedString()

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setText(_ value: String, maxWidth: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        let styled = NSMutableAttributedString(string: value, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(white: 0.88, alpha: 1),
            .paragraphStyle: paragraph
        ])
        let heading = (value as NSString).range(of: "\n")
        styled.addAttributes([.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white],
                             range: NSRange(location: 0, length: heading.location == NSNotFound ? styled.length : heading.location))
        text = styled
        let size = text.boundingRect(with: CGSize(width: max(40, maxWidth - 24), height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        frame.size = CGSize(width: ceil(size.width) + 24, height: ceil(size.height) + 18)
        setAccessibilityLabel(value)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor(white: 0.12, alpha: 1).setFill()
        background.fill()
        NSColor(white: 0.4, alpha: 1).setStroke()
        background.stroke()
        text.draw(with: bounds.insetBy(dx: 12, dy: 9), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}


@MainActor
private final class ScreenshotColorSwatch: NSButton {
    private let ink: ScreenshotInk

    init(ink: ScreenshotInk) {
        self.ink = ink
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let selected = state == .on
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
        NSColor.white.withAlphaComponent(selected || isHighlighted ? 0.16 : 0.06).setFill()
        tile.fill()
        NSColor.white.withAlphaComponent(selected ? 1 : 0.22).setStroke()
        tile.lineWidth = selected ? 2 : 1
        tile.stroke()
        let swatch = NSBezierPath(ovalIn: bounds.insetBy(dx: 7, dy: 7))
        ink.color.setFill()
        swatch.fill()
    }
}
