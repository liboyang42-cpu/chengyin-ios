import Foundation

/// Pure port of mini-program pages/crop/utils/crop-geometry.js. The crop frame stays centered;
/// the image pans/zooms under it. `scale` is relative to a cover-fit base and is clamped to 1...4.
public enum MiniCropGeometry {
    public static let minimumScale = 1.0
    public static let maximumScale = 4.0

    public struct Transform: Equatable { public let scale, x, y: Double }
    public struct SourceRect: Equatable { public let x, y, width, height: Double }

    /// "16:9" → 1.777…; "free" or anything invalid → nil (caller uses the source ratio).
    public static func ratio(_ literal: String?) -> Double? {
        let parts = (literal ?? "").trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return w / h
    }

    /// Ratios callers pass through `cropInit` today: free, 1:1, 16:9, 4:3, 3:4, 5:4, 4:5, 9:16.
    public static let presets = ["free", "1:1", "16:9", "4:3", "3:4", "5:4", "4:5", "9:16"]

    /// Largest frame of `ratio` (or the source ratio when free) that fits the available box.
    public static func frame(ratio literal: String?, imageWidth: Double, imageHeight: Double,
                             availableWidth: Double, availableHeight: Double) -> (width: Double, height: Double)? {
        guard imageWidth > 0, imageHeight > 0, availableWidth > 0, availableHeight > 0 else { return nil }
        let r = ratio(literal) ?? imageWidth / imageHeight
        var w = availableWidth, h = w / r
        if h > availableHeight { h = availableHeight; w = h * r }
        return (w, h)
    }

    static func baseScale(imageWidth: Double, imageHeight: Double, frameWidth: Double, frameHeight: Double) -> Double {
        max(frameWidth / imageWidth, frameHeight / imageHeight)
    }

    public static func clamp(scale: Double, x: Double, y: Double, imageWidth: Double, imageHeight: Double,
                             frameWidth: Double, frameHeight: Double) -> Transform {
        let s = min(maximumScale, max(minimumScale, scale))
        let base = baseScale(imageWidth: imageWidth, imageHeight: imageHeight, frameWidth: frameWidth, frameHeight: frameHeight)
        let maxX = max(0, (imageWidth * base * s - frameWidth) / 2), maxY = max(0, (imageHeight * base * s - frameHeight) / 2)
        return .init(scale: s, x: min(maxX, max(-maxX, x)) + 0, y: min(maxY, max(-maxY, y)) + 0)
    }

    /// Source-pixel rectangle for the current transform; nil for degenerate sizes.
    public static func cropRect(scale: Double, x: Double, y: Double, imageWidth: Double, imageHeight: Double,
                                frameWidth: Double, frameHeight: Double) -> SourceRect? {
        guard imageWidth > 0, imageHeight > 0, frameWidth > 0, frameHeight > 0 else { return nil }
        let t = clamp(scale: scale, x: x, y: y, imageWidth: imageWidth, imageHeight: imageHeight, frameWidth: frameWidth, frameHeight: frameHeight)
        let eff = baseScale(imageWidth: imageWidth, imageHeight: imageHeight, frameWidth: frameWidth, frameHeight: frameHeight) * t.scale
        let sw = frameWidth / eff, sh = frameHeight / eff
        let sx = ((imageWidth * eff - frameWidth) / 2 - t.x) / eff, sy = ((imageHeight * eff - frameHeight) / 2 - t.y) / eff
        return .init(x: min(max(0, imageWidth - sw), max(0, sx)), y: min(max(0, imageHeight - sh), max(0, sy)),
                     width: min(sw, imageWidth), height: min(sh, imageHeight))
    }

    /// Mini confirm shortcut: free ratio with no zoom/pan keeps the original file ("使用原图" semantics).
    public static func keepsOriginal(ratio literal: String?, scale: Double, x: Double, y: Double) -> Bool {
        ratio(literal) == nil && scale == 1 && x == 0 && y == 0
    }
}
