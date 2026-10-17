import SwiftUI

struct HistoryPane: View {
    @Bindable var store: SettingsStore
    @State private var showClearAlert = false
    @State private var clearing = false
    @State private var clearFailed = false
    @State private var newAppId: String = ""

    var body: some View {
        let text = SettingsText(language: store.language)

        Form {
            Section(text.retention) {
                Picker(text.keepHistoryFor, selection: $store.keepHistoryDays) {
                    Text(text.forever).tag(0)
                    Text(text.days(7)).tag(7)
                    Text(text.days(30)).tag(30)
                    Text(text.days(90)).tag(90)
                }
                .pickerStyle(.menu)

                HStack {
                    Text(text.maxItems)
                    Spacer()
                    TextField(text.unlimitedPlaceholder, value: $store.maxItems, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text(text.pinnedNeverDeleted)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(text.ignoredApps) {
                ForEach(store.ignoredApps, id: \.self) { app in
                    HStack {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.tertiary)
                        Text(app)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button {
                            store.ignoredApps.removeAll { $0 == app }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("com.example.app", text: $newAppId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button {
                        let id = newAppId.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty, !store.ignoredApps.contains(id) else { return }
                        store.ignoredApps.append(id)
                        newAppId = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newAppId.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Text(text.ignoredAppsDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section(text.dangerZone) {
                if clearFailed {
                    Text(store.language.pick(zh: "清理未完全完成，请检查磁盘权限后重试。", en: "Cleanup was incomplete. Check disk permissions and retry."))
                        .foregroundStyle(.red)
                }
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(text.clearAllClips)
                    }
                }
                .disabled(clearing)
                .alert(text.clearAllClipsQuestion, isPresented: $showClearAlert) {
                    Button(text.cancel, role: .cancel) {}
                    Button(text.clear, role: .destructive) {
                        clearing = true
                        Task { @MainActor in
                            let success = await HistoryReaper().clearAllInBackground()
                            clearing = false
                            clearFailed = !success
                            NotificationCenter.default.post(name: .magpieHistoryCleared, object: nil)
                        }
                    }
                } message: {
                    Text(text.clearAllClipsMessage)
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension Notification.Name {
    static let magpieHistoryCleared = Notification.Name("magpie.historyCleared")
}
