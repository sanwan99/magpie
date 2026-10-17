import AppKit
import Carbon

/// Owns Magpie's global hotkeys.
/// Esc is handled inside the panel as a local key event, not a global hotkey.
@MainActor
final class HotkeyCenter {
    static weak var current: HotkeyCenter?
    private let defaults: UserDefaults
    private var bindings: [GlobalHotkeyAction: HotkeyBinding] = [:]
    private let driver: HotkeyRegistrationDriver
    private let actions: [GlobalHotkeyAction]
    private let deferredRepairDelay: TimeInterval?
    private var pendingDeferredRepair: DispatchWorkItem?
    private var diagnostics = HotkeyDiagnostics()

    var onTogglePanel: (() -> Void)?
    var onCaptureScreenshot: (() -> Void)?

    init(driver: HotkeyRegistrationDriver = CarbonHotkeyRegistration(),
         actions: [GlobalHotkeyAction] = GlobalHotkeyAction.allCases,
         deferredRepairDelay: TimeInterval? = 0.75,
         defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in actions {
            if let data = defaults.data(forKey: "magpie.hotkey.\(action.rawValue)"),
               let binding = try? JSONDecoder().decode(HotkeyBinding.self, from: data), binding.isValid {
                bindings[action] = binding
            }
        }
        self.driver = driver
        self.actions = actions
        self.deferredRepairDelay = deferredRepairDelay
        repair(reason: "launch")
        Self.current = self
    }

    deinit {
        pendingDeferredRepair?.cancel()
    }

    var diagnosticsSnapshot: HotkeyDiagnostics {
        diagnostics
    }

    func binding(for action: GlobalHotkeyAction) -> HotkeyBinding {
        bindings[action] ?? HotkeyBinding(keyCode: action.keyCode, modifiers: action.modifiers)
    }

    /// Validate both application duplicates and Carbon-reported conflicts.
    /// Failed registration rolls back and leaves the persisted choice unchanged.
    func setBinding(_ binding: HotkeyBinding, for action: GlobalHotkeyAction) -> Bool {
        guard binding.isValid,
              !actions.contains(where: { $0 != action && self.binding(for: $0) == binding }) else { return false }
        let previous = bindings
        pendingDeferredRepair?.cancel()
        bindings[action] = binding
        repair(reason: "configuration")
        guard diagnostics.registered else {
            bindings = previous
            repair(reason: "configurationRollback")
            return false
        }
        defaults.set(try? JSONEncoder().encode(binding), forKey: "magpie.hotkey.\(action.rawValue)")
        NotificationCenter.default.post(name: .magpieHotkeysChanged, object: nil)
        return true
    }

    /// 系统生命周期事件后的热键修复入口。
    ///
    /// 这里做的是一次性 Carbon 链路重建：释放旧 `EventHotKeyRef`、重装事件
    /// handler、重新注册全部全局热键。它替代旧的 30 秒心跳，不做周期性轮询。
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
        NSLog("[hotkey] repair begin reason=%@ registered=%d/%d repairs=%d",
              reason, driver.registeredActions.count, actions.count, diagnostics.repairAttempts)

        if !driver.registeredActions.isEmpty {
            unregister(reason: "\(reason):replaceStaleRegistration")
        }

        diagnostics.eventHandlerRepairAttempts += 1
        let handlerStatus = driver.reinstallEventHandler()
        guard record(status: handlerStatus, operation: "reinstallEventHandler", reason: reason) else {
            refreshRegisteredState()
            return
        }

        for action in actions {
            diagnostics.registerAttempts += 1
            let registerStatus = driver.register(action: action, binding: binding(for: action)) { [weak self] action in
                self?.handleKeyDown(action)
            }
            if record(status: registerStatus, operation: "register", reason: reason, action: action) {
                diagnostics.registerSuccesses += 1
                diagnostics.registrationFailures.removeValue(forKey: action)
                NSLog("[hotkey] register ok action=%@ reason=%@ attempts=%d",
                      action.label, reason, diagnostics.registerAttempts)
            } else {
                diagnostics.registerFailures += 1
                diagnostics.registrationFailures[action] = registerStatus
            }
        }
        refreshRegisteredState()
    }

    private func unregister(reason: String) {
        guard !driver.registeredActions.isEmpty else {
            refreshRegisteredState()
            return
        }

        diagnostics.unregisterAttempts += 1
        let statuses = driver.unregisterAll()
        for (action, status) in statuses {
            _ = record(status: status, operation: "unregister", reason: reason, action: action)
        }
        refreshRegisteredState()
    }

    private func handleKeyDown(_ action: GlobalHotkeyAction) {
        diagnostics.keyDownEvents += 1
        diagnostics.lastReason = "keyDown"
        diagnostics.lastAction = action
        NSLog("[hotkey] keyDown action=%@ events=%d registered=%d/%d",
              action.label,
              diagnostics.keyDownEvents,
              driver.registeredActions.count,
              actions.count)
        switch action {
        case .togglePanel:
            onTogglePanel?()
        case .captureScreenshot:
            onCaptureScreenshot?()
        }
    }

    @discardableResult
    private func record(
        status: OSStatus,
        operation: String,
        reason: String,
        action: GlobalHotkeyAction? = nil
    ) -> Bool {
        diagnostics.lastOSStatus = status
        guard status == noErr else {
            let actionText = action.map { " action=\($0.label)" } ?? ""
            let message = "\(operation) failed\(actionText) reason=\(reason) status=\(status)"
            diagnostics.lastError = message
            NSLog("[hotkey] %@", message)
            return false
        }
        diagnostics.lastError = nil
        return true
    }

    private func refreshRegisteredState() {
        diagnostics.registeredActions = driver.registeredActions
        diagnostics.registered = Set(actions).isSubset(of: driver.registeredActions)
    }
}

enum GlobalHotkeyAction: UInt32, CaseIterable, Hashable, Sendable {
    case togglePanel = 1
    case captureScreenshot = 2

    var keyCode: UInt32 {
        switch self {
        case .togglePanel:
            return UInt32(kVK_ANSI_P)
        case .captureScreenshot:
            return UInt32(kVK_ANSI_J)
        }
    }

    var modifiers: UInt32 {
        UInt32(cmdKey)
    }

    var label: String {
        switch self {
        case .togglePanel:
            return "⌘P"
        case .captureScreenshot:
            return "⌘J"
        }
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
    var registeredActions: Set<GlobalHotkeyAction> = []
    var registrationFailures: [GlobalHotkeyAction: OSStatus] = [:]
    var lastAction: GlobalHotkeyAction?
    var lastReason: String?
    var lastOSStatus: OSStatus = noErr
    var lastError: String?
}

protocol HotkeyRegistrationDriver: AnyObject {
    var registeredActions: Set<GlobalHotkeyAction> { get }

    func reinstallEventHandler() -> OSStatus
    func register(
        action: GlobalHotkeyAction,
        binding: HotkeyBinding,
        keyDownHandler: @escaping @MainActor (GlobalHotkeyAction) -> Void
    ) -> OSStatus
    func unregisterAll() -> [GlobalHotkeyAction: OSStatus]
}

private final class CarbonHotkeyRegistration: HotkeyRegistrationDriver {
    private var eventHandlerRef: EventHandlerRef?
    private var eventHotKeyRefs: [GlobalHotkeyAction: EventHotKeyRef] = [:]
    private var keyDownHandler: (@MainActor (GlobalHotkeyAction) -> Void)?

    var registeredActions: Set<GlobalHotkeyAction> {
        Set(eventHotKeyRefs.keys)
    }

    deinit {
        _ = unregisterAll()
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

    func register(
        action: GlobalHotkeyAction,
        binding: HotkeyBinding,
        keyDownHandler: @escaping @MainActor (GlobalHotkeyAction) -> Void
    ) -> OSStatus {
        self.keyDownHandler = keyDownHandler

        if eventHandlerRef == nil {
            let handlerStatus = reinstallEventHandler()
            guard handlerStatus == noErr else { return handlerStatus }
        }

        if let existingRef = eventHotKeyRefs.removeValue(forKey: action) {
            _ = UnregisterEventHotKey(existingRef)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: CarbonHotkeyConstants.signature,
            id: action.rawValue
        )
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }

        eventHotKeyRefs[action] = hotKeyRef
        return noErr
    }

    func unregisterAll() -> [GlobalHotkeyAction: OSStatus] {
        let refs = eventHotKeyRefs
        eventHotKeyRefs.removeAll()
        return refs.reduce(into: [:]) { statuses, entry in
            statuses[entry.key] = UnregisterEventHotKey(entry.value)
        }
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
              let action = GlobalHotkeyAction(rawValue: hotKeyID.id),
              eventHotKeyRefs[action] != nil
        else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            let handler = keyDownHandler
            Task { @MainActor in
                handler?(action)
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

struct HotkeyBinding: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    static let letters: [UInt32: String] = [
        0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",
        12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",
        23:"5",25:"9",26:"7",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"
    ]
    var isValid: Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return Self.letters[keyCode] != nil && modifiers & ~allowed == 0
            && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }
    var displayName: String {
        [(controlKey,"⌃"), (optionKey,"⌥"), (shiftKey,"⇧"), (cmdKey,"⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map { $0.1 }.joined()
            + (Self.letters[keyCode] ?? "?")
    }
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

extension Notification.Name {
    static let magpieHotkeysChanged = Notification.Name("magpie.hotkeysChanged")
}
