import AppKit
import ImageIO
import SwiftUI

/// 用 ImageIO 的 `CGImageSourceCreateThumbnailAtIndex` 加载缩略图。
///
/// 直接 `NSImage(contentsOfFile:)` 会把整张图解码到全分辨率位图：
/// 一张 2400×840 的 PNG 在磁盘上 600 KB，解码后 8 MB；130 张 image clip
/// 同时在内存里就是 ~1 GB，是 v0.3 单进程内存占用爆 600 MB+ 的主因。
///
/// `CGImageSourceCreateThumbnailAtIndex` 的优势：
/// - **只解码到目标尺寸**（256×256 → 256 KB / 张），内存降一个量级
/// - **复用 PNG 自带的预生成缩略图**（如果有），更快
/// - **kCGImageSourceShouldCacheImmediately** 一次解码完直接 cache，不会
///   被 Image I/O 反复重解码
///
/// 调用约定：
/// - **列表卡片（Stripe/Stack/Grid）**：传 256
/// - **DetailPane（右侧详情）**：传 800
/// - **ExpandedPreviewWindow（用户主动放大）**：仍用 NSImage(contentsOfFile:)
///   原图，因为用户就是要看细节
enum ImageThumbnail {
    enum LoadResult {
        case loaded(NSImage)
        case failed(LoadFailureReason)

        var image: NSImage? {
            if case .loaded(let image) = self {
                return image
            }
            return nil
        }
    }

    enum LoadFailureReason: String {
        case missingFile = "missing"
        case decodeFailed = "decode failed"
    }

    static func load(path: String, maxPixelSize: CGFloat) -> NSImage? {
        loadResult(path: path, maxPixelSize: maxPixelSize).image
    }

    static func loadResult(path: String, maxPixelSize: CGFloat) -> LoadResult {
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("[image] thumbnail missing file path=%@", path)
            return .failed(.missingFile)
        }

        let url = URL(fileURLWithPath: path)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else {
            if let fallback = NSImage(contentsOfFile: path) {
                NSLog("[image] ImageIO thumbnail failed, NSImage fallback ok path=%@", path)
                return .loaded(fallback)
            }
            NSLog("[image] thumbnail decode failed path=%@", path)
            return .failed(.decodeFailed)
        }
        return .loaded(NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
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
