import AppKit
import Carbon
import ImageIO
import Observation
import SwiftUI
import XCTest
@testable import Magpie

final class MagpieTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Phase 0b skeleton compiles and runs.")
    }
}

@MainActor
final class ImageThumbnailLoaderTests: XCTestCase {
    func testPrefetchMakesTheFirstPreviewImmediatelyAvailable() async throws {
        let url = try makeImage(width: 512, height: 256)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe()
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        XCTAssertNil(loader.cachedImage(for: request))
        await loader.prefetch([request, request])
        XCTAssertEqual(loader.cachedImage(for: request)?.width, 256)

        var firstPhase: ImageThumbnail.Phase?
        let preview = AsyncImageThumbnail(path: url.path, maxPixelSize: 256, loader: loader) { phase in
            firstPhase = phase
            return EmptyView()
        }
        let host = NSHostingView(rootView: preview)
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        guard case .loaded = firstPhase else { return XCTFail("The first preview should use the warmed image") }
        _ = await loader.load(request)
        XCTAssertEqual(probe.count, 1)
    }
    func testDecodeRunsOffMainThreadAndCachedRequestsReuseImage() async throws {
        let url = try makeImage(width: 2048, height: 1024)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe()
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        guard case .loaded(let first) = await loader.load(request) else {
            return XCTFail("Expected a decoded thumbnail")
        }
        XCTAssertEqual(first.width, 256)
        XCTAssertEqual(first.height, 128)

        let warmStart = Date()
        for _ in 0..<20 {
            guard case .loaded(let image) = await loader.load(request) else {
                return XCTFail("Expected a cached thumbnail")
            }
            XCTAssertTrue(image === first)
        }
        let warmMilliseconds = Date().timeIntervalSince(warmStart) * 1000
        let directStart = Date()
        for _ in 0..<20 { _ = ImageThumbnail.decode(request) }
        let directMilliseconds = Date().timeIntervalSince(directStart) * 1000
        print("Thumbnail benchmark: 20 cached loads = \(warmMilliseconds) ms; 20 direct decodes = \(directMilliseconds) ms")
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.ranOnMainThread)
    }

    func testConcurrentRequestsShareOneDecode() async throws {
        let url = try makeImage(width: 512, height: 256)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe(delay: 0.03)
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        let loaded = await withTaskGroup(of: ImageThumbnail.DecodeResult.self) { group in
            for _ in 0..<12 { group.addTask { await loader.load(request) } }
            var count = 0
            for await result in group {
                if case .loaded = result { count += 1 }
            }
            return count
        }
        XCTAssertEqual(loaded, 12)
        XCTAssertEqual(probe.count, 1)
        XCTAssertFalse(probe.ranOnMainThread)
    }

    func testDifferentPreviewSizesGetSeparateThumbnails() async throws {
        let url = try makeImage(width: 512, height: 256)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe()
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        guard case .loaded(let small) = await loader.load(.init(path: url.path, maxPixelSize: 128)),
              case .loaded(let large) = await loader.load(.init(path: url.path, maxPixelSize: 256)) else {
            return XCTFail("Expected both preview sizes")
        }
        XCTAssertEqual(small.width, 128)
        XCTAssertEqual(large.width, 256)
        XCTAssertEqual(probe.count, 2)
    }

    func testDeletedAndRestoredImageDoesNotReuseStaleCacheOrFailure() async throws {
        let url = try makeImage(width: 128, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        let loader = ImageThumbnailLoader()
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        guard case .loaded = await loader.load(request) else { return XCTFail("Expected the original image") }
        try FileManager.default.removeItem(at: url)
        guard case .failed(.missingFile) = await loader.load(request) else { return XCTFail("Expected missing file") }
        XCTAssertNil(loader.cachedImage(for: request))
        _ = try makeImage(width: 256, height: 128, at: url)
        guard case .loaded(let restored) = await loader.load(request) else { return XCTFail("Expected the restored image") }
        XCTAssertEqual(restored.width, 256)
    }

    func testReplacingFileAtSamePathInvalidatesThumbnail() async throws {
        let url = try makeImage(width: 128, height: 64)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe()
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        guard case .loaded(let original) = await loader.load(request) else { return XCTFail("Expected original image") }
        _ = try makeImage(width: 512, height: 256, at: url)
        guard case .loaded(let replacement) = await loader.load(request) else { return XCTFail("Expected replacement image") }
        XCTAssertEqual(original.width, 128)
        XCTAssertEqual(replacement.width, 256)
        XCTAssertEqual(probe.count, 2)
    }

    func testCorruptImageReportsDecodeFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("magpie-thumbnail-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        let result = await ImageThumbnailLoader().load(.init(path: url.path, maxPixelSize: 256))
        guard case .failed(.decodeFailed) = result else { return XCTFail("Expected decode failure") }
    }

    func testCancelledSubscriberDoesNotCancelSharedDecode() async throws {
        let url = try makeImage(width: 512, height: 256)
        defer { try? FileManager.default.removeItem(at: url) }
        let probe = ThumbnailDecodeProbe(delay: 0.03)
        let loader = ImageThumbnailLoader(decoder: { probe.decode($0) })
        let request = ImageThumbnail.Request(path: url.path, maxPixelSize: 256)
        let first = Task { await loader.load(request) }
        first.cancel()
        guard case .loaded = await loader.load(request) else { return XCTFail("Expected shared decode to finish") }
        _ = await first.value
        XCTAssertEqual(probe.count, 1)
    }

    private func makeImage(width: Int, height: Int, at existingURL: URL? = nil) throws -> URL {
        let url = existingURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("magpie-thumbnail-\(UUID()).png")
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}

private final class ThumbnailDecodeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let delay: TimeInterval
    private var calls = 0
    private var mainThreadObserved = false

    init(delay: TimeInterval = 0) { self.delay = delay }
    var count: Int { lock.withLock { calls } }
    var ranOnMainThread: Bool { lock.withLock { mainThreadObserved } }

    func decode(_ request: ImageThumbnail.Request) -> ImageThumbnail.DecodeResult {
        lock.withLock {
            calls += 1
            mainThreadObserved = mainThreadObserved || Thread.isMainThread
        }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return ImageThumbnail.decode(request)
    }
}

@MainActor
final class SettingsStoreLoginItemTests: XCTestCase {
    func testStoredLaunchAtLoginPreferenceRegistersSystemLoginItemOnRestore() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "magpie.settings.launchAtLogin")

        let controller = FakeLoginItemController(status: .notRegistered)
        let store = SettingsStore(defaults: defaults, loginItemController: controller)

        XCTAssertEqual(controller.registerCount, 1)
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertEqual(store.launchAtLoginSystemStatus, .enabled)
    }

    func testLaunchAtLoginToggleRegistersAndUnregistersSystemLoginItem() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = FakeLoginItemController(status: .notRegistered)
        let store = SettingsStore(defaults: defaults, loginItemController: controller)

        store.launchAtLogin = true

        XCTAssertEqual(controller.registerCount, 1)
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertEqual(store.launchAtLoginSystemStatus, .enabled)

        store.launchAtLogin = false

        XCTAssertEqual(controller.unregisterCount, 1)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.launchAtLoginSystemStatus, .notRegistered)
    }

    func testLaunchAtLoginRegisterFailureRollsBackToSystemStatus() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = FakeLoginItemController(status: .notRegistered)
        controller.registerError = FakeLoginItemError.denied
        let store = SettingsStore(defaults: defaults, loginItemController: controller)

        store.launchAtLogin = true

        XCTAssertEqual(controller.registerCount, 1)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(store.launchAtLoginSystemStatus, .notRegistered)
        XCTAssertEqual(store.launchAtLoginErrorMessage, "Login item denied")
    }

    func testLaunchAtLoginUsesSystemStatusOnRestore() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: "magpie.settings.launchAtLogin")

        let controller = FakeLoginItemController(status: .enabled)
        let store = SettingsStore(defaults: defaults, loginItemController: controller)

        XCTAssertTrue(store.launchAtLogin)
        XCTAssertEqual(store.launchAtLoginSystemStatus, .enabled)
        XCTAssertEqual(controller.registerCount, 0)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "MagpieTests.SettingsStoreLoginItem.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
final class PanelWindowTests: XCTestCase {
    func testPreparingContentDrawsWithoutOpeningThePanel() {
        let content = PreparationTestView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let material = PanelMaterialView(content: content, frame: content.frame)
        let panel = PanelWindow(contentRect: content.frame)
        panel.contentView = material
        material.update(surface: .frosted, material: .menu)
        let keyWindow = NSApp.keyWindow
        material.prepareContent()
        XCTAssertGreaterThan(content.layoutCount, 0)
        XCTAssertGreaterThan(content.drawCount, 0)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
    }
    func testPanelMovesToActiveSpaceWhenOrderedFront() {
        let panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
        defer { panel.close() }

        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(panel.collectionBehavior.contains(.stationary))
    }
}

@MainActor
private final class PreparationTestView: NSView {
    var layoutCount = 0
    var drawCount = 0
    override func layout() {
        layoutCount += 1
        super.layout()
    }
    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        NSColor.white.setFill()
        dirtyRect.fill()
    }
}

@MainActor
final class SettingsStoreAppearanceTests: XCTestCase {
    func testLegacyAppearanceSettingsKeepThemeFlavorAndOpacity() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dark", forKey: "magpie.settings.theme")
        defaults.set("blue", forKey: "magpie.settings.flavor")
        defaults.set(0.76, forKey: "magpie.settings.panelOpacity")
        defaults.set(20.0, forKey: "magpie.settings.vibrancy")

        let store = SettingsStore(defaults: defaults, loginItemController: FakeLoginItemController(status: .notRegistered))

        XCTAssertEqual(store.panelSurface, .liquidGlass)
        XCTAssertEqual(store.theme, .dark)
        XCTAssertEqual(store.flavor, .blue)
        XCTAssertEqual(store.panelOpacity, 0.76, accuracy: 0.001)
        XCTAssertEqual(store.vibrancy, 20.0)
    }

    func testSurfaceChoiceSurvivesRestoringSettings() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults, loginItemController: FakeLoginItemController(status: .notRegistered))

        for surface in PanelSurface.allCases {
            store.panelSurface = surface
            let restored = SettingsStore(defaults: defaults, loginItemController: FakeLoginItemController(status: .notRegistered))
            XCTAssertEqual(restored.panelSurface, surface)
            XCTAssertEqual(defaults.string(forKey: "magpie.settings.panelSurface"), surface.rawValue)
        }
    }

    func testUnknownSurfaceFallsBackWithoutChangingTheme() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("future-material", forKey: "magpie.settings.panelSurface")
        defaults.set("light", forKey: "magpie.settings.theme")

        let store = SettingsStore(defaults: defaults, loginItemController: FakeLoginItemController(status: .notRegistered))

        XCTAssertEqual(store.panelSurface, .liquidGlass)
        XCTAssertEqual(store.theme, .light)
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "MagpieTests.SettingsStoreAppearance.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

@MainActor
private final class FakeLoginItemController: LoginItemControlling {
    var status: LoginItemRegistrationStatus
    var registerResultStatus: LoginItemRegistrationStatus
    var unregisterResultStatus: LoginItemRegistrationStatus
    var registerError: Error?
    var unregisterError: Error?
    var registerCount = 0
    var unregisterCount = 0

    init(
        status: LoginItemRegistrationStatus,
        registerResultStatus: LoginItemRegistrationStatus = .enabled,
        unregisterResultStatus: LoginItemRegistrationStatus = .notRegistered
    ) {
        self.status = status
        self.registerResultStatus = registerResultStatus
        self.unregisterResultStatus = unregisterResultStatus
    }

    func register() throws {
        registerCount += 1
        if let registerError {
            throw registerError
        }
        status = registerResultStatus
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = unregisterResultStatus
    }
}

private enum FakeLoginItemError: LocalizedError {
    case denied

    var errorDescription: String? {
        "Login item denied"
    }
}

@MainActor
final class PasterTests: XCTestCase {
    func testFileAndFolderDefaultPasteWritesFileURLs() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-paster-tests-\(UUID().uuidString)", isDirectory: true)
        let folderURL = tempRoot.appendingPathComponent("Folder", isDirectory: true)
        let fileURL = tempRoot.appendingPathComponent("report.pdf", isDirectory: false)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: fileURL.path, contents: Data("pdf".utf8))
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileClip = ClipDisplayItem(
            id: "file",
            type: .file,
            app: "Finder",
            createdAt: Date(),
            pinned: false,
            note: "",
            title: "report.pdf",
            preview: .file(path: fileURL.path, kind: "PDF", sizeKB: 32)
        )
        let folderClip = ClipDisplayItem(
            id: "folder",
            type: .folder,
            app: "Finder",
            createdAt: Date(),
            pinned: false,
            note: "",
            title: "Magpie",
            preview: .folder(path: folderURL.path, items: 12)
        )

        Paster.writeToPasteboard(fileClip)
        XCTAssertEqual(readFileURLFromPasteboard()?.path, fileURL.path)

        Paster.writeToPasteboard(folderClip)
        XCTAssertEqual(readFileURLFromPasteboard()?.path, folderURL.path)
    }

    func testFileAndFolderPathActionWritesPathStringToPasteboard() {
        let filePath = "/Users/example/Desktop/report.pdf"
        let folderPath = "/Users/example/Projects/Magpie"

        let fileClip = ClipDisplayItem(
            id: "file",
            type: .file,
            app: "Finder",
            createdAt: Date(),
            pinned: false,
            note: "",
            title: "report.pdf",
            preview: .file(path: filePath, kind: "PDF", sizeKB: 32)
        )
        let folderClip = ClipDisplayItem(
            id: "folder",
            type: .folder,
            app: "Finder",
            createdAt: Date(),
            pinned: false,
            note: "",
            title: "Magpie",
            preview: .folder(path: folderPath, items: 12)
        )

        Paster.writePathToPasteboard(fileClip)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), filePath)

        Paster.writePathToPasteboard(folderClip)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), folderPath)
    }

    private func readFileURLFromPasteboard() -> URL? {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: nil
        ) as? [URL]
        return objects?.first
    }
}

private final class ObservationChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var changes = 0
    var count: Int { lock.withLock { changes } }
    func increment() { lock.withLock { changes += 1 } }
}

@MainActor
final class ClipsViewModelTests: XCTestCase {
    private var savedLayout: Any?

    override func setUp() async throws {
        try await super.setUp()
        savedLayout = UserDefaults.standard.object(forKey: "magpie.activeLayout")
    }

    override func tearDown() async throws {
        if let savedLayout {
            UserDefaults.standard.set(savedLayout, forKey: "magpie.activeLayout")
        } else {
            UserDefaults.standard.removeObject(forKey: "magpie.activeLayout")
        }
        try await super.tearDown()
    }

    func testUnchangedPanelRefreshDoesNotRepublishClips() async throws {
        let viewModel = try await makeViewModel(clipCount: 2)
        viewModel.focusedIndex = 1
        let changes = ObservationChangeCounter()
        withObservationTracking {
            _ = viewModel.clips
            _ = viewModel.totalClipCount
        } onChange: {
            changes.increment()
        }
        viewModel.refreshForPanelShow()
        try await waitUntil { viewModel.focusedIndex == 0 }
        XCTAssertEqual(changes.count, 0)
        XCTAssertEqual(viewModel.clips.count, 2)
    }

    func testChangedClipboardContentsStillPublishAfterPanelRefresh() async throws {
        let database = Database.makeInMemoryForTests()
        let repository = ClipRepository(database: database)
        try insertText("old content", repository: repository)
        let viewModel = ClipsViewModel(repository: repository)
        try await waitUntil { viewModel.clips.count == 1 }
        let changes = ObservationChangeCounter()
        withObservationTracking { _ = viewModel.clips } onChange: { changes.increment() }
        try insertText("new content", repository: repository)
        viewModel.refreshForPanelShow()
        try await waitUntil { viewModel.clips.count == 2 }
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(viewModel.focusedClip?.title, "new content")
    }

    func testCompactTextPreviewPreservesFullContentForDetailAndPaste() {
        let body = String(repeating: "👩🏽‍💻中文", count: 3000)
        let clip = ClipDisplayItem(id: "long-text", type: .text, app: nil, createdAt: Date(),
                                   pinned: false, note: "", title: "Long text", preview: .text(body))
        XCTAssertEqual(clip.card.previewText, String(body.prefix(512)))
        XCTAssertEqual(clip.card.previewText?.count, 512)
        guard case .text(let full) = clip.preview else { return XCTFail("Expected full text") }
        XCTAssertEqual(full, body)
    }

    func testCompactCodePreviewPreservesLanguageAndFullSource() {
        let body = String(repeating: "let value = 123\n", count: 3000)
        let clip = ClipDisplayItem(id: "long-code", type: .code, app: nil, createdAt: Date(),
                                   pinned: false, note: "", title: "Long code", preview: .code(body: body, lang: "swift"))
        guard case .code(let short, let shortLanguage) = clip.card.preview,
              case .code(let full, let fullLanguage) = clip.preview else { return XCTFail("Expected code") }
        XCTAssertEqual(short.count, 512)
        XCTAssertEqual(full, body)
        XCTAssertEqual(shortLanguage, fullLanguage)
    }
    func testPanelShowRefreshFocusesNewestResult() async throws {
        let database = Database.makeInMemoryForTests()
        let repository = ClipRepository(database: database)

        try insertText("older self-test clip", repository: repository)
        try insertText("newer self-test clip", repository: repository)

        let viewModel = ClipsViewModel(repository: repository)
        try await waitUntil {
            viewModel.clips.count == 2
        }

        viewModel.focusedIndex = 1
        XCTAssertEqual(viewModel.focusedClip?.title, "older self-test clip")

        viewModel.refreshForPanelShow()
        try await waitUntil {
            viewModel.focusedClip?.title == "newer self-test clip"
        }

        XCTAssertEqual(viewModel.focusedIndex, 0)
    }

    func testGridArrowNavigationMovesByColumnCount() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "magpie.activeLayout") }
        let viewModel = try await makeViewModel(clipCount: 10)
        viewModel.activeLayout = .grid
        viewModel.updateGridColumnCount(4)
        viewModel.focusedIndex = 5

        viewModel.moveFocus(.up)
        XCTAssertEqual(viewModel.focusedIndex, 1)

        viewModel.moveFocus(.down)
        XCTAssertEqual(viewModel.focusedIndex, 5)

        viewModel.moveFocus(.left)
        XCTAssertEqual(viewModel.focusedIndex, 4)

        viewModel.moveFocus(.right)
        XCTAssertEqual(viewModel.focusedIndex, 5)
    }

    func testGridArrowNavigationClampsVerticalEdges() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "magpie.activeLayout") }
        let viewModel = try await makeViewModel(clipCount: 10)
        viewModel.activeLayout = .grid
        viewModel.updateGridColumnCount(4)

        viewModel.focusedIndex = 2
        viewModel.moveFocus(.up)
        XCTAssertEqual(viewModel.focusedIndex, 2)

        viewModel.focusedIndex = 7
        viewModel.moveFocus(.down)
        XCTAssertEqual(viewModel.focusedIndex, 9)

        viewModel.moveFocus(.down)
        XCTAssertEqual(viewModel.focusedIndex, 9)
    }

    func testOneDimensionalLayoutsKeepLegacyArrowNavigation() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "magpie.activeLayout") }
        let viewModel = try await makeViewModel(clipCount: 10)
        viewModel.updateGridColumnCount(4)

        viewModel.activeLayout = .stripe
        viewModel.focusedIndex = 5
        viewModel.moveFocus(.up)
        XCTAssertEqual(viewModel.focusedIndex, 4)
        viewModel.moveFocus(.down)
        XCTAssertEqual(viewModel.focusedIndex, 5)

        viewModel.activeLayout = .stack
        viewModel.focusedIndex = 5
        viewModel.moveFocus(.up)
        XCTAssertEqual(viewModel.focusedIndex, 4)
        viewModel.moveFocus(.down)
        XCTAssertEqual(viewModel.focusedIndex, 5)
    }

    private func insertText(_ body: String, repository: ClipRepository) throws {
        let detected = DetectedClip(
            type: .text,
            app: "abnerworks.Typora",
            title: body,
            payload: try JSONEncoder().encode(TextPayload(body: body)),
            searchText: body
        )
        try repository.insert(detected)
        Thread.sleep(forTimeInterval: 0.01)
    }

    private func makeViewModel(clipCount: Int) async throws -> ClipsViewModel {
        let database = Database.makeInMemoryForTests()
        let repository = ClipRepository(database: database)
        for index in 0..<clipCount {
            try insertText("navigation clip \(index)", repository: repository)
        }

        let viewModel = ClipsViewModel(repository: repository)
        try await waitUntil {
            viewModel.clips.count == clipCount
        }
        return viewModel
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}

@MainActor
final class HotkeyCenterTests: XCTestCase {
    func testInitialLaunchRegistersPanelAndScreenshotHotkeysWithoutHeartbeat() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        XCTAssertEqual(driver.reinstallEventHandlerCount, 1)
        XCTAssertEqual(driver.registeredActionHistory, [.togglePanel, .captureScreenshot])
        XCTAssertEqual(driver.unregisterAllCount, 0)
        XCTAssertEqual(center.diagnosticsSnapshot.deferredRepairSchedules, 0)
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
        XCTAssertEqual(center.diagnosticsSnapshot.registeredActions, Set(GlobalHotkeyAction.allCases))
    }

    func testWakeRecoveryRebuildsEventHandlerAndRegistration() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .didWake)

        XCTAssertEqual(driver.unregisterAllCount, 1)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 2)
        XCTAssertEqual(driver.registeredActionHistory.count, 4)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "didWake")
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testActiveSpaceChangeUsesOneShotRepair() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .activeSpaceDidChange)

        XCTAssertEqual(driver.unregisterAllCount, 1)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 2)
        XCTAssertEqual(driver.registeredActionHistory.count, 4)
        XCTAssertEqual(center.diagnosticsSnapshot.deferredRepairSchedules, 0)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "activeSpaceDidChange")
    }

    func testSessionAndApplicationActivationRecoverAfterLongSuspend() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .sessionDidBecomeActive)
        center.recover(after: .applicationDidBecomeActive)

        XCTAssertEqual(driver.unregisterAllCount, 2)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 3)
        XCTAssertEqual(driver.registeredActionHistory.count, 6)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "applicationDidBecomeActive")
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testWillSleepUnregistersAndWakeRegistersAgain() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .willSleep)

        XCTAssertEqual(driver.unregisterAllCount, 1)
        XCTAssertFalse(center.diagnosticsSnapshot.registered)

        center.recover(after: .didWake)

        XCTAssertEqual(driver.registeredActionHistory.count, 4)
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testScreenshotRegisterFailureDoesNotDisablePanelAndLifecycleRepairRetries() {
        let driver = FakeHotkeyRegistrationDriver()
        driver.registerStatuses[.captureScreenshot] = [OSStatus(eventNotHandledErr), noErr]

        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        XCTAssertFalse(center.diagnosticsSnapshot.registered)
        XCTAssertEqual(driver.registeredActions, [.togglePanel])
        XCTAssertEqual(center.diagnosticsSnapshot.registerFailures, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.lastOSStatus, OSStatus(eventNotHandledErr))
        XCTAssertEqual(
            center.diagnosticsSnapshot.registrationFailures[.captureScreenshot],
            OSStatus(eventNotHandledErr)
        )
        XCTAssertNotNil(center.diagnosticsSnapshot.lastError)

        center.recover(after: .didWake)

        XCTAssertTrue(center.diagnosticsSnapshot.registered)
        XCTAssertEqual(driver.registeredActions, Set(GlobalHotkeyAction.allCases))
        XCTAssertEqual(center.diagnosticsSnapshot.registerFailures, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.registerSuccesses, 3)
        XCTAssertEqual(center.diagnosticsSnapshot.lastOSStatus, noErr)
        XCTAssertTrue(center.diagnosticsSnapshot.registrationFailures.isEmpty)
        XCTAssertNil(center.diagnosticsSnapshot.lastError)
    }

    func testKeyDownDispatchesPanelAndScreenshotActions() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)
        var toggles = 0
        var captures = 0
        center.onTogglePanel = {
            toggles += 1
        }
        center.onCaptureScreenshot = {
            captures += 1
        }

        driver.fireKeyDown(.togglePanel)
        driver.fireKeyDown(.captureScreenshot)

        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.keyDownEvents, 2)
        XCTAssertEqual(center.diagnosticsSnapshot.lastAction, .captureScreenshot)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "keyDown")
    }
}

private final class FakeHotkeyRegistrationDriver: HotkeyRegistrationDriver {
    var registeredActions: Set<GlobalHotkeyAction> = []
    var registerStatuses: [GlobalHotkeyAction: [OSStatus]] = [:]
    var reinstallEventHandlerStatuses: [OSStatus] = []

    private(set) var registeredBindings: [GlobalHotkeyAction: HotkeyBinding] = [:]
    private(set) var registeredActionHistory: [GlobalHotkeyAction] = []
    private(set) var unregisterAllCount = 0
    private(set) var reinstallEventHandlerCount = 0
    private var keyDownHandler: (@MainActor (GlobalHotkeyAction) -> Void)?

    func reinstallEventHandler() -> OSStatus {
        reinstallEventHandlerCount += 1
        if reinstallEventHandlerStatuses.isEmpty {
            return noErr
        }
        return reinstallEventHandlerStatuses.removeFirst()
    }

    func register(
        action: GlobalHotkeyAction,
        binding: HotkeyBinding,
        keyDownHandler: @escaping @MainActor (GlobalHotkeyAction) -> Void
    ) -> OSStatus {
        registeredActionHistory.append(action)
        registeredBindings[action] = binding
        self.keyDownHandler = keyDownHandler

        var statuses = registerStatuses[action] ?? []
        let status = statuses.isEmpty ? noErr : statuses.removeFirst()
        registerStatuses[action] = statuses
        if status == noErr {
            registeredActions.insert(action)
        } else {
            registeredActions.remove(action)
        }
        return status
    }

    func unregisterAll() -> [GlobalHotkeyAction: OSStatus] {
        unregisterAllCount += 1
        let statuses = Dictionary(uniqueKeysWithValues: registeredActions.map { ($0, noErr) })
        registeredActions.removeAll()
        return statuses
    }

    @MainActor
    func fireKeyDown(_ action: GlobalHotkeyAction) {
        guard registeredActions.contains(action) else { return }
        keyDownHandler?(action)
    }
}

final class PasteValidationTests: XCTestCase {
    func testOnlyUnchangedTargetWindowAndClipboardCanReceivePaste() {
        func check(request: Bool = true, alive: Bool = true, pid: pid_t? = 42,
                   window: Bool = true, count: Int = 10, trusted: Bool = true) -> Bool {
            PasteValidation.maySend(currentRequest: request, targetAlive: alive, targetPID: 42,
                frontmostPID: pid, sameWindow: window, expectedChangeCount: 10,
                actualChangeCount: count, trusted: trusted)
        }
        XCTAssertTrue(check())
        XCTAssertFalse(check(request: false)) // Rapid second paste supersedes first.
        XCTAssertFalse(check(alive: false))
        XCTAssertFalse(check(pid: 43))
        XCTAssertFalse(check(pid: nil))
        XCTAssertFalse(check(window: false)) // Same app, different document.
        XCTAssertFalse(check(count: 11))
        XCTAssertFalse(check(trusted: false))
    }
}

@MainActor
final class CustomHotkeyTests: XCTestCase {
    func testCustomBindingSurvivesWakeAndRestore() throws {
        let name = "magpie.hotkey.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil, defaults: defaults)
        let custom = HotkeyBinding(keyCode: 35, modifiers: UInt32(cmdKey | shiftKey))
        XCTAssertTrue(center.setBinding(custom, for: .togglePanel))
        center.recover(after: .willSleep)
        center.recover(after: .didWake)
        center.recover(after: .activeSpaceDidChange)
        XCTAssertEqual(driver.registeredBindings[.togglePanel], custom)
        let restored = HotkeyCenter(driver: FakeHotkeyRegistrationDriver(), deferredRepairDelay: nil, defaults: defaults)
        XCTAssertEqual(restored.binding(for: .togglePanel), custom)
    }

    func testDuplicateAndSystemConflictRollBack() throws {
        let name = "magpie.hotkey.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil, defaults: defaults)
        let original = center.binding(for: .togglePanel)
        XCTAssertFalse(center.setBinding(center.binding(for: .captureScreenshot), for: .togglePanel))
        XCTAssertFalse(center.setBinding(.init(keyCode: 35, modifiers: 0), for: .togglePanel))
        driver.registerStatuses[.togglePanel] = [OSStatus(eventHotKeyExistsErr), noErr]
        XCTAssertFalse(center.setBinding(.init(keyCode: 35, modifiers: UInt32(cmdKey | shiftKey)), for: .togglePanel))
        XCTAssertEqual(center.binding(for: .togglePanel), original)
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
        XCTAssertNil(defaults.data(forKey: "magpie.hotkey.1"))
    }
}

final class PasteFeedbackPolicyTests: XCTestCase {
    func testChangedClipboardNeverSuggestsPastingOldRecordAndCancellationIsSilent() {
        let reason = PasteValidation.failure(currentRequest: true, targetAlive: false, targetPID: 1,
            frontmostPID: 2, sameWindow: false, expectedChangeCount: 1, actualChangeCount: 2, trusted: false)
        XCTAssertEqual(reason, .clipboardChanged)
        XCTAssertFalse(PasteFailure.clipboardChanged.message(language: .en)!.contains("⌘V"))
        XCTAssertFalse(PasteFailure.writeFailed.message(language: .en)!.contains("⌘V"))
        XCTAssertNil(PasteFailure.superseded.message(language: .en))
        XCTAssertEqual(PasteValidation.failure(currentRequest: false, targetAlive: false, targetPID: 1,
            frontmostPID: 2, sameWindow: false, expectedChangeCount: 1, actualChangeCount: 2, trusted: false), .superseded)
    }

    func testEveryVisibleFailureHasChineseAndEnglishRecoveryText() {
        for failure in PasteFailure.allCases where failure != .superseded {
            XCTAssertFalse(failure.message(language: .zhHans)!.isEmpty)
            XCTAssertFalse(failure.message(language: .en)!.isEmpty)
        }
        XCTAssertEqual(PasteValidation.failure(currentRequest: true, targetAlive: true, targetPID: 1,
            frontmostPID: 1, sameWindow: true, expectedChangeCount: 1, actualChangeCount: 1, trusted: false), .permissionDenied)
    }

    func testGettingStartedCompletionPersistsWithoutTouchingOtherPreferences() throws {
        let name = "magpie.onboarding.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "magpie.settings.useTouchID")
        let preferences = GettingStartedPreferences(defaults: defaults)
        XCTAssertTrue(preferences.needsPresentation)
        preferences.complete()
        XCTAssertFalse(GettingStartedPreferences(defaults: defaults).needsPresentation)
        XCTAssertTrue(defaults.bool(forKey: "magpie.settings.useTouchID"))
    }
}

@MainActor
final class RecordingSettingsPolicyTests: XCTestCase {
    func testIgnoredAppsAndHeuristicsInvalidatePolicySynchronously() throws {
        let name = "magpie.recording.settings.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults, loginItemController: FakeLoginItemController(status: .notRegistered))
        var changes = 0
        store.onRecordingPolicyChange = { changes += 1 }
        store.ignoredApps.append("com.example.Editor")
        XCTAssertEqual(changes, 1)
        store.skipSecretLooking.toggle()
        XCTAssertEqual(changes, 2)
        store.ignoredApps.removeAll()
        XCTAssertEqual(changes, 3)
    }
}
