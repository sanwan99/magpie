import AppKit
import XCTest
@testable import Magpie

@MainActor
final class ScreenshotCoordinatorTests: XCTestCase {
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

    func testRepeatedDeniedCaptureRequestsPermissionAndShowsHelpOnlyOnce() {
        let dependencies = makeDependencies(panelVisible: true)
        dependencies.permission.hasAccessValue = false
        dependencies.permission.requestAccessValue = false
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        coordinator.capture()
        coordinator.capture()
        XCTAssertEqual(dependencies.permission.requestCount, 1)
        XCTAssertEqual(dependencies.feedback.permissionDeniedCount, 1)
        XCTAssertEqual(dependencies.runner.runCount, 0)
        XCTAssertEqual(dependencies.panel.hideCount, 0)
        XCTAssertFalse(coordinator.isCapturing)
    }

    func testAccessGrantedAfterDeniedCaptureCanStartWithoutAnotherRequest() {
        let dependencies = makeDependencies(panelVisible: true)
        dependencies.permission.hasAccessValue = false
        dependencies.permission.requestAccessValue = false
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.permission.hasAccessValue = true
        coordinator.capture()
        XCTAssertEqual(dependencies.permission.requestCount, 1)
        XCTAssertEqual(dependencies.runner.runCount, 1)
        XCTAssertTrue(coordinator.isCapturing)
    }

    func testGrantedPermissionRequestStartsCapture() {
        let dependencies = makeDependencies(panelVisible: false)
        dependencies.permission.hasAccessValue = false
        dependencies.permission.requestAccessValue = true
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        XCTAssertEqual(dependencies.runner.runCount, 1)
        XCTAssertEqual(dependencies.feedback.permissionDeniedCount, 0)
    }

    func testPermissionDialogReentryDoesNotOpenAnotherDialog() {
        let dependencies = makeDependencies(panelVisible: false)
        dependencies.permission.hasAccessValue = false
        dependencies.permission.requestAccessValue = false
        let coordinator = dependencies.makeCoordinator()
        dependencies.feedback.onPermissionDenied = { coordinator.capture() }
        coordinator.capture()
        XCTAssertEqual(dependencies.permission.requestCount, 1)
        XCTAssertEqual(dependencies.feedback.permissionDeniedCount, 1)
        XCTAssertEqual(dependencies.runner.runCount, 0)
    }

    func testExplicitPermissionMenuOpensSettingsWithoutRequestingAccess() {
        let dependencies = makeDependencies(panelVisible: false)
        let coordinator = dependencies.makeCoordinator()
        coordinator.openPermissionSettings()
        XCTAssertEqual(dependencies.feedback.openSettingsCount, 1)
        XCTAssertEqual(dependencies.permission.requestCount, 0)
        XCTAssertEqual(dependencies.runner.runCount, 0)
    }

    func testSuccessfulCaptureHidesVisiblePanelAndRoutesClipboardOnce() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()

        coordinator.capture()

        XCTAssertTrue(coordinator.isCapturing)
        XCTAssertEqual(dependencies.panel.hideCount, 1)
        XCTAssertEqual(dependencies.router.preparedOrigins, [])
        XCTAssertEqual(dependencies.runner.runCount, 1)

        let png = Data([1, 2, 3])
        dependencies.runner.finish(.success(.copied(png)))
        XCTAssertEqual(dependencies.pasteboard.writes, [png])
        XCTAssertEqual(dependencies.router.preparedOrigins, [.explicitScreenshot])

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
        dependencies.runner.finish(.success(.cancelled))

        XCTAssertEqual(coordinator.lastResult, .cancelledOrNonImage)
        XCTAssertFalse(coordinator.isCapturing)
        XCTAssertEqual(dependencies.router.cancelledOrigins, [])
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
        XCTAssertEqual(dependencies.router.cancelledOrigins, [])
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
        XCTAssertEqual(dependencies.router.preparedOrigins, [])
    }

    func testPresentationDoesNotChangeClipboardOrRestorePanel() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.runner.finish(.success(.presented))
        XCTAssertEqual(coordinator.lastResult, .presented)
        XCTAssertTrue(dependencies.pasteboard.writes.isEmpty)
        XCTAssertTrue(dependencies.pasteboard.textWrites.isEmpty)
        XCTAssertTrue(dependencies.router.polledOrigins.isEmpty)
        XCTAssertEqual(dependencies.panel.showCount, 0)
    }

    func testColorCopyRoutesExplicitSourceOnce() {
        let dependencies = makeDependencies(panelVisible: false)
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.runner.finish(.success(.copiedText("#FF0000")))
        XCTAssertEqual(coordinator.lastResult, .copiedText)
        XCTAssertEqual(dependencies.pasteboard.textWrites, ["#FF0000"])
        XCTAssertEqual(dependencies.router.polledOrigins, [.explicitScreenshot])
        XCTAssertTrue(dependencies.router.preparedOrigins.isEmpty)
    }

    func testSaveDoesNotWriteClipboardOrIngestHistory() {
        let dependencies = makeDependencies(panelVisible: true)
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.runner.finish(.success(.saved))
        XCTAssertEqual(coordinator.lastResult, .saved)
        XCTAssertTrue(dependencies.pasteboard.writes.isEmpty)
        XCTAssertTrue(dependencies.router.preparedOrigins.isEmpty)
        XCTAssertTrue(dependencies.router.polledOrigins.isEmpty)
        XCTAssertEqual(dependencies.panel.showCount, 0)
    }

    func testClipboardFailureCancelsReservationAndRestoresPanel() {
        let dependencies = makeDependencies(panelVisible: true)
        dependencies.pasteboard.succeeds = false
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.runner.finish(.success(.copied(Data([1]))))
        XCTAssertEqual(dependencies.router.cancelledOrigins, [.explicitScreenshot])
        XCTAssertTrue(dependencies.router.polledOrigins.isEmpty)
        XCTAssertEqual(dependencies.panel.showCount, 1)
        XCTAssertEqual(dependencies.feedback.launchFailures.count, 1)
        XCTAssertFalse(coordinator.isCapturing)
    }

    func testCancelDoesNotWriteClipboardAndAllowsAnotherSession() {
        let dependencies = makeDependencies(panelVisible: false)
        let coordinator = dependencies.makeCoordinator()
        coordinator.capture()
        dependencies.runner.finish(.success(.cancelled))
        XCTAssertTrue(dependencies.pasteboard.writes.isEmpty)
        XCTAssertEqual(dependencies.panel.showCount, 0)
        coordinator.capture()
        XCTAssertEqual(dependencies.runner.runCount, 2)
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
    let runner = FakeScreenshotSession()
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
            session: runner,
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
private final class FakeScreenshotSession: ScreenshotSessionRunning {
    private(set) var runCount = 0
    private var completion: ((Result<ScreenshotSessionOutput, Error>) -> Void)?

    func run(completion: @escaping (Result<ScreenshotSessionOutput, Error>) -> Void) {
        runCount += 1
        self.completion = completion
    }

    func finish(_ result: Result<ScreenshotSessionOutput, Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

@MainActor
private final class FakeScreenshotPasteboard: ScreenshotPasteboardWriting {
    var succeeds = true
    private(set) var writes: [Data] = []
    private(set) var textWrites: [String] = []
    func writeText(_ text: String) -> Bool { textWrites.append(text); return succeeds }
    func writePNG(_ data: Data) -> Bool { writes.append(data); return succeeds }
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
    private(set) var openSettingsCount = 0
    var onPermissionDenied: (() -> Void)?
    private(set) var launchFailures: [String] = []

    func showPermissionDenied() {
        permissionDeniedCount += 1
        onPermissionDenied?()
    }

    func openPermissionSettings() { openSettingsCount += 1 }

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
