import AppKit
import CoreGraphics
import XCTest
import Translation
@testable import Magpie

@MainActor
final class ScreenshotAdvancedTests: XCTestCase {
    func testScrollingStitchesExactOverlapsAndRejectsDuplicateFrame() throws {
        let master = try pattern(width: 160, height: 1000)
        let first = try XCTUnwrap(master.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 300)))
        let second = try XCTUnwrap(master.cropping(to: CGRect(x: 0, y: 113, width: 160, height: 300)))
        let third = try XCTUnwrap(master.cropping(to: CGRect(x: 0, y: 224, width: 160, height: 300)))
        let stitcher = ScreenshotStitcher(image: first)
        XCTAssertEqual(stitcher.append(first), .unchanged)
        XCTAssertEqual(stitcher.append(second), .appended(113))
        XCTAssertEqual(stitcher.append(third), .appended(111))
        XCTAssertEqual(stitcher.image.height, 524)
        XCTAssertEqual(stitcher.frames, 3)
        try compare(stitcher.image, XCTUnwrap(master.cropping(to: CGRect(x: 0, y: 0, width: 160, height: 524))))
    }

    func testScrollingKeepsFixedHeaderAndFooterOnce() throws {
        let first = try pattern(width: 160, height: 340, offset: 0, fixed: 20)
        let second = try pattern(width: 160, height: 340, offset: 100, fixed: 20)
        let stitcher = ScreenshotStitcher(image: first)
        XCTAssertEqual(stitcher.append(second), .appended(100))
        try compare(stitcher.image, pattern(width: 160, height: 440, offset: 0, fixed: 20))
    }

    func testScrollingReplacesViewportCornerArtifactsInsideOverlap() throws {
        let first = try pattern(width: 160, height: 300, corners: true)
        let second = try pattern(width: 160, height: 300, offset: 100, corners: true)
        let stitcher = ScreenshotStitcher(image: first)
        XCTAssertEqual(stitcher.append(second), .appended(100))
        try compare(stitcher.image, pattern(width: 160, height: 400, corners: true))
    }

    func testScrollingFailsSafelyWithoutOverlapOrAtMemoryLimit() throws {
        let first = try pattern(width: 160, height: 300)
        let unrelated = try pattern(width: 160, height: 300, offset: 900)
        let stitcher = ScreenshotStitcher(image: first, maxPixels: 50_000)
        XCTAssertEqual(stitcher.append(unrelated), .insufficientOverlap)
        XCTAssertEqual(stitcher.image.height, 300)
        let next = try pattern(width: 160, height: 300, offset: 100)
        XCTAssertEqual(stitcher.append(next), .limitReached)
        XCTAssertEqual(stitcher.append(try pattern(width: 150, height: 300)), .sizeChanged)
    }

    func testPixelColorUsesRetinaAndBottomLeftViewCoordinates() throws {
        let data: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255,
                             0, 0, 255, 255, 0, 0, 255, 255]
        let image = try makeImage(data, width: 2, height: 2)
        let sampler = ScreenshotPixelSampler(image: image, pointSize: CGSize(width: 1, height: 1))
        XCTAssertEqual(sampler.hex(at: CGPoint(x: 0.25, y: 0.75)), "#FF0000")
        XCTAssertEqual(sampler.hex(at: CGPoint(x: 0.25, y: 0.25)), "#0000FF")
    }

    func testAnnotationHitTestingAndShiftGeometry() {
        let rectangle = ScreenshotAnnotation(tool: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 70)])
        XCTAssertTrue(rectangle.contains(CGPoint(x: 10, y: 40)))
        XCTAssertFalse(rectangle.contains(CGPoint(x: 50, y: 40)))
        let moved = rectangle.translated(by: CGPoint(x: 12, y: 8))
        XCTAssertEqual(moved.id, rectangle.id)
        XCTAssertEqual(moved.points[0], CGPoint(x: 22, y: 18))
        XCTAssertEqual(ScreenshotGeometry.constrainedEnd(start: .zero, end: CGPoint(x: 80, y: 20), tool: .rectangle), CGPoint(x: 80, y: 80))
        let end = ScreenshotGeometry.constrainedEnd(start: .zero, end: CGPoint(x: 80, y: 20), tool: .arrow)
        XCTAssertEqual(end.y, 0, accuracy: 0.01)
    }

    func testPrivacyCandidatesAndNormalizedRegionMapping() {
        XCTAssertTrue(ScreenshotAnalysis.containsPrivateText("电话：13812345678"))
        XCTAssertTrue(ScreenshotAnalysis.containsPrivateText("user@example.com"))
        XCTAssertTrue(ScreenshotAnalysis.containsPrivateText("姓名：测试用户"))
        XCTAssertFalse(ScreenshotAnalysis.containsPrivateText("截图测试 12345"))
        let rect = ScreenshotAnalysis.localRect(CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.2),
                                                in: CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(rect, CGRect(x: 116, y: 116, width: 88, height: 28))
    }

    func testOCRRecognizesSyntheticTextLocally() async throws {
        let image = NSImage(size: CGSize(width: 700, height: 160))
        image.lockFocus()
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 700, height: 160).fill()
        ("MAGPIE SCREENSHOT 12345" as NSString).draw(at: CGPoint(x: 20, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: image.size)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let result = try await ScreenshotAnalysis.analyze(cg)
        XCTAssertTrue(result.text.contains("MAGPIE"), result.text)
        XCTAssertTrue(result.text.contains("12345"), result.text)
    }

    func testMoveDeleteUndoAndDoubleClickTextEditing() throws {
        let canvas = ScreenshotCanvasView(image: try pattern(width: 800, height: 600),
                                          size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        canvas.keyDown(with: key("r", code: 15, window: window))
        drag(canvas, from: CGPoint(x: 100, y: 200), to: CGPoint(x: 220, y: 320), window: window)
        canvas.keyDown(with: key("v", code: 9, window: window))
        drag(canvas, from: CGPoint(x: 100, y: 260), to: CGPoint(x: 150, y: 280), window: window)
        XCTAssertEqual(canvas.model.state.annotations[0].points[0], CGPoint(x: 150, y: 220))
        canvas.keyDown(with: key("", code: 51, window: window))
        XCTAssertTrue(canvas.model.state.annotations.isEmpty)
        _ = canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command, window: window))
        XCTAssertEqual(canvas.model.state.annotations.count, 1)
        canvas.keyDown(with: key("t", code: 17, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 350, y: 330), window: window))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "原文字"
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 360, y: 340), window: window, clicks: 2))
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(editor.stringValue, "原文字")
        editor.stringValue = "修改后"
        _ = canvas.control(editor, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(canvas.model.state.annotations.count, 2)
        XCTAssertEqual(canvas.model.state.annotations.last?.text, "修改后")
        _ = canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command, window: window))
        XCTAssertEqual(canvas.model.state.annotations.last?.text, "原文字")
    }

    func testWindowSelectionAndColorCopyBeforeRegion() throws {
        let canvas = ScreenshotCanvasView(image: try pattern(width: 800, height: 600),
                                          size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        let target = CGRect(x: 100, y: 100, width: 300, height: 250)
        canvas.windowTargets = [ScreenshotWindowTarget(rect: target, title: "Test window")]
        canvas.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: 150, y: 150), window: window))
        var color: String?
        canvas.onCopyColor = { color = $0 }
        _ = canvas.performKeyEquivalent(with: key("c", code: 8, flags: .command, window: window))
        XCTAssertEqual(color?.count, 7)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 150, y: 150), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 150, y: 150), window: window))
        XCTAssertEqual(canvas.model.state.selection, target)
    }

    func testLiveScrollingCaptureWithOwnedTestWindow() async throws {
        guard CGPreflightScreenCaptureAccess(), let screen = NSScreen.main else {
            throw XCTSkip("Screen Recording permission is required for this integration check.")
        }
        let frame = CGRect(x: screen.visibleFrame.minX + 60, y: screen.visibleFrame.minY + 70, width: 480, height: 320)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Magpie scrolling integration test"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 480, height: 320))
        scroll.documentView = ScreenshotScrollingTestPage(frame: CGRect(x: 0, y: 0, width: 480, height: 2400))
        scroll.hasVerticalScroller = false
        window.contentView = scroll
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let global = window.convertToScreen(CGRect(x: 0, y: 0, width: 480, height: 320))
        let region = global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        var outcome: Result<Data?, Error>?
        let controller = LongScreenshotController(screen: screen, selection: region, language: .zhHans) { outcome = $0 }
        defer { controller.cancel(); window.orderOut(nil); window.close() }
        controller.start()
        let firstDeadline = Date().addingTimeInterval(5)
        while controller.capturedFrameCount < 1 && outcome == nil && Date() < firstDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if case .failure(let error) = outcome { throw error }
        XCTAssertEqual(controller.capturedFrameCount, 1)
        let initial = try XCTUnwrap(controller.capturedImage)
        let sampler = ScreenshotPixelSampler(image: initial, pointSize: CGSize(width: 480, height: 320))
        guard sampler.hex(at: CGPoint(x: 470, y: 310)) == "#FFFFFF" else {
            XCTFail("Owned test window was not visible; refusing to use another window as capture evidence.")
            return
        }
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 120))
        scroll.reflectScrolledClipView(scroll.contentView)
        window.displayIfNeeded()
        let nextDeadline = Date().addingTimeInterval(6)
        while controller.capturedFrameCount < 2 && outcome == nil && Date() < nextDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if case .failure(let error) = outcome { throw error }
        XCTAssertGreaterThanOrEqual(controller.capturedFrameCount, 2)
        controller.complete()
        let exportDeadline = Date().addingTimeInterval(5)
        while outcome == nil && Date() < exportDeadline { try await Task.sleep(for: .milliseconds(100)) }
        let data = try XCTUnwrap(try XCTUnwrap(outcome).get())
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(bitmap.pixelsWide, Int(480 * screen.backingScaleFactor))
        XCTAssertEqual(bitmap.pixelsHigh, Int(440 * screen.backingScaleFactor))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/magpie-long-live-test.png"))
    }

    func testStickerOptionsAndResultActionsProduceImagesWithoutPrematureCopy() throws {
        let canvas = ScreenshotCanvasView(image: try pattern(width: 800, height: 600), size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        canvas.keyDown(with: key("e", code: 14, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 780, y: 580), window: window))
        let sticker = try XCTUnwrap(canvas.model.state.annotations.first)
        XCTAssertEqual(sticker.tool, .sticker)
        XCTAssertTrue(canvas.bounds.contains(sticker.drawingBounds))
        let options = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        let custom = try XCTUnwrap(options.subviews.first { $0.identifier?.rawValue == "screenshot.customSticker" } as? NSTextField)
        custom.stringValue = "👨‍💻"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: custom))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 350, y: 350), window: window))
        XCTAssertEqual(canvas.model.state.annotations.last?.text, "👨‍💻")
        var actions: [String] = []
        canvas.onCopy = { _ in XCTFail("Other result actions must not copy automatically") }
        canvas.onRecognize = { data, translate in
            XCTAssertNotNil(NSBitmapImageRep(data: data))
            actions.append(translate ? "translate" : "ocr")
        }
        canvas.onPin = { data in XCTAssertNotNil(NSBitmapImageRep(data: data)); actions.append("pin") }
        canvas.onShare = { data in XCTAssertNotNil(NSBitmapImageRep(data: data)); actions.append("share") }
        canvas.onLongCapture = { actions.append("long") }
        for (value, code) in [("x", UInt16(7)), ("l", UInt16(37)), ("n", UInt16(45)), ("g", UInt16(5))] {
            canvas.keyDown(with: key(value, code: code, window: window))
        }
        _ = canvas.performKeyEquivalent(with: key("s", code: 1, flags: [.command, .shift], window: window))
        XCTAssertEqual(actions, ["ocr", "translate", "pin", "long", "share"])
        let preview = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try XCTUnwrap(preview.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/magpie-advanced-toolbar-test.png"))
    }

    func testRightClickReturnsThroughOptionsToolAndSelection() throws {
        let canvas = ScreenshotCanvasView(image: try pattern(width: 800, height: 600), size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        canvas.keyDown(with: key("r", code: 15, window: window))
        var cancelled = false
        canvas.onCancel = { cancelled = true }
        let click = mouse(.rightMouseDown, at: CGPoint(x: 300, y: 300), window: window)
        canvas.rightMouseDown(with: click)
        XCTAssertFalse(cancelled)
        canvas.rightMouseDown(with: click)
        XCTAssertNotNil(canvas.model.state.selection)
        canvas.rightMouseDown(with: click)
        XCTAssertNil(canvas.model.state.selection)
        XCTAssertFalse(cancelled)
        canvas.rightMouseDown(with: click)
        XCTAssertTrue(cancelled)
    }

    func testTranslationWithAlreadyInstalledLanguages() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Direct installed-language session requires macOS 26.") }
        let source = Locale.Language(identifier: "en"), target = Locale.Language(identifier: "zh-Hans")
        guard await LanguageAvailability().status(from: source, to: target) == .installed else {
            throw XCTSkip("Offline language packs are not installed; the test does not download them.")
        }
        let session = TranslationSession(installedSource: source, target: target)
        let result = try await session.translate("Hello, world!")
        XCTAssertFalse(result.targetText.isEmpty)
        XCTAssertNotEqual(result.targetText, "Hello, world!")
    }

    func testAdvancedEditorRendersMultilineTextAndDirectSizeOptions() throws {
        let image = NSImage(size: CGSize(width: 800, height: 600))
        image.lockFocus()
        NSColor(white: 0.96, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: 800, height: 600).fill()
        ("Magpie 截图编辑" as NSString).draw(at: CGPoint(x: 70, y: 485), withAttributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.darkGray
        ])
        ("框选 · 标注 · 文字提取 · 翻译 · 长截图 · 贴图" as NSString).draw(at: CGPoint(x: 70, y: 450), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.gray
        ])
        image.unlockFocus()
        var rect = CGRect(origin: .zero, size: image.size)
        let canvas = ScreenshotCanvasView(image: try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil)),
                                          size: image.size, language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        drag(canvas, from: CGPoint(x: 40, y: 175), to: CGPoint(x: 760, y: 545), window: window)
        canvas.keyDown(with: key("r", code: 15, window: window))
        drag(canvas, from: CGPoint(x: 90, y: 270), to: CGPoint(x: 630, y: 405), window: window)
        canvas.keyDown(with: key("t", code: 17, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 130, y: 310), window: window))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "默认红色，点色板换色\n双击文字可继续修改"
        canvas.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(canvas.model.state.annotations.last?.text.components(separatedBy: "\n").count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(canvas.model.state.annotations.last).drawingBounds.height, 30)
        let options = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        let sizes = try XCTUnwrap(options.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        sizes.selectedSegment = 2
        sizes.sendAction(sizes.action, to: sizes.target)
        let preview = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try XCTUnwrap(preview.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/magpie-parity-editor-preview.png"))
        XCTAssertNotNil(canvas.exportPNG())
    }

    func testChangingColorAndSizeKeepsActiveTextEditable() throws {
        let canvas = ScreenshotCanvasView(image: try pattern(width: 800, height: 600), size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        canvas.keyDown(with: key("t", code: 17, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 120, y: 220), window: window))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "继续编辑"
        let options = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        let blue = try XCTUnwrap(options.subviews.first { $0.identifier?.rawValue == "screenshot.ink.blue" } as? NSButton)
        blue.performClick(nil)
        let size = try XCTUnwrap(options.subviews.compactMap { $0 as? NSSegmentedControl }.first)
        size.selectedSegment = 2; size.sendAction(size.action, to: size.target)
        XCTAssertNotNil(field.superview)
        XCTAssertTrue(canvas.model.state.annotations.isEmpty)
        XCTAssertEqual(field.font?.pointSize, 32)
        XCTAssertEqual(field.stringValue, "继续编辑")
        _ = canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(canvas.model.state.annotations.last?.ink, .blue)
        XCTAssertEqual(canvas.model.state.annotations.last?.textSize, 32)
    }

    func testPinnedImageHasKeyboardZoomAndReset() throws {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        let view = ScreenshotPinnedImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = view
        defer { window.orderOut(nil) }
        let original = window.frame.size
        XCTAssertTrue(view.performKeyEquivalent(with: key("=", code: 24, flags: .command, window: window)))
        XCTAssertGreaterThan(window.frame.width, original.width)
        XCTAssertTrue(view.performKeyEquivalent(with: key("0", code: 29, flags: .command, window: window)))
        XCTAssertEqual(window.frame.width, original.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, original.height, accuracy: 1)
    }

    private func makeImage(_ data: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(data) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pattern(width: Int, height: Int, offset: Int = 0, fixed: Int = 0, corners: Bool = false) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if corners, y >= height - 20, x < 20 || x >= width - 20 {
                    bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; continue
                }
                if y < fixed { bytes[i] = 30; bytes[i + 1] = 60; bytes[i + 2] = 90; continue }
                if y >= height - fixed { bytes[i] = 190; bytes[i + 1] = 40; bytes[i + 2] = 30; continue }
                var seed = UInt32((y - fixed + offset) * width + x) &* 747796405 &+ 2891336453
                seed = ((seed >> ((seed >> 28) + 4)) ^ seed) &* 277803737
                seed = (seed >> 22) ^ seed
                bytes[i] = UInt8(truncatingIfNeeded: seed)
                bytes[i + 1] = UInt8(truncatingIfNeeded: seed >> 8)
                bytes[i + 2] = UInt8(truncatingIfNeeded: seed >> 16)
            }
        }
        return try makeImage(bytes, width: width, height: height)
    }
    private func compare(_ lhs: CGImage, _ rhs: CGImage) throws {
        XCTAssertEqual(lhs.width, rhs.width); XCTAssertEqual(lhs.height, rhs.height)
        guard lhs.width == rhs.width, lhs.height == rhs.height else { return }
        let a = NSBitmapImageRep(cgImage: lhs), b = NSBitmapImageRep(cgImage: rhs)
        for y in stride(from: 0, to: lhs.height, by: 17) {
            for x in stride(from: 0, to: lhs.width, by: 19) {
                let ca = try XCTUnwrap(a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let cb = try XCTUnwrap(b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                XCTAssertEqual(ca.redComponent, cb.redComponent, accuracy: 0.005, "x=\(x), y=\(y)")
                XCTAssertEqual(ca.greenComponent, cb.greenComponent, accuracy: 0.005)
                XCTAssertEqual(ca.blueComponent, cb.blueComponent, accuracy: 0.005)
            }
        }
    }
    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                          context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
    private func key(_ value: String, code: UInt16, flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                        context: nil, characters: value, charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
    }
    private func drag(_ canvas: ScreenshotCanvasView, from start: CGPoint, to end: CGPoint, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, window: window))
    }
}


private final class ScreenshotScrollingTestPage: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        for index in 0..<80 {
            let y = CGFloat(index * 30)
            NSColor(srgbRed: CGFloat((index * 13) % 17) / 20 + 0.1, green: 0.3, blue: 0.65, alpha: 1).setFill()
            CGRect(x: 12, y: y + 3, width: CGFloat(35 + (index * 17) % 300), height: 7).fill()
            ("Row \(index) · Magpie scroll test \(index * 137)" as NSString).draw(at: CGPoint(x: 12, y: y + 12),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        }
    }
}
