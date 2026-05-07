import Carbon
import XCTest
@testable import Magpie

final class MagpieTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Phase 0b skeleton compiles and runs.")
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
