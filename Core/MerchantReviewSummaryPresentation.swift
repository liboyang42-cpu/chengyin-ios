import Foundation

/// Mini-program pages/merchant/reviews summary (index.wxml:31-77, view-model.js:140-151).
/// The source page shows missing numbers as 0; this client keeps its stricter rule that a
/// missing server metric is unknown (nil, rendered as a dash), never a guessed zero.
public struct MerchantReviewSummaryPresentation: Equatable {
    /// "1.0"..."5.0", or nil when the server omitted the average.
    public let averageText: String?
    /// 0...5, half-up rounding of a valid average.
    public let filledStars: Int
    public let total: Int
    public let pendingReplyCount: Int?
    public let monthNewCount: Int?
    public let replyRatePct: Int?

    public init?(document: MerchantBusinessDocument) {
        guard case .reviews = document.query else { return nil }
        let rating = document.summary["averageRating"]?.numberText.flatMap { Double($0) }
        if let rating, rating.isFinite, (1...5).contains(rating) {
            averageText = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rating)
            filledStars = Int(rating.rounded(.toNearestOrAwayFromZero))
        } else {
            averageText = nil; filledStars = 0
        }
        func count(_ key: String) -> Int? { document.summary[key]?.integer.flatMap { $0 >= 0 ? $0 : nil } }
        total = max(0, document.total ?? 0)
        pendingReplyCount = count("pendingReplyCount")
        monthNewCount = count("monthNewCount")
        replyRatePct = count("replyRatePct").flatMap { $0 <= 100 ? $0 : nil }
    }
}
