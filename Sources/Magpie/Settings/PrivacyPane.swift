import SwiftUI

struct PrivacyPane: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Form {
            Section("Authentication") {
                Toggle("Require Touch ID to unlock", isOn: $store.useTouchID)
                Text("When enabled, Magpie prompts for Touch ID the first time you summon the panel after launching the app. Once unlocked, stays unlocked for the session.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Filters") {
                Toggle("Skip secret-looking content (API keys, tokens, OTP)", isOn: $store.skipSecretLooking)
                Text("Detects strings shaped like `api_key=…`, `Bearer …`, GitHub tokens, AWS access keys, JWTs, and 6-digit OTP codes — they will not be stored.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Encryption") {
                Toggle("Encrypt local store", isOn: .constant(false))
                    .disabled(true)
                Text("SQLCipher integration coming in v1.0. Until then, the database lives in `~/Library/Application Support/Magpie/clips.sqlite` with macOS user-only file permissions.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Analytics") {
                Toggle("Send analytics", isOn: .constant(false))
                    .disabled(true)
                Text("Magpie is local-only by design. This will never be enabled.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
    }
}
