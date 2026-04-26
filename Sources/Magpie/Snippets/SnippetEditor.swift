import SwiftUI

/// Modal-style editor for a single snippet. Shown in its own NSWindow via
/// `SnippetEditorWindowController`. Save / Delete / Cancel.
struct SnippetEditor: View {
    @Binding var snippet: Snippet
    let isNew: Bool
    let onSave: (Snippet) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Snippet" : "Edit Snippet")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcut")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(";sig", text: $snippet.shortcut)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                Text("Trigger string. By convention starts with `;` (e.g. `;sig`, `;meet`).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Email signature", text: $snippet.title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Body")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $snippet.body)
                    .font(.system(size: 12))
                    .frame(minHeight: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            }

            if let validationError {
                Text(validationError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack {
                if !isNew {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: validateAndSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460, height: 440)
    }

    private func validateAndSave() {
        let trimmedShortcut = snippet.shortcut.trimmingCharacters(in: .whitespaces)
        let trimmedBody = snippet.body
        if trimmedShortcut.isEmpty {
            validationError = "Shortcut cannot be empty."
            return
        }
        if trimmedBody.isEmpty {
            validationError = "Body cannot be empty."
            return
        }
        validationError = nil
        var s = snippet
        s.shortcut = trimmedShortcut
        s.title = s.title.isEmpty ? trimmedShortcut : s.title
        onSave(s)
    }
}
