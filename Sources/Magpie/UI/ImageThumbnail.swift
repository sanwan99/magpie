import AppKit
import ImageIO
import SwiftUI

/// ImageIO 在后台解码到预览尺寸；列表和详情通过同一个加载器复用缩略图。
enum ImageThumbnail {
    struct Request: Hashable, Sendable {
        let path: String
        let maxPixelSize: Int
    }

    enum Phase {
        case loading
        case loaded(NSImage)
        case failed(LoadFailureReason)
    }

    enum LoadFailureReason: String, Sendable {
        case missingFile = "missing"
        case decodeFailed = "decode failed"
    }

    enum DecodeResult: Sendable {
        case loaded(CGImage)
        case failed(LoadFailureReason)
    }

    static func decode(_ request: Request) -> DecodeResult {
        guard FileManager.default.fileExists(atPath: request.path) else {
            return .failed(.missingFile)
        }

        let url = URL(fileURLWithPath: request.path)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, request.maxPixelSize)
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else {
            if let fallback = NSImage(contentsOfFile: request.path),
               let cg = fallback.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return .loaded(cg)
            }
            return .failed(.decodeFailed)
        }
        return .loaded(cg)
    }
}

private final class ThumbnailMemoryCache: @unchecked Sendable {
    private final class CachedImage {
        let image: CGImage
        let version: String
        init(_ image: CGImage, version: String) {
            self.image = image
            self.version = version
        }
    }

    private let cache = NSCache<NSString, CachedImage>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 256
    }

    func image(for request: ImageThumbnail.Request, version: String? = nil) -> CGImage? {
        guard let entry = cache.object(forKey: key(request)),
              version == nil || entry.version == version else { return nil }
        return entry.image
    }

    func store(_ image: CGImage, for request: ImageThumbnail.Request, version: String) {
        cache.setObject(CachedImage(image, version: version), forKey: key(request), cost: image.bytesPerRow * image.height)
    }

    func remove(_ request: ImageThumbnail.Request) { cache.removeObject(forKey: key(request)) }

    private func key(_ request: ImageThumbnail.Request) -> NSString {
        "\(request.path)\u{0}\(request.maxPixelSize)" as NSString
    }
}

actor ImageThumbnailLoader {
    static let shared = ImageThumbnailLoader()

    private nonisolated let cache = ThumbnailMemoryCache()
    private let queue = OperationQueue()
    private let decoder: @Sendable (ImageThumbnail.Request) -> ImageThumbnail.DecodeResult
    private var pending: [ImageThumbnail.Request: Task<ImageThumbnail.DecodeResult, Never>] = [:]

    init(decoder: @escaping @Sendable (ImageThumbnail.Request) -> ImageThumbnail.DecodeResult = { ImageThumbnail.decode($0) }) {
        self.decoder = decoder
        queue.name = "Magpie image thumbnails"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
    }

    /// 只查内存；文件是否仍有效由随后的后台加载检查。
    nonisolated func cachedImage(for request: ImageThumbnail.Request) -> CGImage? {
        cache.image(for: request)
    }

    func prefetch(_ requests: [ImageThumbnail.Request]) async {
        await withTaskGroup(of: Void.self) { group in
            for request in Set(requests) {
                group.addTask { _ = await self.load(request) }
            }
        }
    }

    func load(_ request: ImageThumbnail.Request) async -> ImageThumbnail.DecodeResult {
        if let task = pending[request] { return await task.value }

        let task = Task { await resolve(request) }
        pending[request] = task
        let result = await task.value
        pending[request] = nil
        return result
    }

    private func resolve(_ request: ImageThumbnail.Request) async -> ImageThumbnail.DecodeResult {
        // 文件状态也在后台检查，删除或替换图片后不复用旧缓存。
        let key: String? = await runInBackground {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: request.path),
                  let modified = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber else { return nil }
            let inode = attributes[.systemFileNumber] as? NSNumber
            return "\(request.path)\u{0}\(request.maxPixelSize)\u{0}\(modified.timeIntervalSince1970)\u{0}\(size)\u{0}\(inode?.uint64Value ?? 0)"
        }
        guard let key else {
            cache.remove(request)
            return .failed(.missingFile)
        }
        if let image = cache.image(for: request, version: key) { return .loaded(image) }

        let decoder = self.decoder
        let result = await runInBackground { decoder(request) }
        if case .loaded(let image) = result {
            cache.store(image, for: request, version: key)
        } else {
            cache.remove(request)
        }
        return result
    }

    private func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.addOperation {
                continuation.resume(returning: autoreleasepool(invoking: work))
            }
        }
    }
}

struct AsyncImageThumbnail<Content: View>: View {
    let path: String
    let maxPixelSize: Int
    let content: (ImageThumbnail.Phase) -> Content
    private let loader: ImageThumbnailLoader

    @State private var loadedRequest: ImageThumbnail.Request?
    @State private var phase: ImageThumbnail.Phase = .loading
    @State private var displayedImage: CGImage?

    init(path: String, maxPixelSize: Int, loader: ImageThumbnailLoader = .shared,
         @ViewBuilder content: @escaping (ImageThumbnail.Phase) -> Content) {
        self.path = path
        self.maxPixelSize = maxPixelSize
        self.loader = loader
        self.content = content
        let request = ImageThumbnail.Request(path: path, maxPixelSize: maxPixelSize)
        let cached = loader.cachedImage(for: request)
        _displayedImage = State(initialValue: cached)
        _loadedRequest = State(initialValue: cached == nil ? nil : request)
        _phase = State(initialValue: cached.map {
            .loaded(NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)))
        } ?? .loading)
    }

    private var request: ImageThumbnail.Request {
        ImageThumbnail.Request(path: path, maxPixelSize: maxPixelSize)
    }

    var body: some View {
        content(loadedRequest == request ? phase : .loading)
            .task(id: request) {
                let result = await loader.load(request)
                guard !Task.isCancelled else { return }
                switch result {
                case .loaded(let image):
                    if loadedRequest == request, displayedImage === image { return }
                    displayedImage = image
                    phase = .loaded(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                case .failed(let reason):
                    displayedImage = nil
                    phase = .failed(reason)
                }
                loadedRequest = request
            }
    }
}

struct ImageThumbnailPlaceholder: View {
    let reason: ImageThumbnail.LoadFailureReason
    var iconSize: CGFloat = 28
    var showLabel = true
    private let settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "photo")
                .font(.system(size: iconSize))
                .foregroundStyle(.tertiary)
            if showLabel {
                Text(failureText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureText: String {
        switch reason {
        case .missingFile:
            return settings.language.pick(zh: "图片文件丢失", en: "missing")
        case .decodeFailed:
            return settings.language.pick(zh: "图片解码失败", en: "decode failed")
        }
    }
}
