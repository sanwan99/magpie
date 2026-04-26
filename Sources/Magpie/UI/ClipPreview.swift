import SwiftUI

/// Compact 220×220 card used by Stripe layout. Type-aware preview body.
struct ClipPreview: View {
    let clip: ClipDisplayItem
    var isFocused: Bool = false
    /// If set, render a `⌘N` shortcut badge in the header. Stripe layout
    /// passes 1-9 for the first nine cards (matching the ⌘1-⌘9 hotkeys).
    var shortcutNumber: Int? = nil

    private let settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let t = settings.flavor.tokens(for: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            header
            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(12)
        .frame(width: 220, height: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: t.cardCornerRadius)
                .fill(.background.opacity(isFocused ? 0.45 : 0.32))
        )
        // Flavor-specific idle card tint (Splat: pale cream over the purple
        // overlay). Default flavors leave this transparent.
        .background(
            RoundedRectangle(cornerRadius: t.cardCornerRadius)
                .fill(isFocused ? Color.clear : t.cardBgIdle)
        )
        .background(
            RoundedRectangle(cornerRadius: t.cardCornerRadius)
                .fill(isFocused ? t.focusBg : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: t.cardCornerRadius)
                .strokeBorder(
                    isFocused
                        ? t.strokeColor.opacity(t.focusStrokeOpacity)
                        : t.strokeColor.opacity(t.strokeOpacity),
                    lineWidth: isFocused ? t.focusStrokeWidth : t.strokeWidth
                )
        )
        .shadow(
            color: Color.black.opacity(isFocused ? 0.12 : 0.04),
            radius: isFocused ? 6 : 2,
            x: 0,
            y: isFocused ? 2 : 1
        )
        // Optional neon glow on focus (Splat dark uses lime). Layered on top
        // of the default black drop-shadow so cards still feel grounded.
        .shadow(
            color: (isFocused ? t.focusGlowColor : nil)?.opacity(0.55) ?? .clear,
            radius: 14,
            x: 0,
            y: 0
        )
        .offset(y: isFocused ? -2 : 0)
        // No SwiftUI animation modifier here — applying `.animation(value:)` to
        // every card causes all 9+ views to recompute styles on each focus
        // change, which compounds with ScrollViewReader's centering. The
        // visual snap is sharp and fast; we re-add motion polish in v0.3.
    }

    // MARK: - Header (type icon + label + age)

    private var header: some View {
        HStack(spacing: 6) {
            if let n = shortcutNumber {
                Text("⌘\(n)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.72))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            Image(systemName: typeIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(typeLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            Spacer()
            if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Text(timeAgo)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    // MARK: - Body — switch on preview content

    @ViewBuilder
    private var previewBody: some View {
        switch clip.preview {
        case .text(let body):
            Text(body)
                .font(.system(size: 12))
                .lineLimit(7)
                .lineSpacing(1.5)
                .foregroundStyle(.primary)

        case .code(let body, _):
            Text(body)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(8)
                .foregroundStyle(.primary.opacity(0.92))

        case .url(let url, let host):
            VStack(alignment: .leading, spacing: 4) {
                Text(host ?? url.host ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

        case .folder(let path, let items):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text("\(items) item\(items == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
            }

        case .file(let path, let kind, let sizeKB):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                Text("\(kind.uppercased()) · \(sizeKB) KB")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(4)
            }

        case .image(let path, let w, let h, let sizeKB):
            VStack(alignment: .leading, spacing: 4) {
                if let nsimg = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsimg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    HStack {
                        Spacer()
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                Text("\(w)×\(h) · \(sizeKB) KB")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        case .unsupported:
            Text("(unsupported)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    // MARK: - Footer (app attribution)

    private var footer: some View {
        HStack(spacing: 4) {
            if let app = clip.app, !app.isEmpty {
                Text(shortAppLabel(app))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var typeIcon: String {
        switch clip.type {
        case .text:   return "text.alignleft"
        case .code:   return "chevron.left.forwardslash.chevron.right"
        case .url:    return "link"
        case .image:  return "photo"
        case .file:   return "doc"
        case .folder: return "folder"
        }
    }

    private var typeLabel: String {
        clip.type.rawValue.uppercased()
    }

    private var timeAgo: String {
        let secs = Date().timeIntervalSince(clip.createdAt)
        if secs < 60     { return "now" }
        if secs < 3600   { return "\(Int(secs / 60))m" }
        if secs < 86_400 { return "\(Int(secs / 3600))h" }
        return "\(Int(secs / 86_400))d"
    }

    private func shortAppLabel(_ bundleId: String) -> String {
        // com.apple.dt.Xcode → Xcode; com.openai.codex → codex
        return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    }
}
