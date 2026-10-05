import UIKit

/// Accepts only the existing bounded, metadata-free, upright sanitizer result.
/// No picker, upload, target reference, or merchant ratio is part of this seam.
@MainActor enum TemplateImageCropRenderer {
    static func validatedImage(_ source: RetainedSelectedImage) throws -> UIImage {
        guard let image = UIImage(data: source.jpeg), image.imageOrientation == .up,
              let pixels = image.cgImage, pixels.width == source.width, pixels.height == source.height else {
            throw RetainedImageFailure.invalid
        }
        return image
    }

    static func preview(_ source: RetainedSelectedImage, rect: TemplateImageCropRect) throws -> UIImage {
        let image = try validatedImage(source)
        try validate(rect, source: source)
        return rect.isIdentity ? image : draw(image, rect: rect)
    }

    static func render(_ source: RetainedSelectedImage, rect: TemplateImageCropRect) throws -> RetainedSelectedImage {
        let image = try validatedImage(source)
        try validate(rect, source: source)
        // Preserve both identity and exact sanitized bytes; never re-encode a no-op.
        if rect.isIdentity { return source }
        let output = draw(image, rect: rect)
        for quality in [0.92, 0.75, 0.55] {
            if let bytes = output.jpegData(compressionQuality: quality), bytes.count <= RetainedSelectedImage.maximumBytes {
                return try .init(jpeg: bytes, width: rect.outputWidth, height: rect.outputHeight)
            }
        }
        throw RetainedImageFailure.invalid
    }

    private static func validate(_ rect: TemplateImageCropRect, source: RetainedSelectedImage) throws {
        guard rect.sourceWidth == source.width, rect.sourceHeight == source.height,
              rect.x >= 0, rect.y >= 0, rect.width > 0, rect.height > 0,
              rect.x + rect.width <= Double(source.width),
              rect.y + rect.height <= Double(source.height) else { throw RetainedImageFailure.invalid }
    }

    private static func draw(_ image: UIImage, rect: TemplateImageCropRect) -> UIImage {
        let size = CGSize(width: rect.outputWidth, height: rect.outputHeight)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.clip(to: CGRect(origin: .zero, size: size))
            context.cgContext.interpolationQuality = .high
            // Keep fractional geometry through the draw. CGImage.cropping would
            // expand the rectangle to integer pixels and change the chosen aspect.
            let sx = size.width / CGFloat(rect.width), sy = size.height / CGFloat(rect.height)
            image.draw(in: CGRect(x: -CGFloat(rect.x) * sx, y: -CGFloat(rect.y) * sy,
                                  width: CGFloat(rect.sourceWidth) * sx, height: CGFloat(rect.sourceHeight) * sy))
        }
    }
}
