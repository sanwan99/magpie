import SwiftUI

/// Top-bar pill rail: `All · Text · Code · Url · Image · File · Folder`.
/// Tapping a pill sets `viewModel.typeFilter`; tapping `All` clears it.
struct FilterRail: View {
    @Bindable var viewModel: ClipsViewModel

    private struct Option: Identifiable {
        let id: String
        let label: String
        let type: ClipType?
    }

    private let options: [Option] = [
        Option(id: "all", label: "All", type: nil),
        Option(id: "text", label: "Text", type: .text),
        Option(id: "code", label: "Code", type: .code),
        Option(id: "url", label: "Url", type: .url),
        Option(id: "image", label: "Image", type: .image),
        Option(id: "file", label: "File", type: .file),
        Option(id: "folder", label: "Folder", type: .folder),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = viewModel.typeFilter == option.type
                Button {
                    viewModel.typeFilter = option.type
                } label: {
                    Text(option.label)
                }
                .buttonStyle(FilterPillStyle(isSelected: isSelected))
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
            .toggleStyle(PinnedToggleStyle())
        }
    }
}

private struct FilterPillStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? Color.primary.opacity(0.12) : Color.clear)
            )
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct PinnedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(configuration.isOn ? Color.primary.opacity(0.14) : Color.clear)
                )
                .foregroundStyle(configuration.isOn ? Color.primary : Color.secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
