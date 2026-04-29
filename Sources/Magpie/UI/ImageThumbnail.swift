import AppKit
import ImageIO

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
    static func load(path: String, maxPixelSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
