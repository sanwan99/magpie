import AppKit
import Carbon
import XCTest
@testable import Magpie

final class MagpieTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Phase 0b skeleton compiles and runs.")
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

@MainActor
final class ClipsViewModelTests: XCTestCase {
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
    func testInitialLaunchRegistersCarbonHotkeyWithoutHeartbeat() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        XCTAssertEqual(driver.reinstallEventHandlerCount, 1)
        XCTAssertEqual(driver.registerCount, 1)
        XCTAssertEqual(driver.unregisterCount, 0)
        XCTAssertEqual(center.diagnosticsSnapshot.deferredRepairSchedules, 0)
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testWakeRecoveryRebuildsEventHandlerAndRegistration() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .didWake)

        XCTAssertEqual(driver.unregisterCount, 1)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 2)
        XCTAssertEqual(driver.registerCount, 2)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "didWake")
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testActiveSpaceChangeUsesOneShotRepair() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .activeSpaceDidChange)

        XCTAssertEqual(driver.unregisterCount, 1)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 2)
        XCTAssertEqual(driver.registerCount, 2)
        XCTAssertEqual(center.diagnosticsSnapshot.deferredRepairSchedules, 0)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "activeSpaceDidChange")
    }

    func testSessionAndApplicationActivationRecoverAfterLongSuspend() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .sessionDidBecomeActive)
        center.recover(after: .applicationDidBecomeActive)

        XCTAssertEqual(driver.unregisterCount, 2)
        XCTAssertEqual(driver.reinstallEventHandlerCount, 3)
        XCTAssertEqual(driver.registerCount, 3)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "applicationDidBecomeActive")
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testWillSleepUnregistersAndWakeRegistersAgain() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        center.recover(after: .willSleep)

        XCTAssertEqual(driver.unregisterCount, 1)
        XCTAssertFalse(center.diagnosticsSnapshot.registered)

        center.recover(after: .didWake)

        XCTAssertEqual(driver.registerCount, 2)
        XCTAssertTrue(center.diagnosticsSnapshot.registered)
    }

    func testRegisterFailureIsRecordedAndNextLifecycleRepairRetries() {
        let driver = FakeHotkeyRegistrationDriver()
        driver.registerStatuses = [OSStatus(eventNotHandledErr), noErr]

        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)

        XCTAssertFalse(center.diagnosticsSnapshot.registered)
        XCTAssertEqual(center.diagnosticsSnapshot.registerFailures, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.lastOSStatus, OSStatus(eventNotHandledErr))
        XCTAssertNotNil(center.diagnosticsSnapshot.lastError)

        center.recover(after: .didWake)

        XCTAssertTrue(center.diagnosticsSnapshot.registered)
        XCTAssertEqual(center.diagnosticsSnapshot.registerFailures, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.registerSuccesses, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.lastOSStatus, noErr)
        XCTAssertNil(center.diagnosticsSnapshot.lastError)
    }

    func testKeyDownUpdatesDiagnosticsAndCallsToggleHandler() {
        let driver = FakeHotkeyRegistrationDriver()
        let center = HotkeyCenter(driver: driver, deferredRepairDelay: nil)
        var toggles = 0
        center.onTogglePanel = {
            toggles += 1
        }

        driver.fireKeyDown()

        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.keyDownEvents, 1)
        XCTAssertEqual(center.diagnosticsSnapshot.lastReason, "keyDown")
    }
}

private final class FakeHotkeyRegistrationDriver: HotkeyRegistrationDriver {
    var isRegistered = false
    var registerStatuses: [OSStatus] = []
    var reinstallEventHandlerStatuses: [OSStatus] = []

    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var reinstallEventHandlerCount = 0
    private var keyDownHandler: (@MainActor () -> Void)?

    func reinstallEventHandler() -> OSStatus {
        reinstallEventHandlerCount += 1
        if reinstallEventHandlerStatuses.isEmpty {
            return noErr
        }
        return reinstallEventHandlerStatuses.removeFirst()
    }

    func register(keyDownHandler: @escaping @MainActor () -> Void) -> OSStatus {
        registerCount += 1
        self.keyDownHandler = keyDownHandler

        let status = registerStatuses.isEmpty ? noErr : registerStatuses.removeFirst()
        isRegistered = status == noErr
        return status
    }

    func unregister() -> OSStatus {
        unregisterCount += 1
        isRegistered = false
        return noErr
    }

    @MainActor
    func fireKeyDown() {
        keyDownHandler?()
    }
}
