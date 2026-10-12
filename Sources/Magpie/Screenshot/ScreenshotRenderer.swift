import AppKit
import ImageIO

@MainActor
enum ScreenshotRenderer {
    static func pixelated(_ image: CGImage, pointSize: CGSize) -> CGImage? {
        let width = max(1, Int(pointSize.width / 12))
        let height = max(1, Int(pointSize.height / 12))
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    static func draw(_ annotations: [ScreenshotAnnotation], in context: CGContext,
                     imageBounds: CGRect, pixelatedImage: CGImage?) {
        for annotation in annotations {
            guard let first = annotation.points.first else { continue }
            context.saveGState()
            context.setStrokeColor(annotation.ink.color.cgColor)
            context.setFillColor(annotation.ink.color.cgColor)
            context.setLineWidth(annotation.width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            switch annotation.tool {
            case .selection: break
            case .rectangle:
                annotation.filled ? context.fill(annotation.rect) : context.stroke(annotation.rect)
            case .ellipse:
                annotation.filled ? context.fillEllipse(in: annotation.rect) : context.strokeEllipse(in: annotation.rect)
            case .arrow:
                let end = annotation.points.last ?? first
                let angle = atan2(end.y - first.y, end.x - first.x)
                let length = min(max(12, annotation.width * 4), hypot(end.x - first.x, end.y - first.y) * 0.6)
                context.move(to: first)
                context.addLine(to: end)
                context.strokePath()
                context.move(to: CGPoint(x: end.x - length * cos(angle - .pi / 6),
                                        y: end.y - length * sin(angle - .pi / 6)))
                context.addLine(to: end)
                context.addLine(to: CGPoint(x: end.x - length * cos(angle + .pi / 6),
                                           y: end.y - length * sin(angle + .pi / 6)))
                context.strokePath()
            case .pen:
                if annotation.points.count == 1 {
                    context.fillEllipse(in: CGRect(x: first.x - annotation.width / 2,
                                                   y: first.y - annotation.width / 2,
                                                   width: annotation.width, height: annotation.width))
                } else {
                    context.addLines(between: annotation.points)
                    context.strokePath()
                }
            case .text, .sticker:
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                let font = NSFont.systemFont(ofSize: annotation.textSize, weight: .medium)
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: annotation.ink.color]
                if annotation.tool == .text, annotation.textBoxWidth != nil {
                    (annotation.text as NSString).draw(in: annotation.drawingBounds, withAttributes: attributes)
                } else {
                    (annotation.text as NSString).draw(at: first, withAttributes: attributes)
                }
                NSGraphicsContext.restoreGraphicsState()
            case .mosaic:
                // Export fails closed if the mosaic texture cannot be allocated.
                if annotation.mosaicBrush {
                    let diameter = max(12, annotation.width * 10)
                    if annotation.points.count > 1 {
                        context.setLineWidth(diameter)
                        context.addLines(between: annotation.points)
                        context.replacePathWithStrokedPath()
                        context.clip()
                    } else {
                        context.addEllipse(in: CGRect(x: first.x - diameter / 2, y: first.y - diameter / 2, width: diameter, height: diameter))
                        context.clip()
                    }
                } else {
                    context.clip(to: annotation.rect)
                }
                if let pixelatedImage {
                    context.interpolationQuality = .none
                    context.draw(pixelatedImage, in: imageBounds)
                } else {
                    context.setFillColor(NSColor.black.cgColor)
                    context.fill(imageBounds)
                }
            }
            context.restoreGState()
        }
    }

    static func render(image: CGImage, pointSize: CGSize, state: ScreenshotEditorState) -> CGImage? {
        let bounds = CGRect(origin: .zero, size: pointSize)
        guard let selection = state.selection, pointSize.width > 0, pointSize.height > 0 else { return nil }
        let scale = CGFloat(image.width) / pointSize.width
        let crop = ScreenshotGeometry.pixelAligned(selection, scale: scale, within: bounds)
        guard crop.width >= 1 / scale, crop.height >= 1 / scale,
              let context = context(width: Int((crop.width * scale).rounded()),
                                    height: Int((crop.height * scale).rounded())) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.draw(image, in: bounds)
        let mosaic = state.annotations.contains { $0.tool == .mosaic }
            ? pixelated(image, pointSize: pointSize) : nil
        draw(state.annotations, in: context, imageBounds: bounds, pixelatedImage: mosaic)
        return context.makeImage()
    }

    static func png(image: CGImage, pointSize: CGSize, state: ScreenshotEditorState) -> Data? {
        guard let result = render(image: image, pointSize: pointSize, state: state) else { return nil }
        return NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}


enum ScreenshotPNG {
    static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
