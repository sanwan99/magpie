import AppKit
import Carbon

/// Owns the global hotkeys. v0.1 wires only ⌘P (toggle panel).
/// Esc is handled inside the panel as a local key event, not a global hotkey.
@MainActor
final class HotkeyCenter {
    private let driver: HotkeyRegistrationDriver
    private let deferredRepairDelay: TimeInterval?
    private var pendingDeferredRepair: DispatchWorkItem?
    private var diagnostics = HotkeyDiagnostics()

    var onTogglePanel: (() -> Void)?

    init(driver: HotkeyRegistrationDriver = CarbonHotkeyRegistration(),
         deferredRepairDelay: TimeInterval? = 0.75) {
        self.driver = driver
        self.deferredRepairDelay = deferredRepairDelay
        repair(reason: "launch")
    }

    deinit {
        pendingDeferredRepair?.cancel()
    }

    var diagnosticsSnapshot: HotkeyDiagnostics {
        diagnostics
    }

    /// 系统生命周期事件后的热键修复入口。
    ///
    /// 这里做的是一次性 Carbon 链路重建：释放旧 `EventHotKeyRef`、重装事件
    /// handler、重新注册 ⌘P。它替代旧的 30 秒心跳，不做周期性轮询。
    func recover(after event: HotkeyLifecycleEvent) {
        switch event {
        case .willSleep:
            pendingDeferredRepair?.cancel()
            unregister(reason: event.rawValue)
        default:
            repair(reason: event.rawValue)
            scheduleDeferredRepair(after: event)
        }
    }

    private func scheduleDeferredRepair(after event: HotkeyLifecycleEvent) {
        guard event.schedulesDeferredRepair, let deferredRepairDelay else { return }

        pendingDeferredRepair?.cancel()
        let reason = "deferred:\(event.rawValue)"
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.repair(reason: reason)
            }
        }
        pendingDeferredRepair = work
        diagnostics.deferredRepairSchedules += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredRepairDelay, execute: work)
        NSLog("[hotkey] deferred repair scheduled reason=%@ delay=%.2fs", reason, deferredRepairDelay)
    }

    private func repair(reason: String) {
        diagnostics.repairAttempts += 1
        diagnostics.lastReason = reason
        NSLog("[hotkey] repair begin reason=%@ registered=%d repairs=%d",
              reason, driver.isRegistered ? 1 : 0, diagnostics.repairAttempts)

        if driver.isRegistered {
            unregister(reason: "\(reason):replaceStaleRegistration")
        }

        diagnostics.eventHandlerRepairAttempts += 1
        let handlerStatus = driver.reinstallEventHandler()
        guard record(status: handlerStatus, operation: "reinstallEventHandler", reason: reason) else {
            refreshRegisteredState()
            return
        }

        diagnostics.registerAttempts += 1
        let registerStatus = driver.register { [weak self] in
            self?.handleKeyDown()
        }
        if record(status: registerStatus, operation: "register", reason: reason) {
            diagnostics.registerSuccesses += 1
            NSLog("[hotkey] register ok reason=%@ attempts=%d", reason, diagnostics.registerAttempts)
        } else {
            diagnostics.registerFailures += 1
        }
        refreshRegisteredState()
    }

    private func unregister(reason: String) {
        guard driver.isRegistered else {
            refreshRegisteredState()
            return
        }

        diagnostics.unregisterAttempts += 1
        let status = driver.unregister()
        _ = record(status: status, operation: "unregister", reason: reason)
        refreshRegisteredState()
    }

    private func handleKeyDown() {
        diagnostics.keyDownEvents += 1
        diagnostics.lastReason = "keyDown"
        NSLog("[hotkey] keyDown ⌘P events=%d registered=%d",
              diagnostics.keyDownEvents, driver.isRegistered ? 1 : 0)
        onTogglePanel?()
    }

    @discardableResult
    private func record(status: OSStatus, operation: String, reason: String) -> Bool {
        diagnostics.lastOSStatus = status
        guard status == noErr else {
            let message = "\(operation) failed reason=\(reason) status=\(status)"
            diagnostics.lastError = message
            NSLog("[hotkey] %@", message)
            return false
        }
        diagnostics.lastError = nil
        return true
    }

    private func refreshRegisteredState() {
        diagnostics.registered = driver.isRegistered
    }
}

enum HotkeyLifecycleEvent: String, CaseIterable {
    case willSleep
    case didWake
    case screensDidWake
    case activeSpaceDidChange
    case sessionDidBecomeActive
    case applicationDidBecomeActive

    var schedulesDeferredRepair: Bool {
        self != .willSleep
    }
}

struct HotkeyDiagnostics: Equatable {
    var registerAttempts = 0
    var registerSuccesses = 0
    var registerFailures = 0
    var unregisterAttempts = 0
    var eventHandlerRepairAttempts = 0
    var repairAttempts = 0
    var deferredRepairSchedules = 0
    var keyDownEvents = 0
    var registered = false
    var lastReason: String?
    var lastOSStatus: OSStatus = noErr
    var lastError: String?
}

protocol HotkeyRegistrationDriver: AnyObject {
    var isRegistered: Bool { get }

    func reinstallEventHandler() -> OSStatus
    func register(keyDownHandler: @escaping @MainActor () -> Void) -> OSStatus
    func unregister() -> OSStatus
}

private final class CarbonHotkeyRegistration: HotkeyRegistrationDriver {
    private var eventHandlerRef: EventHandlerRef?
    private var eventHotKeyRef: EventHotKeyRef?
    private var keyDownHandler: (@MainActor () -> Void)?

    var isRegistered: Bool {
        eventHotKeyRef != nil
    }

    deinit {
        _ = unregister()
        removeEventHandler()
    }

    func reinstallEventHandler() -> OSStatus {
        removeEventHandler()

        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: UInt32(kEventHotKeyReleased))
        ]

        let userData = Unmanaged.passUnretained(self).toOpaque()
        return eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                magpieHotkeyEventHandler,
                buffer.count,
                buffer.baseAddress,
                userData,
                &eventHandlerRef
            )
        }
    }

    func register(keyDownHandler: @escaping @MainActor () -> Void) -> OSStatus {
        self.keyDownHandler = keyDownHandler

        if eventHandlerRef == nil {
            let handlerStatus = reinstallEventHandler()
            guard handlerStatus == noErr else { return handlerStatus }
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: CarbonHotkeyConstants.signature,
            id: CarbonHotkeyConstants.hotkeyID
        )
        let status = RegisterEventHotKey(
            CarbonHotkeyConstants.keyCode,
            CarbonHotkeyConstants.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            eventHotKeyRef = nil
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }

        eventHotKeyRef = hotKeyRef
        return noErr
    }

    func unregister() -> OSStatus {
        guard let eventHotKeyRef else { return noErr }
        let status = UnregisterEventHotKey(eventHotKeyRef)
        self.eventHotKeyRef = nil
        return status
    }

    fileprivate func handle(event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        guard hotKeyID.signature == CarbonHotkeyConstants.signature,
              hotKeyID.id == CarbonHotkeyConstants.hotkeyID
        else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            let handler = keyDownHandler
            Task { @MainActor in
                handler?()
            }
            return noErr
        case UInt32(kEventHotKeyReleased):
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func removeEventHandler() {
        guard let eventHandlerRef else { return }
        RemoveEventHandler(eventHandlerRef)
        self.eventHandlerRef = nil
    }
}

private enum CarbonHotkeyConstants {
    static let signature: OSType = fourCharCode("MgHK")
    static let hotkeyID: UInt32 = 1
    static let keyCode = UInt32(kVK_ANSI_P)
    static let modifiers = UInt32(cmdKey)

    private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf8.reduce(0) { code, byte in
            (code << 8) + FourCharCode(byte)
        }
    }
}

private let magpieHotkeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }
    let registration = Unmanaged<CarbonHotkeyRegistration>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return registration.handle(event: event)
}
