import AppKit

enum ScreenshotTool: String, CaseIterable {
    case selection, rectangle, ellipse, sticker, arrow, pen, mosaic, text

    var shortcut: String {
        switch self {
        case .sticker: return "e"
        case .selection: return "v"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .arrow: return "a"
        case .pen: return "p"
        case .text: return "t"
        case .mosaic: return "m"
        }
    }

    var symbol: String {
        switch self {
        case .sticker: return "face.smiling"
        case .selection: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3.fill"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .sticker: return language.pick(zh: "表情", en: "Sticker")
        case .selection: return language.pick(zh: "选区 / 选中标注", en: "Select region / annotation")
        case .rectangle: return language.pick(zh: "矩形", en: "Rectangle")
        case .ellipse: return language.pick(zh: "椭圆", en: "Ellipse")
        case .arrow: return language.pick(zh: "箭头", en: "Arrow")
        case .pen: return language.pick(zh: "画笔", en: "Pen")
        case .text: return language.pick(zh: "文字", en: "Text")
        case .mosaic: return language.pick(zh: "马赛克", en: "Mosaic")
        }
    }

    func help(_ language: AppLanguage) -> String {
        let detail: String
        switch self {
        case .selection: detail = language.pick(zh: "拖动调整选区；点选标注后可移动、缩放或删除。", en: "Adjust the capture area, or select a mark to move, resize or delete it.")
        case .rectangle: detail = language.pick(zh: "拖动画矩形框；按住 Shift 画正方形。", en: "Drag to draw a rectangle. Hold Shift for a square.")
        case .ellipse: detail = language.pick(zh: "拖动画椭圆；按住 Shift 画圆形。", en: "Drag to draw an ellipse. Hold Shift for a circle.")
        case .sticker: detail = language.pick(zh: "选择表情后，点击截图放置；可调整大小。", en: "Choose an emoji, then click to place it. Its size is adjustable.")
        case .arrow: detail = language.pick(zh: "拖动画箭头；按住 Shift 对齐到 45° 方向。", en: "Drag to draw an arrow. Hold Shift to snap to 45° angles.")
        case .pen: detail = language.pick(zh: "按住鼠标自由涂画，可选择颜色和线宽。", en: "Drag to draw freehand. Choose a color and stroke width.")
        case .mosaic: detail = language.pick(zh: "涂抹或框选区域，用马赛克遮住截图内容。", en: "Paint over an area or draw a rectangle to pixelate it.")
        case .text: detail = language.pick(zh: "点击输入文字；Shift+回车换行，双击已有文字修改。", en: "Click to type. Shift+Return adds a line; double-click text to edit.")
        }
        return "\(title(language))  (\(shortcut.uppercased()))\n\(detail)"
    }
}

enum ScreenshotInk: Int, CaseIterable {
    case red, orange, yellow, green, blue, purple, black, white, olive

    var color: NSColor {
        switch self {
        case .red: return NSColor(srgbRed: 0.96, green: 0.22, blue: 0.22, alpha: 1)
        case .orange: return NSColor(srgbRed: 1, green: 0.55, blue: 0.12, alpha: 1)
        case .yellow: return NSColor(srgbRed: 1, green: 0.83, blue: 0.15, alpha: 1)
        case .green: return NSColor(srgbRed: 0.16, green: 0.72, blue: 0.35, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.66, green: 0.35, blue: 0.9, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.18, green: 0.48, blue: 0.95, alpha: 1)
        case .black: return .black
        case .white: return .white
        case .olive: return NSColor(srgbRed: 0.47, green: 0.52, blue: 0.22, alpha: 1)
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .red: return language.pick(zh: "红色", en: "Red")
        case .orange: return language.pick(zh: "橙色", en: "Orange")
        case .yellow: return language.pick(zh: "黄色", en: "Yellow")
        case .green: return language.pick(zh: "绿色", en: "Green")
        case .blue: return language.pick(zh: "蓝色", en: "Blue")
        case .purple: return language.pick(zh: "紫色", en: "Purple")
        case .black: return language.pick(zh: "黑色", en: "Black")
        case .white: return language.pick(zh: "白色", en: "White")
        case .olive: return language.pick(zh: "橄榄色", en: "Olive")
        }
    }

}

struct ScreenshotAnnotation: Equatable {
    var id = UUID()
    var tool: ScreenshotTool
    var points: [CGPoint]
    var ink: ScreenshotInk = .red
    var width: CGFloat = 3
    var text = ""
    var textSize: CGFloat = 21
    var textBoxWidth: CGFloat?
    var filled = false
    var mosaicBrush = false

    var rect: CGRect {
        ScreenshotGeometry.rectangle(from: points.first ?? .zero, to: points.last ?? .zero)
    }
}

enum ScreenshotHandle: CaseIterable {
    case bottomLeft, bottom, bottomRight, right, topRight, top, topLeft, left

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum ScreenshotGeometry {
    static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    static func moved(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(max(rect.minX + delta.x, bounds.minX), max(bounds.minX, bounds.maxX - rect.width)),
               y: min(max(rect.minY + delta.y, bounds.minY), max(bounds.minY, bounds.maxY - rect.height)),
               width: rect.width, height: rect.height)
    }

    static func resized(_ rect: CGRect, handle: ScreenshotHandle, to point: CGPoint,
                        within bounds: CGRect) -> CGRect {
        let p = clamp(point, to: bounds)
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        switch handle {
        case .bottomLeft, .left, .topLeft: left = min(p.x, right - 2)
        case .bottomRight, .right, .topRight: right = max(p.x, left + 2)
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight: bottom = min(p.y, top - 2)
        case .topLeft, .top, .topRight: top = max(p.y, bottom + 2)
        default: break
        }
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Align both edges to source pixels so preview and export share the same crop.
    static func pixelAligned(_ rect: CGRect, scale: CGFloat, within bounds: CGRect) -> CGRect {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, scale > 0 else { return .zero }
        let left = (clipped.minX * scale).rounded() / scale
        let bottom = (clipped.minY * scale).rounded() / scale
        let right = (clipped.maxX * scale).rounded() / scale
        let top = (clipped.maxY * scale).rounded() / scale
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }
}

struct ScreenshotEditorState: Equatable {
    var selection: CGRect?
    var annotations: [ScreenshotAnnotation] = []
}

struct ScreenshotEditorModel {
    var state = ScreenshotEditorState()
    private var undoStack: [ScreenshotEditorState] = []
    private var redoStack: [ScreenshotEditorState] = []
    private var transaction: ScreenshotEditorState?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func beginChange() { transaction = state }

    mutating func commitChange() {
        defer { transaction = nil }
        guard let previous = transaction, previous != state else { return }
        undoStack.append(previous)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func add(_ annotation: ScreenshotAnnotation) {
        beginChange()
        state.annotations.append(annotation)
        commitChange()
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
    }
}


extension ScreenshotAnnotation {
    @MainActor var drawingBounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text || tool == .sticker {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: textSize, weight: .medium)]
            if tool == .text, let width = textBoxWidth {
                let measured = (text as NSString).boundingRect(with: CGSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
                return CGRect(origin: first, size: CGSize(width: width, height: max(textSize + 4, ceil(measured.height))))
            }
            return CGRect(origin: first, size: (text as NSString).size(withAttributes: attributes))
        }
        let left = points.map(\.x).min() ?? 0, right = points.map(\.x).max() ?? 0
        let bottom = points.map(\.y).min() ?? 0, top = points.map(\.y).max() ?? 0
        let padding = mosaicBrush ? max(12, width * 10) / 2 : width / 2
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom).insetBy(dx: -padding, dy: -padding)
    }

    @MainActor func contains(_ point: CGPoint) -> Bool {
        guard drawingBounds.insetBy(dx: -6, dy: -6).contains(point) else { return false }
        if tool == .text || tool == .sticker || filled { return true }
        if tool == .rectangle || (tool == .mosaic && !mosaicBrush) {
            return tool == .mosaic || !rect.insetBy(dx: 6, dy: 6).contains(point)
        }
        if tool == .ellipse {
            guard rect.width > 0, rect.height > 0 else { return false }
            let distance = hypot((point.x - rect.midX) / (rect.width / 2), (point.y - rect.midY) / (rect.height / 2))
            return abs(distance - 1) * min(rect.width, rect.height) / 2 <= max(6, width)
        }
        guard points.count > 1 else { return true }
        let tolerance = mosaicBrush ? max(12, width * 10) / 2 : max(6, width)
        return zip(points, points.dropFirst()).contains { start, end in
            let dx = end.x - start.x, dy = end.y - start.y
            let square = dx * dx + dy * dy
            let t = square > 0 ? min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / square)) : 0
            return hypot(point.x - start.x - t * dx, point.y - start.y - t * dy) <= tolerance
        }
    }

    func translated(by delta: CGPoint) -> ScreenshotAnnotation {
        var copy = self
        copy.points = points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return copy
    }
}

struct ScreenshotWindowTarget {
    let rect: CGRect
    let title: String
}

extension ScreenshotGeometry {
    static func constrainedEnd(start: CGPoint, end: CGPoint, tool: ScreenshotTool) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }
}
