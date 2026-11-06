import XCTest
@testable import QuestifyCore

final class PublishTopicAndCommentModerationAuditTests: XCTestCase {
    func testCanonicalChecksPassUGCModerationReadiness() {
        let checks = PublishTopicAndCommentModerationAudit.canonicalChecks
        XCTAssertEqual(checks.map(\.id), [
            "publish-9grid-composer",
            "topic-detail-feed",
            "comment-thread-moderation",
            "ugc-report-and-block"
        ])
        XCTAssertTrue(checks.allSatisfy(\.isCompliant))

        let result = PublishTopicAndCommentModerationAudit.evaluate()
        XCTAssertEqual(result.totalChecks, 4)
        XCTAssertEqual(result.compliantChecks, 4)
        XCTAssertTrue(result.isUGCModerationReady)
    }

    func testMaxMediaAttachmentsExceedingNineOrBelowOneIsRejected() {
        let overLimit = PublishAndCommentModerationCheck(
            id: "publish-9grid-composer",
            maxMediaAttachments: 10,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        )
        let zeroLimit = PublishAndCommentModerationCheck(
            id: "topic-detail-feed",
            maxMediaAttachments: 0,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        )
        XCTAssertFalse(overLimit.isCompliant)
        XCTAssertFalse(zeroLimit.isCompliant)

        var checks = PublishTopicAndCommentModerationAudit.canonicalChecks
        checks[0] = overLimit
        let result = PublishTopicAndCommentModerationAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalChecks, 4)
        XCTAssertEqual(result.compliantChecks, 3)
        XCTAssertFalse(result.isUGCModerationReady)
    }

    func testMissingUGCReportOrBlockAuthorImmediateHideFailsCompliance() {
        let missingReport = PublishAndCommentModerationCheck(
            id: "comment-thread-moderation",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: false,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: true
        )
        let missingBlockHide = PublishAndCommentModerationCheck(
            id: "ugc-report-and-block",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: false,
            preservesDraftOnNetworkFailure: true
        )
        XCTAssertFalse(missingReport.isCompliant)
        XCTAssertFalse(missingBlockHide.isCompliant)

        let result = PublishTopicAndCommentModerationAudit.evaluate(checks: [missingReport, missingBlockHide])
        XCTAssertEqual(result.totalChecks, 2)
        XCTAssertEqual(result.compliantChecks, 0)
        XCTAssertFalse(result.isUGCModerationReady)
    }

    func testDraftPreservationFailureOnNetworkErrorIsDetected() {
        var checks = PublishTopicAndCommentModerationAudit.canonicalChecks
        checks[0] = PublishAndCommentModerationCheck(
            id: "publish-9grid-composer",
            maxMediaAttachments: 9,
            enforcesUGCRulesAndReportSheet: true,
            supportsBlockAuthorImmediateHide: true,
            preservesDraftOnNetworkFailure: false
        )

        XCTAssertFalse(checks[0].isCompliant)
        let result = PublishTopicAndCommentModerationAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalChecks, 4)
        XCTAssertEqual(result.compliantChecks, 3)
        XCTAssertFalse(result.isUGCModerationReady)

        let emptyResult = PublishTopicAndCommentModerationAudit.evaluate(checks: [])
        XCTAssertFalse(emptyResult.isUGCModerationReady)
    }
}
