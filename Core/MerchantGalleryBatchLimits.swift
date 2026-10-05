import Foundation

/// Ephemeral sanitized selection budget; no source image bytes or URLs are persisted.
public enum MerchantGalleryBatchLimits {
    public static let maximumRetainedBytes = 24 * 1024 * 1024
    public static func remaining(currentCount: Int) -> Int { (0...9).contains(currentCount) ? 9 - currentCount : 0 }
    public static func accepts(_ images: [RetainedSelectedImage], currentCount: Int) -> Bool {
        guard !images.isEmpty, images.count <= remaining(currentCount: currentCount),
              Set(images.map(\.id)).count == images.count else { return false }
        var total = 0
        for image in images {
            guard image.jpeg.count <= maximumRetainedBytes - total else { return false }
            total += image.jpeg.count
        }
        return true
    }
}
