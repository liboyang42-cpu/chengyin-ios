import Foundation

/// Read-only status projection of one already validated merchant review row.
/// It never grants a write capability: reply/report/edit remain governed by the
/// server `canReply`/`canReport`/`canEditReply` flags and the existing mutation gate.
public struct MerchantReviewCardPresentation: Equatable {
    public static let localizationTableName = "MerchantReviewAndCustomerDetail"
    public static let verifiedRedemptionKey = "merchant.review.verifiedRedemption"
    public static let photoCountFormatKey = "merchant.review.photoCount %lld"

    public enum Visibility: String, Equatable, CaseIterable {
        case publicVisible, pendingReview, hidden, unknown
        public var titleKey: String { "merchant.review.visibility." + rawValue }
    }
    public enum ReplyState: String, Equatable, CaseIterable {
        case replied, awaitingReply, noReplyAvailable
        public var titleKey: String { "merchant.review.reply." + rawValue }
    }

    public let visibility: Visibility
    public let replyState: ReplyState
    public let rating: Int?
    public let verifiedRedemption: Bool
    public let photoCount: Int

    public init?(row: MerchantBusinessRecord) {
        guard row.kind == .review else { return nil }
        // Only the exact server literal VISIBLE is public; anything else is never guessed public.
        switch row.fields.mbText("status") {
        case "VISIBLE": visibility = .publicVisible
        case "PENDING_REVIEW": visibility = .pendingReview
        case "HIDDEN": visibility = .hidden
        default: visibility = .unknown
        }
        if row.fields.mbText("merchantReply") != nil { replyState = .replied }
        else if row.fields["canReply"]?.bool == true { replyState = .awaitingReply }
        else { replyState = .noReplyAvailable }
        rating = row.fields["rating"]?.integer
        verifiedRedemption = row.fields["verifiedRedemption"]?.bool == true
        photoCount = row.fields["imageUrls"]?.array?.count ?? 0
    }

    public var visibilityTitleKey: String { visibility.titleKey }
    public var replyTitleKey: String { replyState.titleKey }
    public var visibilityTitle: String { visibilityTitleKey }
    public var replyTitle: String { replyTitleKey }
}
