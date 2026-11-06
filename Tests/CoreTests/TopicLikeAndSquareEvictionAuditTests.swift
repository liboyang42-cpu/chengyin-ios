import XCTest
@testable import QuestifyCore

final class TopicLikeAndSquareEvictionAuditTests: XCTestCase {
    func testImmediateURLCacheMediaEvictionOn404AndDeletedStatus() {
        let evicted404 = SquarePostMediaEvictionSample(
            postID: "post-404",
            httpStatusCode: 404,
            lifecycleStatus: "NOT_FOUND",
            attachedMediaURLs: [
                "https://cdn.example.com/square/post-404-a.jpg",
                "https://cdn.example.com/square/post-404-b.jpg"
            ],
            evictedFromURLCacheURLs: [
                "https://cdn.example.com/square/post-404-a.jpg",
                "https://cdn.example.com/square/post-404-b.jpg"
            ]
        )
        let evictedDeleted = SquarePostMediaEvictionSample(
            postID: "post-deleted",
            httpStatusCode: 200,
            lifecycleStatus: "DELETED",
            attachedMediaURLs: ["https://cdn.example.com/square/post-del.mp4"],
            evictedFromURLCacheURLs: ["https://cdn.example.com/square/post-del.mp4"]
        )

        let cleanReport = TopicLikeAndSquareEvictionAudit.audit(
            mediaEvictionSamples: [evicted404, evictedDeleted]
        )
        XCTAssertTrue(cleanReport.isCompliant)
        XCTAssertEqual(cleanReport.evictedMediaURLCount, 3)
        XCTAssertTrue(cleanReport.unevictedMediaByPostID.isEmpty)

        let leakedDeleted = SquarePostMediaEvictionSample(
            postID: "post-leak",
            httpStatusCode: 404,
            lifecycleStatus: "DELETED",
            attachedMediaURLs: [
                "https://cdn.example.com/square/leak-1.jpg",
                "https://cdn.example.com/square/leak-2.jpg"
            ],
            evictedFromURLCacheURLs: ["https://cdn.example.com/square/leak-1.jpg"]
        )
        let leakReport = TopicLikeAndSquareEvictionAudit.audit(
            mediaEvictionSamples: [leakedDeleted]
        )
        XCTAssertFalse(leakReport.isCompliant)
        XCTAssertEqual(
            leakReport.unevictedMediaByPostID["post-leak"],
            ["https://cdn.example.com/square/leak-2.jpg"]
        )
        XCTAssertEqual(
            leakReport.violations,
            [
                .unevictedMediaOnDeletedOrNotFoundPost(
                    postID: "post-leak",
                    urls: ["https://cdn.example.com/square/leak-2.jpg"]
                )
            ]
        )
    }

    func testBidirectionalTopicLikeDeltaCalculationAndFloorAtZero() {
        XCTAssertEqual(AuditedTopicLikeDirection.like.signedDelta, 1)
        XCTAssertEqual(AuditedTopicLikeDirection.unlike.signedDelta, -1)
        XCTAssertEqual(AuditedTopicLikeDirection.like.optimisticCount(from: 9), 10)
        XCTAssertEqual(AuditedTopicLikeDirection.unlike.optimisticCount(from: 9), 8)
        XCTAssertEqual(AuditedTopicLikeDirection.unlike.optimisticCount(from: 0), 0)

        let validLike = TopicLikeInteractionAuditSample(
            topicID: "topic-101",
            direction: .like,
            initialCount: 4,
            recordedDelta: 1,
            settledCount: 5,
            authoritativeServerCount: 5,
            revalidatedOnSettle: true
        )
        let validUnlike = TopicLikeInteractionAuditSample(
            topicID: "topic-101",
            direction: .unlike,
            initialCount: 5,
            recordedDelta: -1,
            settledCount: 4,
            authoritativeServerCount: 4,
            revalidatedOnSettle: true
        )

        let report = TopicLikeAndSquareEvictionAudit.audit(
            likeGrantEnabled: true,
            likeGrantApproved: true,
            dispatchedWriteCount: 2,
            likeInteractionSamples: [validLike, validUnlike]
        )
        XCTAssertTrue(report.isCompliant)
    }

    func testServerRevalidationOnSettleCatchesStaleOrMismatchedCounts() {
        let wrongDeltaAndUnrevalidated = TopicLikeInteractionAuditSample(
            topicID: "topic-bad-1",
            direction: .unlike,
            initialCount: 10,
            recordedDelta: 1,
            settledCount: 11,
            authoritativeServerCount: 9,
            revalidatedOnSettle: false
        )

        let report = TopicLikeAndSquareEvictionAudit.audit(
            likeGrantEnabled: true,
            likeGrantApproved: true,
            likeInteractionSamples: [wrongDeltaAndUnrevalidated]
        )
        XCTAssertFalse(report.isCompliant)
        XCTAssertEqual(
            report.violations,
            [
                .invalidBidirectionalLikeDelta(topicID: "topic-bad-1", expected: -1, actual: 1),
                .missingOrMismatchedServerRevalidationOnSettle(topicID: "topic-bad-1")
            ]
        )
    }

    func testDefaultFailClosedTopicLikeWriteGateEnforcement() {
        XCTAssertEqual(TopicLikeAndSquareEvictionAudit.topicLikeRoute, "/api/topic/like")

        let defaultReport = TopicLikeAndSquareEvictionAudit.audit()
        XCTAssertTrue(defaultReport.isCompliant)
        XCTAssertFalse(defaultReport.likeGrantEnabled)
        XCTAssertFalse(defaultReport.likeGrantApproved)

        let unapprovedGrantReport = TopicLikeAndSquareEvictionAudit.audit(
            likeGrantEnabled: true,
            likeGrantApproved: false
        )
        XCTAssertFalse(unapprovedGrantReport.isCompliant)
        XCTAssertEqual(unapprovedGrantReport.violations, [.unapprovedTopicLikeGrantEnabled])

        let bypassedGateReport = TopicLikeAndSquareEvictionAudit.audit(
            likeGrantEnabled: false,
            likeGrantApproved: false,
            dispatchedWriteCount: 1
        )
        XCTAssertFalse(bypassedGateReport.isCompliant)
        XCTAssertEqual(bypassedGateReport.violations, [.topicLikeWriteDispatchedWhileGateDisabled])
    }
}
