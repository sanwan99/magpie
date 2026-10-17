import SwiftUI

@MainActor
struct PrivacyPane: View {
    @Bindable var store: SettingsStore
    @State private var lockGate = BiometricGate(enabled: { true })
    @State private var authenticationTask: Task<Void, Never>?
    @State private var authenticating = false
    @State private var authenticationFailed = false

    var body: some View {
        let text = SettingsText(language: store.language)

        Form {
            Section(text.authentication) {
                Toggle(text.requireTouchID, isOn: Binding(
                    get: { store.useTouchID }, set: { value in changeLock(value) }))
                    .disabled(authenticating)
                if authenticationFailed {
                    Text(store.language.pick(zh: "认证未完成，隐私锁设置未更改。", en: "Authentication did not complete. The lock setting is unchanged."))
                        .foregroundStyle(.red)
                }
                Text(text.touchIDNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(text.filters) {
                Toggle(text.skipSecret, isOn: $store.skipSecretLooking)
                Text(text.skipSecretNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(text.encryption) {
                Toggle(text.encryptLocalStore, isOn: .constant(false))
                    .disabled(true)
                Text(text.encryptionNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(text.analytics) {
                Toggle(text.sendAnalytics, isOn: .constant(false))
                    .disabled(true)
                Text(text.analyticsNote)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            authenticationTask?.cancel()
            lockGate.relock()
            authenticating = false
        }
    }

    private func changeLock(_ enabled: Bool) {
        guard !authenticating, enabled != store.useTouchID else { return }
        authenticating = true
        authenticationFailed = false
        lockGate.relock()
        authenticationTask = Task { @MainActor in
            let allowed = await lockGate.authenticateIfNeeded(reason: store.language.pick(
                zh: "更改 Magpie 隐私锁", en: "Change the Magpie privacy lock"))
            guard !Task.isCancelled else { return }
            if allowed { store.useTouchID = enabled }
            authenticationFailed = !allowed
            authenticating = false
            lockGate.relock()
        }
    }
}
