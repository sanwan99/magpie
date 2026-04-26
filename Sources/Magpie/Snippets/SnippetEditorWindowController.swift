import AppKit
import SwiftUI

/// Manages a single Snippet editor window. Reused across edit sessions —
/// opening editor while one is already up just brings it to the front.
@MainActor
final class SnippetEditorWindowController {
    static let shared = SnippetEditorWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<EditorHost>?

    private init() {}

    /// Open the editor for an existing or brand-new snippet.
    func open(
        snippet initial: Snippet,
        isNew: Bool,
        onSave: @escaping (Snippet) -> Void,
        onDelete: @escaping () -> Void
    ) {
        let host = EditorHost(
            initial: initial,
            isNew: isNew,
            onSave: { [weak self] s in
                onSave(s)
                self?.close()
            },
            onDelete: { [weak self] in
                onDelete()
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )

        if let existing = window, existing.isVisible {
            // Replace content for the new snippet.
            hostingController?.rootView = host
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: host)
        let win = NSWindow(contentViewController: controller)
        win.title = isNew ? "New Snippet" : "Edit Snippet"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.hostingController = controller
    }

    func close() {
        window?.orderOut(nil)
    }
}

/// SwiftUI bridge that owns a mutable copy of the snippet during editing.
private struct EditorHost: View {
    @State var draft: Snippet
    let isNew: Bool
    let onSave: (Snippet) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        initial: Snippet,
        isNew: Bool,
        onSave: @escaping (Snippet) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: initial)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        SnippetEditor(
            snippet: $draft,
            isNew: isNew,
            onSave: onSave,
            onDelete: onDelete,
            onCancel: onCancel
        )
    }
}
