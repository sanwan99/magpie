import SwiftUI

struct GeneralPane: View {
    @Bindable var store: SettingsStore

    var body: some View {
        let text = SettingsText(language: store.language)

        Form {
            Section(text.appearance) {
                Picker(text.languageLabel, selection: $store.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Picker(text.theme, selection: $store.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { t in
                        Text(t.displayName(language: store.language)).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(text.vibrancy)
                    Slider(value: $store.vibrancy, in: 0...60)
                    Text("\(Int(store.vibrancy))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(text.flavor)
                        .padding(.top, 6)
                    Spacer()
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(56), spacing: 8), count: 5),
                        spacing: 8
                    ) {
                        ForEach(Flavor.allCases, id: \.self) { flavor in
                            FlavorSwatch(
                                flavor: flavor,
                                isSelected: store.flavor == flavor,
                                language: store.language
                            ) {
                                store.flavor = flavor
                            }
                        }
                    }
                }
            }

            Section(text.behavior) {
                Toggle(text.launchAtLogin, isOn: $store.launchAtLogin)
                Toggle(text.showRecentFirst, isOn: $store.showRecentFirst)
                Toggle(text.detectColorsAndLinks, isOn: $store.detectColorsAndLinks)
                Toggle(text.stripTracking, isOn: $store.stripTrackingFromURLs)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(text.autoExpand, isOn: $store.autoExpandSnippets)
                    Text(text.autoExpandNote)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 22)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

private struct FlavorSwatch: View {
    let flavor: Flavor
    let isSelected: Bool
    let language: AppLanguage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // Solid base (accent)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(flavor.tokens.accent)
                    // Highlight wedge (focusBg) — shows focus color preview
                    RoundedRectangle(cornerRadius: 6)
                        .fill(flavor.tokens.focusBgColor.opacity(flavor.tokens.focusBgIntensity))
                        .frame(width: 14)
                        .offset(x: 8)
                }
                .frame(width: 36, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            flavor.tokens.strokeColor.opacity(
                                isSelected ? 0.95 : flavor.tokens.strokeOpacity
                            ),
                            lineWidth: isSelected ? 1.5 : flavor.tokens.strokeWidth
                        )
                )

                Text(flavor.displayName(language: language))
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
