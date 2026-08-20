import AppKit
import XCTest
@testable import Magpie

@MainActor
final class ScreenshotCoordinatorTests: XCTestCase {
    func testSystemCommandUsesInteractiveToolbarAndClipboard() {
        XCTAssertEqual(SystemScreenshotCommand.executableURL.path, "/usr/sbin/screencapture")
        XCTAssertEqual(SystemScreenshotCommand.arguments, ["-i", "-U", "-c", "-d"])
    }

    func testPermissionDeniedDoesNotHidePanelOrLaunchCommand() {
        let dependencies = makeDependencies(panelVisible: true)
        dependencies.permission.hasAccessValue = false
        dependencies.permission.requestAccessValue = false
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()

        XCTAssertEqual(coordinator.lastResult, .permissionDenied)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(dependencies.permission.requestCount, 1)
        XCTAssertEqual(dependencies.runner.runCount, 0)
        XCTAssertEqual(dependencies.panel.hideCount, 0)
        XCTAssertEqual(dependencies.feedback.permissionDeniedCount, 1)
    }

    func testSuccessfulCaptureHidesVisiblePanelAndRoutesClipboardOnce() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()

        XCTAssertTrue(coordinator.isCapturing)
        XCTAssertEqual(dependencies.panel.hideCount, 1)
        XCTAssertEqual(dependencies.router.preparedOrigins, [.explicitScreenshot])
        XCTAssertEqual(dependencies.runner.runCount, 1)

        dependencies.pasteboard.changeCount = 11
        dependencies.pasteboard.containsImage = true
        dependencies.runner.finish(.success(0))

        XCTAssertEqual(coordinator.lastResult, .captured)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(dependencies.router.polledOrigins, [.explicitScreenshot])
        XCTAssertEqual(dependencies.panel.showCount, 0)
        XCTAssertEqual(dependencies.feedback.launchFailures, [])
    }

    func testCancelledOrNonImageCaptureRestoresPreviouslyVisiblePanel() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()
        dependencies.runner.finish(.success(1))

        XCTAssertEqual(coordinator.lastResult, .cancelledOrNonImage)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(dependencies.router.cancelledOrigins, [.explicitScreenshot])
        XCTAssertEqual(dependencies.router.polledOrigins, [])
        XCTAssertEqual(dependencies.panel.showCount, 1)
    }

    func testLaunchFailureRestoresPanelAndShowsFeedback() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()
        dependencies.runner.finish(.failure(FakeScreenshotError.launchFailed))

        XCTAssertEqual(coordinator.lastResult, .launchFailed("fake launch failure"))
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(dependencies.router.cancelledOrigins, [.explicitScreenshot])
        XCTAssertEqual(dependencies.panel.showCount, 1)
        XCTAssertEqual(dependencies.feedback.launchFailures, ["fake launch failure"])
    }

    func testRepeatedCaptureWhileCommandRunsIsIgnored() {
        let dependencies = makeDependencies(panelVisible: false)
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()
        coordinator.capture()

        XCTAssertTrue(coordinator.isCapturing)
        XCTAssertEqual(dependencies.runner.runCount, 1)
        XCTAssertEqual(dependencies.router.preparedOrigins, [.explicitScreenshot])
    }

    func testExplicitScreenshotPolicyBypassesPassiveIgnoreListAndUsesMagpieSource() {
        let policy = ClipboardIngestPolicy.forChange(
            origin: .explicitScreenshot,
            observedAppBundleIdentifier: "com.example.Ignored",
            magpieBundleIdentifier: "com.sanwan.magpie",
            ignoredApps: ["com.example.Ignored", "com.sanwan.magpie"],
            skipSecretLooking: true
        )

        XCTAssertEqual(policy.appBundleIdentifier, "com.sanwan.magpie")
        XCTAssertTrue(policy.ignoredApps.isEmpty)
        XCTAssertTrue(policy.skipSecretLooking)
    }

    func testObservedPolicyKeepsFrontmostSourceAndIgnoreList() {
        let ignoredApps = ["com.example.Ignored"]
        let policy = ClipboardIngestPolicy.forChange(
            origin: .observed,
            observedAppBundleIdentifier: "com.example.Editor",
            magpieBundleIdentifier: "com.sanwan.magpie",
            ignoredApps: ignoredApps,
            skipSecretLooking: false
        )

        XCTAssertEqual(policy.appBundleIdentifier, "com.example.Editor")
        XCTAssertEqual(policy.ignoredApps, ignoredApps)
        XCTAssertFalse(policy.skipSecretLooking)
    }

    func testClipboardWatcherPollNowProcessesScreenshotOnlyOnce() throws {
        let pasteboard = NSPasteboard(name: .init("MagpieTests.Screenshot.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let watcher = ClipboardWatcher(pasteboard: pasteboard, pollInterval: 60)
        let png = try makePNGData(width: 2, height: 2)
        var changes: [(ClipboardSnapshot, ClipboardChangeOrigin)] = []
        watcher.onChange = { snapshot, origin in
            changes.append((snapshot, origin))
        }

        watcher.prepareNextChange(origin: .explicitScreenshot)
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(png, forType: .png))

        XCTAssertTrue(watcher.pollNow(origin: .explicitScreenshot))
        XCTAssertFalse(watcher.pollNow(origin: .explicitScreenshot))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.1, .explicitScreenshot)
        XCTAssertEqual(changes.first?.0.imageData, png)

        pasteboard.clearContents()
    }

    func testPreparedScreenshotOriginIgnoresNonImageAndRoutesNextImage() throws {
        let pasteboard = NSPasteboard(name: .init("MagpieTests.Screenshot.Pending.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let watcher = ClipboardWatcher(pasteboard: pasteboard, pollInterval: 60)
        var origins: [ClipboardChangeOrigin] = []
        watcher.onChange = { _, origin in
            origins.append(origin)
        }
        watcher.prepareNextChange(origin: .explicitScreenshot)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("video-or-file-result", forType: .string))
        XCTAssertFalse(watcher.pollNow())
        XCTAssertTrue(origins.isEmpty)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setData(try makePNGData(width: 1, height: 1), forType: .png))
        XCTAssertTrue(watcher.pollNow())
        XCTAssertEqual(origins, [.explicitScreenshot])

        pasteboard.clearContents()
    }

    private func makeDependencies(panelVisible: Bool) -> ScreenshotTestDependencies {
        ScreenshotTestDependencies(panelVisible: panelVisible)
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class ScreenshotTestDependencies {
    let permission = FakeScreenCapturePermission()
    let runner = FakeScreenshotCommandRunner()
    let pasteboard = FakeScreenshotPasteboard()
    let panel: FakeScreenshotPanel
    let router = FakeScreenshotClipboardRouter()
    let feedback = FakeScreenshotFeedbackPresenter()

    init(panelVisible: Bool) {
        panel = FakeScreenshotPanel(isVisible: panelVisible)
    }

    func makeCoordinator() -> ScreenshotCoordinator {
        ScreenshotCoordinator(
            permission: permission,
            commandRunner: runner,
            pasteboard: pasteboard,
            panel: panel,
            clipboardRouter: router,
            feedback: feedback
        )
    }
}

@MainActor
private final class FakeScreenCapturePermission: ScreenCapturePermissionProviding {
    var hasAccessValue = true
    var requestAccessValue = true
    private(set) var requestCount = 0

    func hasAccess() -> Bool {
        hasAccessValue
    }

    func requestAccess() -> Bool {
        requestCount += 1
        return requestAccessValue
    }
}

@MainActor
private final class FakeScreenshotCommandRunner: ScreenshotCommandRunning {
    private(set) var runCount = 0
    private var completion: ((Result<Int32, Error>) -> Void)?

    func run(completion: @escaping (Result<Int32, Error>) -> Void) {
        runCount += 1
        self.completion = completion
    }

    func finish(_ result: Result<Int32, Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

@MainActor
private final class FakeScreenshotPasteboard: ScreenshotPasteboardReading {
    var changeCount = 10
    var containsImage = false
}

@MainActor
private final class FakeScreenshotPanel: ScreenshotPanelControlling {
    var isVisible: Bool
    private(set) var hideCount = 0
    private(set) var showCount = 0

    init(isVisible: Bool) {
        self.isVisible = isVisible
    }

    func hide(completion: (() -> Void)?) {
        hideCount += 1
        isVisible = false
        completion?()
    }

    func show() {
        showCount += 1
        isVisible = true
    }
}

@MainActor
private final class FakeScreenshotClipboardRouter: ScreenshotClipboardRouting {
    private(set) var preparedOrigins: [ClipboardChangeOrigin] = []
    private(set) var cancelledOrigins: [ClipboardChangeOrigin] = []
    private(set) var polledOrigins: [ClipboardChangeOrigin] = []

    func prepareNextChange(origin: ClipboardChangeOrigin) {
        preparedOrigins.append(origin)
    }

    func cancelPreparedChange(origin: ClipboardChangeOrigin) {
        cancelledOrigins.append(origin)
    }

    func pollNow(origin: ClipboardChangeOrigin) -> Bool {
        polledOrigins.append(origin)
        return true
    }
}

@MainActor
private final class FakeScreenshotFeedbackPresenter: ScreenshotFeedbackPresenting {
    private(set) var permissionDeniedCount = 0
    private(set) var launchFailures: [String] = []

    func showPermissionDenied() {
        permissionDeniedCount += 1
    }

    func showLaunchFailure(_ message: String) {
        launchFailures.append(message)
    }
}

private enum FakeScreenshotError: LocalizedError {
    case launchFailed

    var errorDescription: String? {
        "fake launch failure"
    }
}
