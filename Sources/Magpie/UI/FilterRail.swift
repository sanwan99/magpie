import SwiftUI

/// Top-bar pill rail: `All · Text · Code · Url · Image · File · Folder`.
/// Tapping a pill sets `viewModel.typeFilter`; tapping `All` clears it.
struct FilterRail: View {
    @Bindable var viewModel: ClipsViewModel
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private struct Option: Identifiable {
        let id: String
        let label: String
        let icon: String
        let type: ClipType?
    }

    private let options: [Option] = [
        Option(id: "all", label: "All", icon: "square.grid.2x2", type: nil),
        Option(id: "text", label: "Text", icon: "textformat", type: .text),
        Option(id: "code", label: "Code", icon: "chevron.left.forwardslash.chevron.right", type: .code),
        Option(id: "url", label: "Link", icon: "link", type: .url),
        Option(id: "image", label: "Image", icon: "photo", type: .image),
        Option(id: "file", label: "File", icon: "doc", type: .file),
        Option(id: "folder", label: "Folder", icon: "folder", type: .folder),
    ]

    var body: some View {
        HStack(spacing: settings.flavor == .splat ? 12 : 4) {
            ForEach(options) { option in
                let isSelected = viewModel.typeFilter == option.type
                Button {
                    viewModel.typeFilter = option.type
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.icon)
                            .font(.system(size: settings.flavor == .splat ? 11 : 10, weight: .semibold))
                        Text(option.label)
                    }
                }
                .buttonStyle(FilterPillStyle(
                    isSelected: isSelected,
                    isSplat: settings.flavor == .splat,
                    colorScheme: colorScheme
                ))
            }

            Spacer(minLength: 0)

            // Pinned-only toggle on the right edge.
            Toggle(isOn: $viewModel.pinnedOnly) {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                    Text("Pinned")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .toggleStyle(PinnedToggleStyle(isSplat: settings.flavor == .splat, colorScheme: colorScheme))
        }
    }
}

private struct FilterPillStyle: ButtonStyle {
    let isSelected: Bool
    let isSplat: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isSplat ? .bold : (isSelected ? .semibold : .medium)))
            .textCase(isSplat ? .uppercase : nil)
            .padding(.horizontal, isSplat ? 12 : 10)
            .padding(.vertical, isSplat ? 6 : 4)
            .background(
                Capsule().fill(backgroundColor)
            )
            .foregroundStyle(foregroundColor)
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .rotationEffect(isSplat && isSelected ? .degrees(-2) : .degrees(0))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }

    private var backgroundColor: Color {
        if !isSplat {
            return isSelected ? selectedSoftFill : Color.clear
        }
        if isSelected {
            return colorScheme == .dark ? splatYellow : splatPurple
        }
        return Color.clear
    }

    private var foregroundColor: Color {
        if !isSplat {
            return isSelected ? Color.primary.opacity(0.86) : Color.secondary
        }
        if isSelected {
            return colorScheme == .dark ? splatInk : splatCream
        }
        return colorScheme == .dark ? splatCream.opacity(0.82) : splatInk.opacity(0.72)
    }

    private var borderColor: Color {
        if isSplat && isSelected {
            return splatInk
        }
        return isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear
    }

    private var borderWidth: CGFloat {
        if isSplat && isSelected {
            return 1.5
        }
        return isSelected ? 0.7 : 0
    }

    private var selectedSoftFill: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.075)
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color { Color(red: 1.00, green: 0.97, blue: 0.85) }
}

private struct PinnedToggleStyle: ToggleStyle {
    let isSplat: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(size: 11, weight: isSplat ? .bold : .medium))
                .padding(.horizontal, isSplat ? 12 : 10)
                .padding(.vertical, isSplat ? 6 : 4)
                .background(
                    Capsule().fill(backgroundColor(configuration.isOn))
                )
                .foregroundStyle(foregroundColor(configuration.isOn))
                .overlay(
                    Capsule()
                        .strokeBorder(borderColor(configuration.isOn), lineWidth: borderWidth(configuration.isOn))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func backgroundColor(_ isOn: Bool) -> Color {
        if !isSplat {
            return isOn ? selectedSoftFill : Color.clear
        }
        return isOn ? (colorScheme == .dark ? splatYellow : splatPurple) : Color.clear
    }

    private func foregroundColor(_ isOn: Bool) -> Color {
        if !isSplat {
            return isOn ? Color.primary.opacity(0.86) : Color.secondary
        }
        if isOn {
            return colorScheme == .dark ? splatInk : splatCream
        }
        return colorScheme == .dark ? splatCream.opacity(0.82) : splatInk.opacity(0.72)
    }

    private func borderColor(_ isOn: Bool) -> Color {
        if isSplat && isOn {
            return splatInk
        }
        return isOn ? Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear
    }

    private func borderWidth(_ isOn: Bool) -> CGFloat {
        if isSplat && isOn {
            return 1.5
        }
        return isOn ? 0.7 : 0
    }

    private var selectedSoftFill: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.075)
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color { Color(red: 1.00, green: 0.97, blue: 0.85) }
}
