import Foundation

/// A spatial image treatment, not an animation or a backdrop permission.
public struct ProgressiveBlurParameters: Hashable, Sendable {
    public enum Curve: String, Hashable, Sendable { case linear, smoothstep }
    public let start, end, maxRadius, tintOpacity, cornerRadius: Double
    public let curve: Curve
    public init?(start: Double, end: Double, maxRadius: Double, curve: Curve = .smoothstep,
                 tintOpacity: Double = 0, cornerRadius: Double = 24) {
        guard [start, end, maxRadius, tintOpacity, cornerRadius].allSatisfy(\.isFinite),
              0 <= start, start < end, end <= 1, 0 <= maxRadius, maxRadius <= 32,
              0 <= tintOpacity, tintOpacity <= 0.2, 0 <= cornerRadius, cornerRadius <= 128 else { return nil }
        self.start = start; self.end = end; self.maxRadius = maxRadius; self.curve = curve
        self.tintOpacity = tintOpacity; self.cornerRadius = cornerRadius
    }
    /// Initial engineering values, pending native visual and Release performance acceptance.
    public static let cover = ProgressiveBlurParameters(start: 0.35, end: 0.9, maxRadius: 16)!
    public func intensity(at fractionFromTop: Double) -> Double {
        guard fractionFromTop.isFinite else { return 0 }
        let t = min(1, max(0, (fractionFromTop - start) / (end - start)))
        return curve == .linear ? t : t * t * (3 - 2 * t)
    }
}

public struct ProgressiveBlurOutput: Hashable, Sendable {
    public let width, height: Int
    public let requestedScale, effectiveScale: Double
    public let pointWidth, pointHeight: Double
    public init?(pointWidth: Double, pointHeight: Double, scale: Double) {
        guard [pointWidth, pointHeight, scale].allSatisfy(\.isFinite),
              pointWidth > 0, pointHeight > 0, pointWidth <= 10_000, pointHeight <= 10_000,
              scale > 0, scale <= 4 else { return nil }
        // Bound each derived surface before allocating or decoding pixels.
        let sizeLimit = 2048 / max(pointWidth, pointHeight)
        let areaLimit = sqrt(2_000_000 / (pointWidth * pointHeight))
        let actual = min(scale, min(sizeLimit, areaLimit))
        self.width = max(1, Int(floor(pointWidth * actual)))
        self.height = max(1, Int(floor(pointHeight * actual)))
        self.requestedScale = scale; self.effectiveScale = actual
        self.pointWidth = pointWidth; self.pointHeight = pointHeight
    }
}
