import LocalAuthentication
import AppKit

@MainActor
protocol OwnerAuthenticating: AnyObject {
    func authenticate(reason: String) async -> Bool
    func cancel()
}

@MainActor
final class SystemOwnerAuthenticator: OwnerAuthenticating {
    private var context: LAContext?

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        self.context = context
        defer { context.invalidate(); self.context = nil }
        var error: NSError?
        // macOS owns the fallback UI; Magpie never reads the account password.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            NSLog("[authentication] policy unavailable")
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            DiagnosticLog.failure("authentication", error: error)
            return false
        }
    }

    func cancel() { context?.invalidate() }
}

/// Unlock lasts only while the panel is open. Hiding, sleep, screen lock,
/// session changes and process restart require fresh system authentication.
@MainActor
final class BiometricGate {
    private(set) var isUnlocked = false
    private let authenticator: OwnerAuthenticating
    private let enabled: () -> Bool
    private var generation = 0
    private var authenticating = false

    init(authenticator: OwnerAuthenticating? = nil,
         enabled: @escaping () -> Bool = { SettingsStore.shared.useTouchID }) {
        self.authenticator = authenticator ?? SystemOwnerAuthenticator()
        self.enabled = enabled
    }

    func authenticateIfNeeded(reason: String = "Unlock Magpie") async -> Bool {
        guard enabled() else { return true }
        if isUnlocked { return true }
        // Repeated hotkeys must not open concurrent authentication prompts.
        guard !authenticating else { return false }
        authenticating = true
        let requestGeneration = generation
        defer { authenticating = false }
        let success = await authenticator.authenticate(reason: reason)
        guard success, !Task.isCancelled, requestGeneration == generation else { return false }
        isUnlocked = true
        return true
    }

    func relock() {
        generation += 1
        isUnlocked = false
        authenticator.cancel()
    }
}
