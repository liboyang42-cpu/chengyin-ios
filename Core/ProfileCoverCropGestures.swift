import Foundation

/// Local cover crop controls, shared by image gestures and the existing accessible sliders.
/// Deltas move the image beneath the fixed 16:9 frame, never the output frame itself.
public struct ProfileCoverCropPosition: Equatable {
    public var horizontal: Double
    public var vertical: Double
    public var zoom: Double
    public init(horizontal: Double = 0.5, vertical: Double = 0.5, zoom: Double = 1) {
        self.horizontal = horizontal; self.vertical = vertical; self.zoom = zoom
    }
    public func rect(sourceWidth: Int, sourceHeight: Int) throws -> MerchantImageCropRect {
        try .init(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspect: .gallery,
                  horizontal: horizontal, vertical: vertical, zoom: zoom)
    }
    public func panned(deltaX: Double, deltaY: Double, viewportWidth: Double, viewportHeight: Double,
                       sourceWidth: Int, sourceHeight: Int) throws -> Self {
        let crop = try rect(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        guard deltaX.isFinite, deltaY.isFinite, viewportWidth.isFinite, viewportHeight.isFinite,
              viewportWidth > 0, viewportHeight > 0 else { throw RetainedImageFailure.invalid }
        let xTravel = Double(sourceWidth - crop.width), yTravel = Double(sourceHeight - crop.height)
        // Keep fractional travel between events; integer rounding is only for rendering/export.
        let x = horizontal * xTravel - deltaX * Double(crop.width) / viewportWidth
        let y = vertical * yTravel - deltaY * Double(crop.height) / viewportHeight
        guard x.isFinite, y.isFinite else { throw RetainedImageFailure.invalid }
        return .init(horizontal: xTravel > 0 ? Self.unit(x / xTravel) : 0.5,
                     vertical: yTravel > 0 ? Self.unit(y / yTravel) : 0.5, zoom: zoom)
    }
    public func pinched(by factor: Double, sourceWidth: Int, sourceHeight: Int) throws -> Self {
        let old = try rect(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        guard factor.isFinite, factor > 0 else { throw RetainedImageFailure.invalid }
        let proposed = zoom * factor
        guard proposed.isFinite else { throw RetainedImageFailure.invalid }
        let nextZoom = min(4, max(1, proposed))
        let next = try MerchantImageCropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                                             aspect: .gallery, zoom: nextZoom)
        let xTravel = Double(sourceWidth - next.width), yTravel = Double(sourceHeight - next.height)
        // Keep the selected source center stable when zooming, then clamp at the image edge.
        let x = Double(old.x) + Double(old.width - next.width) / 2
        let y = Double(old.y) + Double(old.height - next.height) / 2
        return .init(horizontal: xTravel > 0 ? Self.unit(x / xTravel) : 0.5,
                     vertical: yTravel > 0 ? Self.unit(y / yTravel) : 0.5, zoom: nextZoom)
    }
    private static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
}
