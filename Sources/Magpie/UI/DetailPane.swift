import SwiftUI

/// Right-hand detail pane per spec §04: heading + full type-aware preview + action buttons.
/// Width controlled by parent; this view fills its container.
struct DetailPane: View {
    let clip: ClipDisplayItem?
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    /// 点击 header 右上"扩大"按钮时调用 — 由 PanelController 转发到
    /// ExpandedPreviewWindowController.shared.show(clip:)。
    var onExpand: (() -> Void)? = nil
    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let clip {
                content(for: clip)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(Color.clear)
        )
    }

    // MARK: - Filled content

    @ViewBuilder
    private func content(for clip: ClipDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(for: clip)
            Divider().opacity(0.4)
            ScrollView(showsIndicators: false) {
                fullPreview(for: clip)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.vertical, 4)
            }
            actions(for: clip)
        }
        .padding(16)
    }

    // MARK: - Header

    private func header(for clip: ClipDisplayItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                typeBadge(for: clip.type)
                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(settings.flavor == .splat ? splatYellow : Color.secondary)
                }
                Spacer()
                Text(timeAgo(clip.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(settings.flavor == .splat ? splatCream.opacity(0.65) : Color.secondary.opacity(0.65))
                    .monospacedDigit()
                if onExpand != nil {
                    expandButton
                }
            }

            if let title = clip.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: settings.flavor == .splat ? 21 : 16, weight: .semibold))
                    .foregroundStyle(settings.flavor == .splat ? splatCream : Color.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let app = clip.app, !app.isEmpty {
                Text(app)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(settings.flavor == .splat ? splatCream.opacity(0.48) : Color.secondary.opacity(0.55))
            }
        }
    }

    /// 扩大化按钮 — 把当前 clip 在独立窗口里大尺寸渲染。
    /// 视觉跟随 flavor：splat 用墨黑底 + 奶白图标；普通主题低调灰色。
    private var expandButton: some View {
        Button {
            onExpand?()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(settings.flavor == .splat ? splatCream : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(settings.flavor == .splat
                              ? splatInk.opacity(0.85)
                              : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help("放大查看（⌘O）")
    }

    private func typeBadge(for type: ClipType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: typeIcon(type))
                .font(.system(size: 11, weight: .medium))
            Text(type.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(settings.flavor == .splat ? splatCream : Color.secondary)
        .padding(.horizontal, settings.flavor == .splat ? 8 : 0)
        .padding(.vertical, settings.flavor == .splat ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(settings.flavor == .splat ? splatInk : Color.clear)
        )
    }

    // MARK: - Full preview

    @ViewBuilder
    private func fullPreview(for clip: ClipDisplayItem) -> some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 12))
                .textSelection(.enabled)

        case .code(let body, let lang):
            VStack(alignment: .leading, spacing: 6) {
                if let lang, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                Text(body)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 6) {
                Text(host ?? url.host ?? "")
                    .font(.system(size: 14, weight: .semibold))
                Text(url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case .folder(let path, let items):
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(items) item\(items == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case .file(let path, let kind, let sizeKB):
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(kind.uppercased()) · \(sizeKB) KB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 8) {
                // DetailPane 宽度 ~360-440pt，800 缩略图够清；想看原图按 ⌘O 走
                // ExpandedPreview 加载全分辨率。
                if let nsimg = ImageThumbnail.load(path: path, maxPixelSize: 800) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("Image file missing")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                HStack(spacing: 12) {
                    Label("\(w)×\(h)", systemImage: "ruler")
                        .font(.system(size: 11, design: .monospaced))
                    Label("\(sizeKB) KB", systemImage: "internaldrive")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

        case .unsupported:
            Text("Unsupported clip type")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Actions

    private func actions(for clip: ClipDisplayItem) -> some View {
        Group {
            if settings.flavor == .splat {
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: onPaste) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.up")
                            Text("PASTE")
                            Spacer()
                            Text("↵")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                    .buttonStyle(SplatActionButtonStyle(kind: .primary, colorScheme: colorScheme))
                    .keyboardShortcut(.return, modifiers: [])

                    Button(action: onTogglePin) {
                        HStack(spacing: 8) {
                            Image(systemName: clip.pinned ? "pin.slash" : "pin")
                            Text(clip.pinned ? "UNPIN" : "PIN")
                            Spacer()
                            Text("⌘D")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                    .buttonStyle(SplatActionButtonStyle(kind: .secondary, colorScheme: colorScheme))
                }
            } else {
                VStack(spacing: 6) {
                    Button(action: onPaste) {
                        HStack {
                            Image(systemName: "arrow.uturn.up")
                            Text("Paste")
                            Spacer()
                            Text("↵")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RegularActionButtonStyle(isPrimary: true, colorScheme: colorScheme))
                    .keyboardShortcut(.return, modifiers: [])

                    Button(action: onTogglePin) {
                        HStack {
                            Image(systemName: clip.pinned ? "pin.slash" : "pin")
                            Text(clip.pinned ? "Unpin" : "Pin")
                            Spacer()
                            Text("⌘D")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RegularActionButtonStyle(isPrimary: false, colorScheme: colorScheme))
                }
            }
        }
    }

    // MARK: - Empty state

    private var empty: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Select a clip")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func typeIcon(_ type: ClipType) -> String {
        switch type {
        case .text:   return "text.alignleft"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        case .url:    return "link"
        case .image:  return "photo"
        case .file:   return "doc"
        case .folder: return "folder"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Date().timeIntervalSince(date)
        if secs < 60     { return "just now" }
        if secs < 3600   { return "\(Int(secs / 60))m ago" }
        if secs < 86_400 { return "\(Int(secs / 3600))h ago" }
        return "\(Int(secs / 86_400))d ago"
    }

    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}

private enum SplatActionKind {
    case primary
    case secondary
}

private struct SplatActionButtonStyle: ButtonStyle {
    let kind: SplatActionKind
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(kind == .primary ? splatCream : splatYellow)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: kind == .primary ? 44 : 36)
            .background(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .fill(kind == .primary ? splatPurple : Color(red: 0.13, green: 0.04, blue: 0.23).opacity(0.96))
            )
            .background(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .fill(kind == .primary ? splatInk.opacity(0.85) : Color.clear)
                    .offset(x: kind == .primary ? 4 : 0, y: kind == .primary ? 4 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: kind == .primary ? 18 : 9)
                    .strokeBorder(kind == .primary ? splatInk : splatYellow.opacity(0.75), lineWidth: kind == .primary ? 2 : 1.5)
            )
            .rotationEffect(kind == .primary ? .degrees(-2) : .degrees(0))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var splatPurple: Color { Color(red: 0.48, green: 0.17, blue: 1.00) }
    private var splatYellow: Color { Color(red: 1.00, green: 0.91, blue: 0.00) }
    private var splatInk: Color { Color(red: 0.05, green: 0.05, blue: 0.06) }
    private var splatCream: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.97, blue: 0.85)
            : Color(red: 0.05, green: 0.05, blue: 0.06)
    }
}

private struct RegularActionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundStyle(isPrimary ? primaryForeground : secondaryForeground)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isPrimary ? primaryBackground : secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPrimary ? Color.clear : regularBorder, lineWidth: isPrimary ? 0 : 0.5)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }

    private var primaryBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.95, blue: 0.96)
            : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    private var primaryForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color.white
    }

    private var secondaryBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.60)
    }

    private var secondaryForeground: Color {
        Color.secondary
    }

    private var regularBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.06)
    }
}
