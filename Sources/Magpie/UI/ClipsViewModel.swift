import Foundation
import Observation
import SwiftUI

/// View-side representation of a clip — one row in the panel layouts.
struct ClipDisplayItem: Identifiable, Equatable {
    let id: String
    let type: ClipType
    let app: String?
    let createdAt: Date
    let pinned: Bool
    let title: String?
    let preview: PreviewContent

    enum PreviewContent: Equatable {
        case text(String)
        case code(body: String, lang: String?)
        case url(URL, host: String?)
        case folder(path: String, items: Int)
        case file(path: String, kind: String, sizeKB: Int)
        case image(path: String, width: Int, height: Int, sizeKB: Int)
        case unsupported
    }
}

extension ClipDisplayItem {
    init?(record: ClipRecord) {
        guard let type = ClipType(rawValue: record.type) else { return nil }
        let decoder = JSONDecoder()
        let preview: PreviewContent
        switch type {
        case .text:
            guard let p = try? decoder.decode(TextPayload.self, from: record.payload) else { return nil }
            preview = .text(p.body)
        case .code:
            guard let p = try? decoder.decode(CodePayload.self, from: record.payload) else { return nil }
            preview = .code(body: p.body, lang: p.lang)
        case .url:
            guard let p = try? decoder.decode(URLPayload.self, from: record.payload),
                  let url = URL(string: p.url) else { return nil }
            preview = .url(url, host: p.host)
        case .folder:
            guard let p = try? decoder.decode(FolderPayload.self, from: record.payload) else { return nil }
            preview = .folder(path: p.path, items: p.items)
        case .file:
            guard let p = try? decoder.decode(FilePayload.self, from: record.payload) else { return nil }
            preview = .file(path: p.path, kind: p.kind, sizeKB: p.sizeKB)
        case .image:
            guard let p = try? decoder.decode(ImagePayload.self, from: record.payload) else { return nil }
            preview = .image(path: p.path, width: p.width, height: p.height, sizeKB: p.sizeKB)
        }
        self.id = record.id
        self.type = type
        self.app = record.app
        self.createdAt = record.createdAtDate
        self.pinned = record.pinned
        self.title = record.title
        self.preview = preview
    }
}

/// MainActor-isolated `@Observable` view model.
///
/// Uses the macOS 14+ Observation framework instead of `ObservableObject` +
/// `@Published`. The key practical difference: SwiftUI tracks property access
/// per-keypath, so changing `focusedIndex` no longer invalidates the SearchField
/// or FilterRail — only views that actually read `focusedIndex` re-diff.
@MainActor
@Observable
final class ClipsViewModel {
    // MARK: - Filtered results (read-only externally)

    private(set) var clips: [ClipDisplayItem] = []
    private(set) var totalClipCount: Int = 0

    // MARK: - Interactive state

    /// Free-text search. Each keystroke schedules a debounced apply (default 100 ms)
    /// to avoid hammering SQLite + re-rendering on every character.
    var searchInput: String = "" {
        didSet { scheduleDebouncedApply() }
    }
    /// Type pill selection. Applied immediately (single click, no debounce needed).
    var typeFilter: ClipType? = nil {
        didSet { refresh() }
    }
    /// Pinned-only toggle.
    var pinnedOnly: Bool = false {
        didSet { refresh() }
    }

    // MARK: - Focus

    var focusedIndex: Int = 0

    /// Queue Mode — when ON, paste auto-advances focus to the next clip,
    /// matching prototype spec §05. Per-session (does not persist).
    var queueMode: Bool = false

    func toggleQueueMode() {
        queueMode.toggle()
    }

    /// Advance focus toward newer clips by one. Called after paste in Queue Mode.
    func advanceFocusForQueue() {
        guard !clips.isEmpty else { return }
        focusedIndex = min(clips.count - 1, focusedIndex + 1)
    }

    // MARK: - Layout preferences (persisted)

    /// The currently active panel layout. ⌘\ cycles. Persisted to UserDefaults.
    var activeLayout: ActiveLayout = .stripe {
        didSet {
            UserDefaults.standard.set(activeLayout.rawValue, forKey: Self.activeLayoutKey)
        }
    }

    /// Whether the right-side detail pane is shown. Space toggles. Persisted.
    /// Default OFF so the layout has full width for cards (matches v0.1 feel).
    /// Users opt in via Space when they want a fuller view of a clip.
    var detailPaneVisible: Bool = false {
        didSet {
            UserDefaults.standard.set(detailPaneVisible, forKey: Self.detailPaneKey)
        }
    }

    /// Owned by `PanelController`. Called when the UI requests a paste.
    @ObservationIgnored
    var onPasteRequest: (() -> Void)?

    @ObservationIgnored
    private var debounceTask: Task<Void, Never>?
    @ObservationIgnored
    private let debounceInterval: Duration = .milliseconds(100)
    @ObservationIgnored
    private let repository: ClipRepository
    @ObservationIgnored
    private let limit: Int

    @ObservationIgnored
    private static let activeLayoutKey = "magpie.activeLayout"
    @ObservationIgnored
    private static let detailPaneKey = "magpie.detailPaneVisible"

    init(repository: ClipRepository, limit: Int = 200) {
        self.repository = repository
        self.limit = limit

        // Restore persisted layout preferences before refresh — so initial
        // render uses the user's last choice instead of the default.
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.activeLayoutKey),
           let restored = ActiveLayout(rawValue: raw) {
            self.activeLayout = restored
        }
        if defaults.object(forKey: Self.detailPaneKey) != nil {
            self.detailPaneVisible = defaults.bool(forKey: Self.detailPaneKey)
        }

        refresh()
    }

    // MARK: - Layout actions

    func cycleLayout() {
        activeLayout = activeLayout.next
    }

    func toggleDetailPane() {
        detailPaneVisible.toggle()
    }

    // MARK: - Refresh

    func refresh() {
        do {
            let query = currentQuery()
            let records = try repository.search(query, limit: limit)
            self.clips = records.compactMap { ClipDisplayItem(record: $0) }
            self.totalClipCount = (try? repository.count()) ?? clips.count
            if focusedIndex >= clips.count {
                focusedIndex = clips.isEmpty ? 0 : 0
            }
        } catch {
            NSLog("[ui] refresh failed: %@", "\(error)")
        }
    }

    private func scheduleDebouncedApply() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
        }
    }

    /// Reset to "no filter, no search" — Esc cascade calls this.
    func clearFiltersAndSearch() {
        debounceTask?.cancel()
        searchInput = ""
        typeFilter = nil
        pinnedOnly = false
    }

    private func currentQuery() -> SearchQuery {
        var query = SearchQueryParser.parse(searchInput, pinnedOnly: pinnedOnly)
        if let t = typeFilter {
            query.typeFilters.append(t)
        }
        return query
    }

    // MARK: - Pin toggle

    func toggleFocusedPin() {
        guard let clip = focusedClip else { return }
        let targetId = clip.id
        do {
            try repository.togglePin(clipId: targetId)
            refresh()
            if let newIdx = clips.firstIndex(where: { $0.id == targetId }) {
                focusedIndex = newIdx
            }
        } catch {
            NSLog("[ui] togglePin failed: %@", "\(error)")
        }
    }

    // MARK: - Focus navigation

    func moveBack() {
        guard !clips.isEmpty else { return }
        focusedIndex = max(0, focusedIndex - 1)
    }

    func moveForward() {
        guard !clips.isEmpty else { return }
        focusedIndex = min(clips.count - 1, focusedIndex + 1)
    }

    var focusedClip: ClipDisplayItem? {
        clips.indices.contains(focusedIndex) ? clips[focusedIndex] : nil
    }

    func clip(at index: Int) -> ClipDisplayItem? {
        clips.indices.contains(index) ? clips[index] : nil
    }

    func requestPaste(at index: Int) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        onPasteRequest?()
    }

    /// Single-click on a card: focus it AND open the detail pane (auto-show
    /// the user's intent). Arrow-key navigation deliberately does NOT do
    /// this — that path is for browsing without committing to detail view.
    func focusAndShowDetail(at index: Int) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        if !detailPaneVisible {
            detailPaneVisible = true
        }
    }
}
