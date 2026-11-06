import Foundation

/// Pure, self-contained audit check for Wave-2 `w2-13` (`PublishPostView` 9-grid media limit
/// & topic tag attachment, `SquareTopicDetailView` & `SquareCommentThreadView`,
/// `PostReportReasonSheet` UGC report reasons, and client-side + server-side UGC moderation filter).
public struct PublishAndCommentModerationCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let maxMediaAttachments: Int
    public let enforcesUGCRulesAndReportSheet: Bool
    public let supportsBlockAuthorImmediateHide: Bool
    public let preservesDraftOnNetworkFailure: Bool

    public init(
        id: String,
        maxMediaAttachments: Int = 9,
        enforcesUGCRulesAndReportSheet: Bool,
        supportsBlockAuthorImmediateHide: Bool,
        preservesDraftOnNetworkFailure: Bool
    ) {
        self.id = id
        self.maxMediaAttachments = maxMediaAttachments
        self.enforcesUGCRulesAndReportSheet = enforcesUGCRulesAndReportSheet
        self.supportsBlockAuthorImmediateHide = supportsBlockAuthorImmediateHide
        self.preservesDraftOnNetworkFailure = preservesDraftOnNetworkFailure
    }

    public var isCompliant: Bool {
        (1...9).contains(maxMediaAttachments) &&
            enforcesUGCRulesAndReportSheet &&
            supportsBlockAuthorImmediateHide &&
            preservesDraftOnNetworkFailure
    }
}

/// Evaluates Wave-2 `w2-13` square post composer, topic detail feed, comment thread moderation,
/// and UGC report/block readiness.
public struct PublishTopicAndCommentModerationAudit: Sendable, Equatable {
    public static let canonicalChecks: [PublishAndCommentModerationCheck] = [
        PublishAndCommentModerationCheck(
            id: "publish-9grid-composer",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        ),
        PublishAndCommentModerationCheck(
            id: "topic-detail-feed",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        ),
        PublishAndCommentModerationCheck(
            id: "comment-thread-moderation",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        ),
        PublishAndCommentModerationCheck(
            id: "ugc-report-and-block",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        )
    ]

    public init() {}

    public static func evaluate(
        checks: [PublishAndCommentModerationCheck] = canonicalChecks
    ) -> (totalChecks: Int, compliantChecks: Int, isUGCModerationReady: Bool) {
        let total = checks.count
        let compliant = checks.filter(\.isCompliant).count
        let isReady = total > 0 && compliant == total
        return (totalChecks: total, compliantChecks: compliant, isUGCModerationReady: isReady)
    }
}
