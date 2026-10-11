import Foundation

public enum RoamStampFramingFailure: Error, Equatable { case invalidGeometry }

/// Native adaptation of P027 layout.js / crop.js. Values describe the visible preview card,
/// not screen points, camera sensor zoom, imported photos, or persisted location metadata.
public struct RoamStampFrame: Equatable {
    public let viewportWidth: Double
    public let viewportHeight: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(viewportWidth: Double, viewportHeight: Double, ratio: Double) throws {
        guard Self.validDimension(viewportWidth), Self.validDimension(viewportHeight), ratio.isFinite,
              (RoamStampFramingState.minimumRatio...RoamStampFramingState.maximumRatio).contains(ratio) else {
            throw RoamStampFramingFailure.invalidGeometry
        }
        let width = min(viewportWidth, viewportHeight * 0.8) * ratio
        guard width >= 4 else { throw RoamStampFramingFailure.invalidGeometry }
        self.viewportWidth = viewportWidth; self.viewportHeight = viewportHeight
        self.width = width; height = width / 0.8
        x = (viewportWidth - width) / 2; y = (viewportHeight - height) / 2
    }
    private static func validDimension(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 30_000 }

    /// Both preview and photo use portrait, non-mirrored rear wide-angle capture. UIKit normalizes
    /// image orientation before these dimensions are supplied. Preview gravity is aspect-fill.
    public func crop(imageWidth: Double, imageHeight: Double) throws -> RoamStampPixelRegion {
        guard Self.validDimension(imageWidth), Self.validDimension(imageHeight), imageWidth >= 1, imageHeight >= 1,
              imageWidth * imageHeight <= 100_000_000 else { throw RoamStampFramingFailure.invalidGeometry }
        let scale = max(viewportWidth / imageWidth, viewportHeight / imageHeight)
        let left = (viewportWidth - imageWidth * scale) / 2
        let top = (viewportHeight - imageHeight * scale) / 2
        let sourceX = max(0, (x - left) / scale), sourceY = max(0, (y - top) / scale)
        let right = min(imageWidth, (x + width - left) / scale)
        let bottom = min(imageHeight, (y + height - top) / scale)
        let sourceWidth = min(right - sourceX, (bottom - sourceY) * 0.8)
        let sourceHeight = sourceWidth / 0.8
        // Quantize output width, not the source geometry: exact 4:5 pixels, never stretch or upscale.
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth >= 4 else { throw RoamStampFramingFailure.invalidGeometry }
        let outputWidth = Int(floor(min(1600, sourceWidth) / 4)) * 4
        return .init(x: sourceX + (right - sourceX - sourceWidth) / 2,
                     y: sourceY + (bottom - sourceY - sourceHeight) / 2,
                     width: sourceWidth, height: sourceHeight,
                     outputWidth: outputWidth, outputHeight: outputWidth / 4 * 5)
    }
}
public struct RoamStampPixelRegion: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let outputWidth: Int
    public let outputHeight: Int
}
public struct RoamStampFramingShot: Equatable {
    public let id: UUID
    public let frame: RoamStampFrame
    public let ratio: Double
}

/// One capture owns an immutable framing snapshot until it fails or is consumed. An invalidated
/// screen cannot accept late camera callbacks, and a new retake starts with an independent state.
public struct RoamStampFramingState {
    public static let minimumRatio = 0.4
    public static let maximumRatio = 0.9
    public static let defaultRatio = 0.74
    public private(set) var ratio = RoamStampFramingState.defaultRatio
    public private(set) var pending: RoamStampFramingShot?
    public private(set) var isActive = true
    public init() {}
    public mutating func adjust(to value: Double) {
        guard isActive, pending == nil, value.isFinite else { return }
        ratio = min(Self.maximumRatio, max(Self.minimumRatio, value))
    }
    public mutating func begin(viewportWidth: Double, viewportHeight: Double) throws -> RoamStampFramingShot? {
        guard isActive, pending == nil else { return nil }
        let shot = RoamStampFramingShot(id: UUID(), frame: try .init(viewportWidth: viewportWidth, viewportHeight: viewportHeight, ratio: ratio), ratio: ratio)
        pending = shot; return shot
    }
    @discardableResult public mutating func resolve(_ id: UUID, succeeded: Bool) -> Bool {
        guard isActive, pending?.id == id else { return false }
        pending = nil
        if succeeded { isActive = false }
        return true
    }
    public mutating func cancel() { isActive = false; pending = nil }
}
