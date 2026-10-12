import AppKit
import Vision
import NaturalLanguage

struct ScreenshotTextLine: Sendable {
    let text: String
    let bounds: CGRect
}

struct ScreenshotAnalysisResult: Sendable {
    let lines: [ScreenshotTextLine]
    let privateRegions: [CGRect]
    var text: String { lines.map(\.text).joined(separator: "\n") }
}

enum ScreenshotAnalysis {
    static func analyze(_ image: CGImage, privacy: Bool = false) async throws -> ScreenshotAnalysisResult {
        try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.recognitionLanguages = ["zh-Hans", "en-US"]
            textRequest.usesLanguageCorrection = true
            let faces = VNDetectFaceRectanglesRequest()
            let requests: [VNRequest] = privacy ? [textRequest, faces] : [textRequest]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
            let lines = (textRequest.results ?? []).compactMap { observation -> ScreenshotTextLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return ScreenshotTextLine(text: candidate.string, bounds: observation.boundingBox)
            }.sorted { left, right in
                abs(left.bounds.midY - right.bounds.midY) < min(left.bounds.height, right.bounds.height) / 2
                    ? left.bounds.minX < right.bounds.minX : left.bounds.midY > right.bounds.midY
            }
            var regions = (faces.results ?? []).map(\.boundingBox)
            if privacy {
                regions += lines.filter { containsPrivateText($0.text) }.map(\.bounds)
            }
            return ScreenshotAnalysisResult(lines: lines, privateRegions: regions)
        }.value
    }

    static func containsPrivateText(_ text: String) -> Bool {
        let patterns = [#"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d[ -]?\d{4}[ -]?\d{4}(?!\d)"#,
                        #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
                        #"(?<!\d)\d{17}[\dX](?!\d)"#,
                        #"(?:姓名|联系人|手机号?|电话|邮箱|微信号|住址|地址|账号)\s*[:：]"#]
        if patterns.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) { return true }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, _ in
            if tag == .personalName { found = true; return false }
            return true
        }
        return found
    }

    static func localRect(_ normalized: CGRect, in selection: CGRect) -> CGRect {
        CGRect(x: selection.minX + normalized.minX * selection.width,
               y: selection.minY + normalized.minY * selection.height,
               width: normalized.width * selection.width, height: normalized.height * selection.height)
            .insetBy(dx: -4, dy: -4).intersection(selection)
    }
}

@MainActor
final class ScreenshotPixelSampler {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let size: CGSize
    init(image: CGImage, pointSize: CGSize) {
        width = image.width; height = image.height; size = pointSize
        if let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                   bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
           let bytes = context.data?.assumingMemoryBound(to: UInt8.self) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            pixels = Array(UnsafeBufferPointer(start: bytes, count: image.width * image.height * 4))
        } else { pixels = [] }
    }
    func hex(at point: CGPoint) -> String {
        guard !pixels.isEmpty, size.width > 0, size.height > 0 else { return "#000000" }
        let x = min(width - 1, max(0, Int(point.x / size.width * CGFloat(width))))
        let y = min(height - 1, max(0, height - 1 - Int(point.y / size.height * CGFloat(height))))
        let i = (y * width + x) * 4
        return String(format: "#%02X%02X%02X", pixels[i], pixels[i + 1], pixels[i + 2])
    }
}
