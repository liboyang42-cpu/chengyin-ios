import Foundation

/// Keeps the upright source aspect. Only composition changes:
/// the fixed frame reveals a smaller source rectangle as zoom increases.
/// Fractional source pixels avoid destroying the aspect of coprime dimensions.
/// This is separate from MerchantImageCropRect's fixed destination ratios.
public struct TemplateImageCropRect: Equatable {
    public static let maximumOutputEdge = 1440
    public let sourceWidth: Int
    public let sourceHeight: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(sourceWidth: Int, sourceHeight: Int,
                horizontal: Double = 0.5, vertical: Double = 0.5, zoom: Double = 1) throws {
        guard (1...RetainedSelectedImage.maximumDimension).contains(sourceWidth),
              (1...RetainedSelectedImage.maximumDimension).contains(sourceHeight),
              horizontal.isFinite, vertical.isFinite, zoom.isFinite,
              (0...1).contains(horizontal), (0...1).contains(vertical),
              (1...4).contains(zoom) else { throw RetainedImageFailure.invalid }
        self.sourceWidth = sourceWidth; self.sourceHeight = sourceHeight
        width = Double(sourceWidth) / zoom; height = Double(sourceHeight) / zoom
        x = (Double(sourceWidth) - width) * horizontal
        y = (Double(sourceHeight) - height) * vertical
    }

    /// Panning at 1x has no travel and is still an identity operation.
    public var isIdentity: Bool {
        x == 0 && y == 0 && width == Double(sourceWidth) && height == Double(sourceHeight)
    }

    /// Identity output is the original sanitized image. Edited output follows
    /// a 1440px cap and nearest-pixel rounding, with a one-pixel minimum.
    /// Integer encoding can approximate the aspect by up to half a pixel per edge.
    public var outputWidth: Int { isIdentity ? sourceWidth : outputDimension(width) }
    public var outputHeight: Int { isIdentity ? sourceHeight : outputDimension(height) }
    private func outputDimension(_ dimension: Double) -> Int {
        let scale = min(1, Double(Self.maximumOutputEdge) / max(width, height))
        return max(1, Int((dimension * scale).rounded()))
    }
}
