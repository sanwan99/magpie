import CoreGraphics
import Foundation

enum ScreenshotStitchResult: Equatable {
    case appended(Int), unchanged, insufficientOverlap, sizeChanged, limitReached
}

final class ScreenshotStitcher {
    private(set) var image: CGImage
    private var previous: CGImage
    private var samples: [UInt8]
    private(set) var frames = 1
    private let maxPixels: Int
    private let columns = 32

    init(image: CGImage, maxPixels: Int = 40_000_000) {
        self.image = image; previous = image; self.maxPixels = maxPixels
        samples = Self.fingerprint(image)
    }

    func append(_ next: CGImage) -> ScreenshotStitchResult {
        guard next.width == previous.width, next.height == previous.height else { return .sizeChanged }
        let nextSamples = Self.fingerprint(next)
        let height = next.height
        guard height >= 64, samples.count == height * columns, nextSamples.count == samples.count else { return .insufficientOverlap }
        func rowError(_ a: Int, _ b: Int) -> Double {
            var total = 0
            for x in 0..<columns { total += abs(Int(samples[a * columns + x]) - Int(nextSamples[b * columns + x])) }
            return Double(total) / Double(columns)
        }
        let wholeError = stride(from: 0, to: height, by: max(1, height / 96)).map { rowError($0, $0) }.reduce(0, +)
        if wholeError < 0.4 { return .unchanged }
        var top = 0, bottom = 0
        while top < height / 4, rowError(top, top) < 0.1 { top += 1 }
        while bottom < height / 4, rowError(height - bottom - 1, height - bottom - 1) < 0.1 { bottom += 1 }
        let minOverlap = max(32, height / 6)
        let maximum = height - top - bottom - minOverlap
        guard maximum > 1 else { return .insufficientOverlap }
        func score(_ shift: Int) -> (Double, Int) {
            let end = height - bottom - shift
            guard end - top >= minOverlap else { return (.infinity, 0) }
            var total = 0.0, count = 0, low: UInt8 = 255, high: UInt8 = 0
            for y in stride(from: top, to: end, by: max(1, (end - top) / 64)) {
                total += rowError(y + shift, y); count += 1
                for x in 0..<columns {
                    let value = nextSamples[y * columns + x]
                    low = min(low, value); high = max(high, value)
                }
            }
            return (total / Double(max(1, count)), Int(high) - Int(low))
        }
        let step = 1
        var bestShift = 0, bestScore = Double.infinity
        for shift in stride(from: 1, through: maximum, by: step) {
            let value = score(shift)
            if value.1 >= 8, value.0 < bestScore { bestShift = shift; bestScore = value.0 }
        }
        guard bestShift > 0 else { return .insufficientOverlap }
        for shift in max(1, bestShift - step)...min(maximum, bestShift + step) {
            let value = score(shift)
            if value.1 >= 8, value.0 < bestScore { bestShift = shift; bestScore = value.0 }
        }
        guard bestScore < 6 else { return .insufficientOverlap }
        let newHeight = image.height + bestShift
        guard newHeight <= 30_000, newHeight <= maxPixels / max(1, next.width) else { return .limitReached }
        // Join inside the matching overlap. Replacing the old viewport's lower overlap also
        // removes transient window corners and edge decorations from intermediate joins.
        let overlap = height - top - bottom - bestShift
        let replacedRows = bottom + overlap / 2
        guard let old = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.height - replacedRows)),
              let tail = next.cropping(to: CGRect(x: 0, y: height - replacedRows - bestShift, width: next.width, height: replacedRows + bestShift)),
              let context = CGContext(data: nil, width: next.width, height: newHeight, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .limitReached }
        context.draw(old, in: CGRect(x: 0, y: tail.height, width: old.width, height: old.height))
        context.draw(tail, in: CGRect(x: 0, y: 0, width: tail.width, height: tail.height))
        guard let output = context.makeImage() else { return .limitReached }
        image = output; previous = next; samples = nextSamples; frames += 1
        return .appended(bestShift)
    }

    private static func fingerprint(_ image: CGImage) -> [UInt8] {
        let width = 32
        guard let context = CGContext(data: nil, width: width, height: image.height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return [] }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: image.height))
        return (0..<(width * image.height)).map { index in
            let i = index * 4
            return UInt8((Int(data[i]) * 3 + Int(data[i + 1]) * 6 + Int(data[i + 2])) / 10)
        }
    }
}
