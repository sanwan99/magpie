import LocalAuthentication
import AppKit

/// Touch ID / passcode gate for the panel.
///
/// Strategy per spec hint: prompt only on the first panel show after launch
/// (not every time, not on launch — that would block the menu bar app).
/// Once unlocked, stays unlocked for the rest of the session.
@MainActor
final class BiometricGate {
    private(set) var isUnlocked: Bool = false

    /// Returns true if biometric auth succeeded (or was not needed).
    /// Call before showing the panel; if false, abort the show.
    func authenticateIfNeeded(reason: String = "Unlock Magpie") async -> Bool {
        let store = SettingsStore.shared
        if !store.useTouchID { return true }
        if isUnlocked { return true }

        let context = LAContext()
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            NSLog("[biometric] policy unavailable: %@", error?.localizedDescription ?? "?")
            // Hardware doesn't support biometrics — pass through rather than locking the user out.
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            isUnlocked = success
            return success
        } catch {
            NSLog("[biometric] auth failed: %@", "\(error)")
            return false
        }
    }

    /// Manually re-lock (e.g. on screen unlock, system sleep — wired in v1.0).
    func relock() {
        isUnlocked = false
    }
}
