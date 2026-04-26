import Foundation
import Observation

/// MainActor-isolated, @Observable view model for the Snippets drawer + editor.
@MainActor
@Observable
final class SnippetsViewModel {
    private(set) var snippets: [Snippet] = []
    var drawerVisible: Bool = false
    /// Drawer-local search input (separate from the main panel search).
    var searchInput: String = ""

    /// Owned by `PanelController`. Called when the user picks a snippet from
    /// the drawer — pastes the body into the previously frontmost app.
    @ObservationIgnored
    var onPasteRequest: ((Snippet) -> Void)?

    @ObservationIgnored
    private let repository: SnippetRepository

    init(repository: SnippetRepository = SnippetRepository()) {
        self.repository = repository
        refresh()
    }

    func refresh() {
        do {
            snippets = try repository.all()
        } catch {
            NSLog("[snippets] refresh failed: %@", "\(error)")
        }
    }

    /// Filtered list — matches title / shortcut (case-insensitive substring).
    var filteredSnippets: [Snippet] {
        let q = searchInput.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return snippets }
        let lower = q.lowercased()
        return snippets.filter {
            $0.title.lowercased().contains(lower) ||
            $0.shortcut.lowercased().contains(lower)
        }
    }

    func toggleDrawer() {
        drawerVisible.toggle()
    }

    func upsert(_ snippet: Snippet) {
        do {
            try repository.upsert(snippet)
            refresh()
        } catch {
            NSLog("[snippets] upsert failed: %@", "\(error)")
        }
    }

    func delete(id: String) {
        do {
            try repository.delete(id: id)
            refresh()
        } catch {
            NSLog("[snippets] delete failed: %@", "\(error)")
        }
    }

    func find(shortcut: String) -> Snippet? {
        try? repository.find(shortcut: shortcut)
    }

    func requestPaste(_ snippet: Snippet) {
        onPasteRequest?(snippet)
    }
}
