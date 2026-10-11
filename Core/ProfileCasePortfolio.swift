import Foundation

/// Presentation projection only. The original casePics wire value is never reserialized.
public struct ProfileCasePortfolio {
    public let images: [String]
    public let omittedImageCount: Int
    /// Includes references beyond the preview cap; bulk removal always means all.
    public var imageCount: Int { images.count + omittedImageCount }
    public init(casePics: String) {
        // Mini excludes blank entries but retains each nonblank value and duplicate position.
        let values = casePics.split(separator: ";", omittingEmptySubsequences: false)
            .map(String.init).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        images = Array(values.prefix(100))
        omittedImageCount = max(0, values.count - images.count)
    }
    /// Missing, empty and different Unicode byte representations are distinct.
    public static func sameText(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (.some(lhs), .some(rhs)): return lhs.utf8.elementsEqual(rhs.utf8)
        default: return false
        }
    }
}
