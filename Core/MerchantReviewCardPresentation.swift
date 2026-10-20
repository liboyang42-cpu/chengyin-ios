import Foundation

/// Read-only status projection of one already validated merchant review row.
/// It never grants a write capability: reply/report/edit remain governed by the
/// server `canReply`/`canReport`/`canEditReply` flags and the existing mutation gate.
public struct MerchantReviewCardPresentation: Equatable {
    public enum Visibility: String, Equatable { case publicVisible, pendingReview, hidden, unknown }
    public enum ReplyState: String, Equatable { case replied, awaitingReply, noReplyAvailable }

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

    public var visibilityTitle: String {
        switch visibility {
        case .publicVisible: return "公开展示"
        case .pendingReview: return "审核中（暂未公开）"
        case .hidden: return "已隐藏（未公开）"
        case .unknown: return "可见性未知（不按公开处理）"
        }
    }
    public var replyTitle: String {
        switch replyState {
        case .replied: return "已回复"
        case .awaitingReply: return "待回复"
        case .noReplyAvailable: return "不可回复"
        }
    }
}
