import SwiftUI

struct HistoryPane: View {
    @Bindable var store: SettingsStore
    @State private var showClearAlert = false
    @State private var newAppId: String = ""

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Keep history for", selection: $store.keepHistoryDays) {
                    Text("Forever").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.menu)

                HStack {
                    Text("Max items")
                    Spacer()
                    TextField("0 = unlimited", value: $store.maxItems, format: .number)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Pinned clips are never auto-deleted, regardless of these limits.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Ignored apps") {
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

                Text("Bundle identifiers (e.g. `com.agilebits.onepassword`, `com.lastpass.macos`). Clipboard activity from these apps will not be ingested.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Section("Danger zone") {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear all clips")
                    }
                }
                .alert("Clear all clips?", isPresented: $showClearAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear", role: .destructive) {
                        HistoryReaper().clearAll()
                    }
                } message: {
                    Text("This permanently deletes all clips (pinned and unpinned) and the on-disk image cache. Cannot be undone.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
