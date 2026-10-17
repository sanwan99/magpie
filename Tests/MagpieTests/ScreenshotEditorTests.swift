import AppKit
import CoreGraphics
import XCTest
@testable import Magpie

@MainActor
final class ScreenshotEditorTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    func testReverseDragAndMoveStayInsideScreen() {
        let rect = ScreenshotGeometry.rectangle(from: CGPoint(x: 180, y: 140), to: CGPoint(x: 20, y: 30))
        XCTAssertEqual(rect, CGRect(x: 20, y: 30, width: 160, height: 110))
        XCTAssertEqual(ScreenshotGeometry.moved(rect, by: CGPoint(x: 1000, y: -1000), within: bounds),
                       CGRect(x: 240, y: 0, width: 160, height: 110))
    }

    func testAllResizeHandlesPreserveOppositeEdgesAndMinimumSize() {
        let rect = CGRect(x: 100, y: 100, width: 100, height: 80)
        for handle in ScreenshotHandle.allCases {
            let result = ScreenshotGeometry.resized(rect, handle: handle, to: CGPoint(x: -100, y: 1000), within: bounds)
            XCTAssertTrue(bounds.contains(result), "\(handle)")
            XCTAssertGreaterThanOrEqual(result.width, 2)
            XCTAssertGreaterThanOrEqual(result.height, 2)
        }
        XCTAssertEqual(ScreenshotGeometry.resized(rect, handle: .left, to: CGPoint(x: 350, y: 120), within: bounds),
                       CGRect(x: 198, y: 100, width: 2, height: 80))
        XCTAssertEqual(ScreenshotGeometry.resized(rect, handle: .topRight, to: CGPoint(x: 250, y: 220), within: bounds),
                       CGRect(x: 100, y: 100, width: 150, height: 120))
    }

    func testUndoRedoRestoresCropAndAnnotationsTogether() {
        var model = ScreenshotEditorModel()
        model.beginChange()
        model.state.selection = CGRect(x: 10, y: 10, width: 100, height: 80)
        model.commitChange()
        let initial = model.state
        model.add(ScreenshotAnnotation(tool: .arrow, points: [CGPoint(x: 20, y: 20), CGPoint(x: 90, y: 60)]))
        let annotated = model.state
        model.beginChange()
        model.state = ScreenshotEditorState(selection: bounds)
        model.commitChange()
        model.undo()
        XCTAssertEqual(model.state, annotated)
        model.undo()
        XCTAssertEqual(model.state, initial)
        model.redo()
        XCTAssertEqual(model.state, annotated)
        model.add(ScreenshotAnnotation(tool: .text, points: [.zero], text: "测试"))
        XCTAssertFalse(model.canRedo)
    }

    func testNoOpGestureDoesNotConsumeUndoStep() {
        var model = ScreenshotEditorModel()
        model.beginChange()
        model.commitChange()
        XCTAssertFalse(model.canUndo)
    }

    func testRetinaCropKeepsPixelResolutionAndBottomLeftOrientation() throws {
        let image = try sampleImage(width: 800, height: 600)
        let state = ScreenshotEditorState(selection: CGRect(x: 20, y: 210, width: 100, height: 60))
        let output = try XCTUnwrap(ScreenshotRenderer.render(image: image, pointSize: bounds.size, state: state))
        XCTAssertEqual(output.width, 200)
        XCTAssertEqual(output.height, 120)
        let rep = NSBitmapImageRep(cgImage: output)
        let color = try XCTUnwrap(rep.colorAt(x: 100, y: 60)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
    }

    func testFractionalCropIsClampedAndPixelAligned() {
        let result = ScreenshotGeometry.pixelAligned(CGRect(x: -3, y: 1.24, width: 23.26, height: 10.51),
                                                      scale: 2, within: bounds)
        XCTAssertEqual(result, CGRect(x: 0, y: 1, width: 20.5, height: 11))
    }

    func testExportRejectsEmptyAndOutsideSelections() throws {
        let image = try sampleImage(width: 400, height: 300)
        XCTAssertNil(ScreenshotRenderer.render(image: image, pointSize: bounds.size, state: ScreenshotEditorState()))
        XCTAssertNil(ScreenshotRenderer.render(image: image, pointSize: bounds.size,
                      state: ScreenshotEditorState(selection: CGRect(x: 450, y: 350, width: 10, height: 10))))
    }

    func testMosaicChangesPixelsOnlyInsideMarkedArea() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in 0..<100 {
            context.setFillColor((x % 2 == 0 ? NSColor.white : .black).cgColor)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 100))
        }
        let image = try XCTUnwrap(context.makeImage())
        let area = CGRect(x: 0, y: 0, width: 100, height: 100)
        let mark = ScreenshotAnnotation(tool: .mosaic, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 80)])
        let output = try XCTUnwrap(ScreenshotRenderer.render(image: image, pointSize: area.size,
                                   state: ScreenshotEditorState(selection: area, annotations: [mark])))
        let original = NSBitmapImageRep(cgImage: image), edited = NSBitmapImageRep(cgImage: output)
        let before = try XCTUnwrap(original.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        let after = try XCTUnwrap(edited.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(before.redComponent, after.redComponent, accuracy: 0.01)
        let pixel = try XCTUnwrap(edited.colorAt(x: 50, y: 50)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(pixel.redComponent, 0.1)
        XCTAssertLessThan(pixel.redComponent, 0.9)
    }

    func testAllAnnotationToolsRenderIntoPNG() throws {
        let image = try sampleImage(width: 800, height: 600)
        var marks: [ScreenshotAnnotation] = []
        for (index, tool) in ScreenshotTool.allCases.filter({ $0 != .selection }).enumerated() {
            let x = CGFloat(30 + index * 55)
            marks.append(ScreenshotAnnotation(tool: tool, points: [CGPoint(x: x, y: 40), CGPoint(x: x + 40, y: 100)],
                                               ink: .white, width: 3, text: "中文"))
        }
        let data = try XCTUnwrap(ScreenshotRenderer.png(image: image, pointSize: bounds.size,
                                   state: ScreenshotEditorState(selection: bounds, annotations: marks)))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 800)
        XCTAssertEqual(rep.pixelsHigh, 600)
        try data.write(to: URL(fileURLWithPath: "/private/tmp/magpie-screenshot-annotation-test.png"))
    }

    func testCanvasSelectionAnnotationUndoAndCopyThroughEvents() throws {
        let image = try sampleImage(width: 1600, height: 1200)
        let canvas = ScreenshotCanvasView(image: image, size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 180), window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 700, y: 480), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 700, y: 480), window: window))
        XCTAssertEqual(canvas.model.state.selection, CGRect(x: 100, y: 180, width: 600, height: 300))
        canvas.keyDown(with: key("a", code: 0, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 200, y: 220), window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 450, y: 390), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 450, y: 390), window: window))
        XCTAssertEqual(canvas.model.state.annotations.count, 1)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command, window: window)))
        XCTAssertTrue(canvas.model.state.annotations.isEmpty)
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("z", code: 6, flags: [.command, .shift], window: window)))
        XCTAssertEqual(canvas.model.state.annotations.count, 1)
        let preview = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try XCTUnwrap(preview.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/magpie-screenshot-canvas-test.png"))
        var copied: Data?
        canvas.onCopy = { copied = $0 }
        canvas.keyDown(with: key("\r", code: 36, window: window))
        let output = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(copied)))
        XCTAssertEqual(output.pixelsWide, 1200)
        XCTAssertEqual(output.pixelsHigh, 600)
        window.orderOut(nil)
    }

    func testCanvasResizeMoveAndChineseTextCommit() throws {
        let canvas = ScreenshotCanvasView(image: try sampleImage(width: 1600, height: 1200),
                                          size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 180), window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 700, y: 480), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 700, y: 480), window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 700, y: 480), window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 750, y: 500), window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 750, y: 500), window: window))
        XCTAssertEqual(canvas.model.state.selection, CGRect(x: 100, y: 180, width: 650, height: 320))
        canvas.keyDown(with: key("", code: 124, flags: .shift, window: window))
        XCTAssertEqual(canvas.model.state.selection?.minX, 110)
        canvas.keyDown(with: key("t", code: 17, window: window))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 200, y: 300), window: window))
        let field = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextField }.first)
        field.stringValue = "中文标注测试"
        var copied = false
        canvas.onCopy = { _ in copied = true }
        _ = canvas.performKeyEquivalent(with: key("c", code: 8, flags: .command, window: window))
        XCTAssertFalse(copied, "Copy while editing text must not finish the screenshot")
        XCTAssertTrue(canvas.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(canvas.model.state.annotations.last?.text, "中文标注测试")
        XCTAssertNil(field.superview)
        canvas.keyDown(with: key("\r", code: 36, window: window))
        XCTAssertTrue(copied)
        window.orderOut(nil)
    }

    func testFullScreenToolbarAndCancelWithoutExport() throws {
        let canvas = ScreenshotCanvasView(image: try sampleImage(width: 1280, height: 960),
                                          size: CGSize(width: 640, height: 480), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        XCTAssertTrue(canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window)))
        XCTAssertEqual(canvas.model.state.selection, canvas.bounds)
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0.subviews.contains { $0 is NSButton } })
        XCTAssertFalse(toolbar.isHidden)
        XCTAssertTrue(canvas.bounds.contains(toolbar.frame))
        var cancelled = false
        canvas.onCancel = { cancelled = true }
        canvas.onCopy = { _ in XCTFail("Cancellation must not export") }
        canvas.onSave = { _ in XCTFail("Cancellation must not save") }
        canvas.keyDown(with: key("", code: 53, window: window))
        XCTAssertTrue(cancelled)
        window.orderOut(nil)
    }

    func testLiveFrameCaptureWhenPermissionAlreadyGranted() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw XCTSkip("Test host has no Screen Recording permission; no permission request was made.")
        }
        let frames = try await NativeScreenshotSession.captureFrames()
        XCTAssertFalse(frames.isEmpty)
        for (screen, image) in frames {
            XCTAssertEqual(image.width, Int(screen.frame.width * screen.backingScaleFactor))
            XCTAssertEqual(image.height, Int(screen.frame.height * screen.backingScaleFactor))
        }
    }

    func testRectangleDefaultsRedAndPalettePreservesExistingMarksAndToolChoice() throws {
        let canvas = ScreenshotCanvasView(image: try sampleImage(width: 1600, height: 1200),
                                          size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0.subviews.contains { $0.identifier?.rawValue == "screenshot.tool.rectangle" } })
        let rectangle = try XCTUnwrap(toolbar.subviews.first { $0.identifier?.rawValue == "screenshot.tool.rectangle" } as? NSButton)
        rectangle.performClick(nil)
        let palette = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        XCTAssertFalse(palette.isHidden)
        XCTAssertTrue(canvas.bounds.contains(palette.frame))
        XCTAssertFalse(palette.frame.intersects(toolbar.frame))
        let red = try XCTUnwrap(palette.subviews.first { $0.identifier?.rawValue == "screenshot.ink.red" } as? NSButton)
        let blue = try XCTUnwrap(palette.subviews.first { $0.identifier?.rawValue == "screenshot.ink.blue" } as? NSButton)
        XCTAssertEqual(red.state, .on)
        draw(canvas, from: CGPoint(x: 100, y: 200), to: CGPoint(x: 250, y: 330), window: window)
        XCTAssertEqual(canvas.model.state.annotations.last?.ink, .red)
        blue.performClick(nil)
        XCTAssertEqual(blue.state, .on)
        XCTAssertEqual(red.state, .off)
        draw(canvas, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 450, y: 330), window: window)
        XCTAssertEqual(canvas.model.state.annotations.map(\.ink), [.red, .blue])
        canvas.keyDown(with: key("a", code: 0, window: window))
        draw(canvas, from: CGPoint(x: 470, y: 210), to: CGPoint(x: 620, y: 350), window: window)
        XCTAssertEqual(canvas.model.state.annotations.last?.ink, .blue)
        canvas.keyDown(with: key("m", code: 46, window: window))
        XCTAssertTrue(red.isHidden)
        XCTAssertTrue(blue.isHidden)
        canvas.keyDown(with: key("r", code: 15, window: window))
        XCTAssertFalse(palette.isHidden)
        XCTAssertEqual(blue.state, .on)
        _ = canvas.performKeyEquivalent(with: key("z", code: 6, flags: .command, window: window))
        XCTAssertEqual(canvas.model.state.annotations.map(\.ink), [.red, .blue])
        XCTAssertEqual(blue.state, .on)
    }

    func testNewScreenshotStartsRedAndPaletteFitsSmallSelectionNearScreenEdge() throws {
        let size = CGSize(width: 800, height: 600)
        let context = try XCTUnwrap(CGContext(data: nil, width: 1600, height: 1200, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        let canvas = ScreenshotCanvasView(image: try XCTUnwrap(context.makeImage()), size: size, language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        draw(canvas, from: CGPoint(x: 40, y: 130), to: CGPoint(x: 760, y: 510), window: window)
        canvas.keyDown(with: key("r", code: 15, window: window))
        draw(canvas, from: CGPoint(x: 170, y: 260), to: CGPoint(x: 590, y: 420), window: window)
        XCTAssertEqual(canvas.model.state.annotations.last?.ink, .red)
        let palette = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        XCTAssertTrue(canvas.bounds.contains(palette.frame))
        let preview = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try XCTUnwrap(preview.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/magpie-red-palette-preview.png"))
        canvas.keyDown(with: key("v", code: 9, window: window))
        XCTAssertTrue(palette.isHidden)
        draw(canvas, from: CGPoint(x: 4, y: 4), to: CGPoint(x: 28, y: 28), window: window)
        canvas.keyDown(with: key("r", code: 15, window: window))
        XCTAssertFalse(palette.isHidden)
        XCTAssertTrue(canvas.bounds.contains(palette.frame))
    }

    func testHoverHelpFollowsPointerAndDoesNotEnterExport() async throws {
        let canvas = ScreenshotCanvasView(image: try sampleImage(width: 800, height: 600),
                                          size: CGSize(width: 800, height: 600), language: .zhHans)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.contentView = canvas
        defer { window.orderOut(nil) }
        draw(canvas, from: CGPoint(x: 40, y: 180), to: CGPoint(x: 760, y: 520), window: window)
        let before = try XCTUnwrap(canvas.exportPNG())
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0.subviews.contains { $0.identifier?.rawValue == "screenshot.tool.rectangle" } })
        let rectangle = try XCTUnwrap(toolbar.subviews.first { $0.identifier?.rawValue == "screenshot.tool.rectangle" })
        let ellipse = try XCTUnwrap(toolbar.subviews.first { $0.identifier?.rawValue == "screenshot.tool.ellipse" })
        let help = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.hoverHelp" })
        func hover(_ view: NSView) {
            let point = canvas.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), from: view)
            canvas.mouseMoved(with: mouse(.mouseMoved, at: point, window: window))
        }
        hover(rectangle)
        XCTAssertTrue(help.isHidden, "Do not flash a tooltip while passing over a tool")
        canvas.mouseMoved(with: mouse(.mouseMoved, at: CGPoint(x: 400, y: 400), window: window))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(help.isHidden, "Leaving the toolbar must cancel pending help")
        hover(rectangle)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(help.isHidden)
        XCTAssertTrue(help.accessibilityLabel()?.contains("矩形  (R)") == true)
        XCTAssertTrue(help.accessibilityLabel()?.contains("Shift") == true)
        XCTAssertTrue(canvas.bounds.contains(help.frame))
        XCTAssertFalse(help.frame.intersects(toolbar.frame))
        XCTAssertNil(help.hitTest(CGPoint(x: help.frame.midX, y: help.frame.midY)), "Help must not intercept clicks")
        hover(ellipse)
        XCTAssertTrue(help.isHidden, "Do not leave the previous tool's help visible")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(help.accessibilityLabel()?.contains("椭圆  (O)") == true)
        let preview = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: preview)
        try XCTUnwrap(preview.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/magpie-hover-help-preview.png"))
        XCTAssertEqual(canvas.exportPNG(), before, "Hover help must never appear in the copied screenshot")
        XCTAssertTrue(help.isHidden)
    }

    func testHoverHelpExplainsDisabledOptionsAndFitsBesidePalette() async throws {
        let canvas = ScreenshotCanvasView(image: try sampleImage(width: 480, height: 400),
                                          size: CGSize(width: 480, height: 400), language: .en)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        defer { window.orderOut(nil) }
        _ = canvas.performKeyEquivalent(with: key("a", code: 0, flags: .command, window: window))
        let toolbar = try XCTUnwrap(canvas.subviews.first { $0.subviews.contains { $0.identifier?.rawValue == "screenshot.tool.rectangle" } })
        let disabled = try XCTUnwrap(toolbar.subviews.compactMap { $0 as? NSButton }.first { !$0.isEnabled && $0.accessibilityHelp()?.contains("Annotation color") == true })
        let help = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.hoverHelp" })
        let point = canvas.convert(CGPoint(x: disabled.bounds.midX, y: disabled.bounds.midY), from: disabled)
        canvas.mouseMoved(with: mouse(.mouseMoved, at: point, window: window))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(help.isHidden)
        XCTAssertTrue(help.accessibilityLabel()?.contains("Choose a rectangle") == true)
        canvas.keyDown(with: key("t", code: 17, window: window))
        XCTAssertTrue(help.isHidden)
        let palette = try XCTUnwrap(canvas.subviews.first { $0.identifier?.rawValue == "screenshot.colorPalette" })
        let size = try XCTUnwrap(palette.subviews.first { $0 is NSSegmentedControl && !$0.isHidden })
        canvas.mouseMoved(with: mouse(.mouseMoved, at: canvas.convert(CGPoint(x: size.bounds.midX, y: size.bounds.midY), from: size), window: window))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(help.isHidden)
        XCTAssertTrue(help.accessibilityLabel()?.contains("Text size") == true)
        XCTAssertTrue(help.accessibilityLabel()?.contains("21") == true)
        XCTAssertTrue(canvas.bounds.contains(help.frame))
        XCTAssertFalse(help.frame.intersects(palette.frame))
        XCTAssertFalse(help.frame.intersects(toolbar.frame))
        canvas.isActive = false
        XCTAssertTrue(help.isHidden)
    }

    private func draw(_ canvas: ScreenshotCanvasView, from start: CGPoint, to end: CGPoint, window: NSWindow) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, window: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, window: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, window: window))
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    private func key(_ value: String, code: UInt16, flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: value,
                        charactersIgnoringModifiers: value, isARepeat: false, keyCode: code)!
    }

    private func sampleImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        return try XCTUnwrap(context.makeImage())
    }
}

/// Synthetic CPU-path baselines. Does not capture the screen or claim UI/RSS improvements.
@MainActor
final class ScreenshotPerformanceTests: XCTestCase {
    func testRetinaAndFortyMegapixelRenderAndEncodingBaselines() throws {
        for (width, height) in [(3840, 2160), (4000, 10000)] {
            try autoreleasepool {
                let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                for row in stride(from: 0, to: height, by: 64) {
                    context.setFillColor(CGColor(red: CGFloat(row % 256) / 255, green: 0.35, blue: 0.7, alpha: 1))
                    context.fill(CGRect(x: 0, y: row, width: width, height: 64))
                }
                let image = try XCTUnwrap(context.makeImage())
                let points = CGSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2)
                var state = ScreenshotEditorState(selection: CGRect(origin: .zero, size: points))
                state.annotations = [ScreenshotAnnotation(tool: .rectangle,
                    points: [CGPoint(x: 40, y: 40), CGPoint(x: 200, y: 180)])]
                let started = ProcessInfo.processInfo.systemUptime
                let rendered = try XCTUnwrap(ScreenshotRenderer.render(image: image, pointSize: points, state: state))
                let renderedAt = ProcessInfo.processInfo.systemUptime
                let appKitData = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
                let appKitAt = ProcessInfo.processInfo.systemUptime
                let imageIOData = try XCTUnwrap(ScreenshotPNG.encode(rendered))
                let imageIOAt = ProcessInfo.processInfo.systemUptime
                for data in [appKitData, imageIOData] {
                    let decoded = try XCTUnwrap(NSBitmapImageRep(data: data))
                    XCTAssertEqual(decoded.pixelsWide, width)
                    XCTAssertEqual(decoded.pixelsHigh, height)
                }
                print("IMAGE_BENCH pixels=\(width * height) renderMS=\((renderedAt - started) * 1000) appKitPNGMS=\((appKitAt - renderedAt) * 1000) imageIOPNGMS=\((imageIOAt - appKitAt) * 1000)")
            }
        }
    }
}
