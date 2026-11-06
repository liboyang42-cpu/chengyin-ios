import UIKit

/// Local JPEG export for `MiniCropView` results against an already sanitized,
/// upright retained image. No picker, upload, permission, or reference mutation.
@MainActor enum CreatorCropExport {
    static func validatedImage(_ source: RetainedSelectedImage) throws -> UIImage {
        guard let image = UIImage(data: source.jpeg), image.imageOrientation == .up,
              let pixels = image.cgImage, pixels.width == source.width, pixels.height == source.height else {
            throw RetainedImageFailure.invalid
        }
        return image
    }

    static func export(_ source: RetainedSelectedImage, result: MiniCropView.Result) throws -> RetainedSelectedImage {
        switch result {
        case .original:
            _ = try validatedImage(source)
            return source // Exact retained bytes and identity; never re-encoded.
        case .crop(let rect):
            return try render(source, rect: rect)
        }
    }

    static func render(_ source: RetainedSelectedImage, rect: MiniCropGeometry.SourceRect) throws -> RetainedSelectedImage {
        let image = try validatedImage(source)
        guard rect.x.isFinite, rect.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
              rect.x + rect.width <= Double(source.width), rect.y + rect.height <= Double(source.height) else {
            throw RetainedImageFailure.invalid
        }
        let outputWidth = max(1, Int(rect.width.rounded())), outputHeight = max(1, Int(rect.height.rounded()))
        let size = CGSize(width: outputWidth, height: outputHeight)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let output = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.clip(to: CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .high
            let sx = size.width / CGFloat(rect.width), sy = size.height / CGFloat(rect.height)
            image.draw(in: CGRect(x: -CGFloat(rect.x) * sx, y: -CGFloat(rect.y) * sy,
                                  width: CGFloat(source.width) * sx, height: CGFloat(source.height) * sy))
        }
        for quality in [0.92, 0.75, 0.55] {
            if let bytes = output.jpegData(compressionQuality: quality), bytes.count <= RetainedSelectedImage.maximumBytes {
                return try .init(jpeg: bytes, width: outputWidth, height: outputHeight)
            }
        }
        throw RetainedImageFailure.invalid
    }
}
