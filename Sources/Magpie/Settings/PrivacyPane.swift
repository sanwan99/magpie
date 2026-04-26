import SwiftUI

struct PrivacyPane: View {
    @Bindable var store: SettingsStore

    var body: some View {
        let text = SettingsText(language: store.language)

        Form {
            Section(text.authentication) {
                Toggle(text.requireTouchID, isOn: $store.useTouchID)
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
    }
}
