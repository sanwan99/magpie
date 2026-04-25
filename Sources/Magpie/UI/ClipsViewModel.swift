import Foundation
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
        case unsupported
    }
}

extension ClipDisplayItem {
    /// Decode the persisted record into a UI-ready item. Returns nil if the row is
    /// malformed (unknown type or undecodable payload).
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
            preview = .unsupported
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

/// MainActor-isolated observable view model.
/// `refresh()` reloads the most recent N clips from the repository; the panel
/// re-renders via SwiftUI's @Published binding.
@MainActor
final class ClipsViewModel: ObservableObject {
    @Published private(set) var clips: [ClipDisplayItem] = []
    @Published var focusedIndex: Int = 0

    /// Owned by `PanelController`. Invoked when the UI requests a paste —
    /// e.g. double-click or `requestPaste(at:)`.
    var onPasteRequest: (() -> Void)?

    private let repository: ClipRepository
    private let limit: Int

    init(repository: ClipRepository, limit: Int = 200) {
        self.repository = repository
        self.limit = limit
        refresh()
    }

    func refresh() {
        do {
            let records = try repository.recent(limit: limit)
            self.clips = records.compactMap { ClipDisplayItem(record: $0) }
            // After refresh, keep focus in bounds (favor head if list shrank).
            if focusedIndex >= clips.count {
                focusedIndex = clips.isEmpty ? 0 : 0
            }
        } catch {
            NSLog("[ui] refresh failed: %@", "\(error)")
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

    /// Set focus then request a paste — used by double-click and ⌘N quick paste.
    func requestPaste(at index: Int) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        onPasteRequest?()
    }
}
