import SwiftUI

/// Right-hand detail pane per spec §04: heading + full type-aware preview + action buttons.
/// Width controlled by parent; this view fills its container.
struct DetailPane: View {
    let clip: ClipDisplayItem?
    let onPaste: () -> Void
    let onTogglePin: () -> Void

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
                .fill(Color.primary.opacity(0.025))
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
                Image(systemName: typeIcon(clip.type))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(clip.type.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timeAgo(clip.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            if let title = clip.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let app = clip.app, !app.isEmpty {
                Text(app)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
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

        case .unsupported:
            Text("Unsupported in v0.1 (image type lands in v0.3).")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Actions

    private func actions(for clip: ClipDisplayItem) -> some View {
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            .buttonStyle(.bordered)
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
}
