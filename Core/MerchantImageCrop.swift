import Foundation

/// The mini merchant editor fixes these destination ratios. Other destinations
/// retain their existing policy; this is not an upload or photo-library grant.
public enum MerchantImageCropAspect: Equatable {
    case logo, cover, gallery
    public static func forDestination(_ destination: RetainedImageScope.Destination) -> Self? {
        switch destination {
        case .merchant(_, .logo): return .logo
        case .merchant(_, .coverImage): return .cover
        case .merchant(_, .gallery): return .gallery
        default: return nil
        }
    }
    public var widthUnits: Int {
        switch self { case .logo: return 1; case .cover: return 5; case .gallery: return 16 }
    }
    public var heightUnits: Int {
        switch self { case .logo: return 1; case .cover: return 3; case .gallery: return 9 }
    }
}

/// Integer pixel geometry keeps the output ratio exact, inside the upright source,
/// with no upscaling. Positions select the available travel, from leading to trailing.
public struct MerchantImageCropRect: Equatable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
    public init(sourceWidth: Int, sourceHeight: Int, aspect: MerchantImageCropAspect,
                horizontal: Double = 0.5, vertical: Double = 0.5, zoom: Double = 1) throws {
        guard (1...RetainedSelectedImage.maximumDimension).contains(sourceWidth),
              (1...RetainedSelectedImage.maximumDimension).contains(sourceHeight),
              horizontal.isFinite, vertical.isFinite, zoom.isFinite,
              (0...1).contains(horizontal), (0...1).contains(vertical), (1...4).contains(zoom) else {
            throw RetainedImageFailure.invalid
        }
        let available = min(sourceWidth / aspect.widthUnits, sourceHeight / aspect.heightUnits)
        guard available > 0 else { throw RetainedImageFailure.invalid }
        let units = max(1, Int((Double(available) / zoom).rounded(.down)))
        width = units * aspect.widthUnits; height = units * aspect.heightUnits
        x = Int((Double(sourceWidth - width) * horizontal).rounded())
        y = Int((Double(sourceHeight - height) * vertical).rounded())
    }
}
