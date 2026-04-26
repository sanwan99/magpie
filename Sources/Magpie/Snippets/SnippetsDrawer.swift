import SwiftUI

/// Top-down drawer over the panel content. Shows when
/// `viewModel.drawerVisible == true`. Lists snippets, allows editing /
/// deleting / creating, and pastes selected snippet via callback.
struct SnippetsDrawer: View {
    @Bindable var viewModel: SnippetsViewModel
    let onCreate: () -> Void
    let onEdit: (Snippet) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            list
        }
        .frame(maxWidth: .infinity)
        .background(.background.opacity(0.95))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text("Snippets")
                .font(.system(size: 13, weight: .bold))
            Text("\(viewModel.snippets.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            TextField("Search snippets…", text: $viewModel.searchInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                )

            Spacer(minLength: 0)

            Button(action: onCreate) {
                Label("New", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if viewModel.filteredSnippets.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredSnippets) { snippet in
                        SnippetRow(
                            snippet: snippet,
                            onPaste: { viewModel.requestPaste(snippet) },
                            onEdit:  { onEdit(snippet) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 240)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(viewModel.snippets.isEmpty ? "No snippets yet" : "No matches")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if viewModel.snippets.isEmpty {
                Text("Click + New to create your first snippet (e.g. ;sig → signature).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(hovering ? 0.10 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let onPaste: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(snippet.shortcut)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08))
                )
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.title.isEmpty ? snippet.shortcut : snippet.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(snippet.body)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                IconButton(systemName: "pencil", help: "Edit snippet", action: onEdit)
                IconButton(systemName: "arrow.uturn.up", help: "Paste snippet", action: onPaste)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPaste() }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.0001))
        )
    }
}
