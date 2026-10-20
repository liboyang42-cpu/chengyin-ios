@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class TopicLikeAndSquareEvictionSectionViewTests: XCTestCase {
    func testDefaultSnapshotEnforcesMediaCacheEvictionAndFailClosedLikeGate() {
        let view = TopicLikeAndSquareEvictionSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.evictsCacheOn404)
        XCTAssertTrue(view.snapshot.evictsCacheOnDeletedStatus)
        XCTAssertFalse(view.snapshot.likeGrantEnabled)
        XCTAssertTrue(view.snapshot.preservesServerLikeDirectionEcho)
        XCTAssertTrue(view.snapshot.hasCanonicalRules)
        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(
            view.snapshot.rows.map(\.ruleID),
            [
                "Square404MediaEviction",
                "SquareDeletedPostEviction",
                "TopicLikeFailClosedGate",
                "TopicLikeDirectionEcho"
            ]
        )
        XCTAssertTrue(view.statusHeadline.contains("I05"))
    }

    func testEnabledLikeGrantViolatesFailClosedDefault() {
        let unlockedLikeSnapshot = TopicLikeAndSquareEvictionSnapshot(
            evictsCacheOn404: true,
            evictsCacheOnDeletedStatus: true,
            likeGrantEnabled: true,
            preservesServerLikeDirectionEcho: true
        )
        let view = TopicLikeAndSquareEvictionSectionView(snapshot: unlockedLikeSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertFalse(view.snapshot.rows[2].isEnforced)
        XCTAssertTrue(view.statusHeadline.contains("likeGrantEnabled"))
    }

    func testMissing404OrDeletedMediaEvictionReportsViolation() {
        let missing404Eviction = TopicLikeAndSquareEvictionSnapshot(
            evictsCacheOn404: false,
            evictsCacheOnDeletedStatus: true,
            likeGrantEnabled: false,
            preservesServerLikeDirectionEcho: true
        )
        let view404 = TopicLikeAndSquareEvictionSectionView(snapshot: missing404Eviction)
        _ = view404.body

        XCTAssertFalse(view404.snapshot.isAllCompliant)
        XCTAssertFalse(view404.snapshot.rows[0].isEnforced)
        XCTAssertTrue(view404.statusHeadline.contains("I05"))

        let missingDeletedEviction = TopicLikeAndSquareEvictionSnapshot(
            evictsCacheOn404: true,
            evictsCacheOnDeletedStatus: false,
            likeGrantEnabled: false,
            preservesServerLikeDirectionEcho: true
        )
        let viewDeleted = TopicLikeAndSquareEvictionSectionView(snapshot: missingDeletedEviction)
        _ = viewDeleted.body

        XCTAssertFalse(viewDeleted.snapshot.isAllCompliant)
        XCTAssertFalse(viewDeleted.snapshot.rows[1].isEnforced)
        XCTAssertTrue(viewDeleted.statusHeadline.contains("DELETED"))
    }
}
