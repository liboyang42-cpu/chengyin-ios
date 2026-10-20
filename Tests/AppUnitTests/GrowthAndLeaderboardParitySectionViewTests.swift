import XCTest
import SwiftUI
@testable import QuestifyApp
import QuestifyCore

@MainActor
final class GrowthAndLeaderboardParitySectionViewTests: XCTestCase {

    func testDefaultSnapshotAndViewInstantiation() {
        let snapshot = GrowthAndLeaderboardParitySnapshot()
        XCTAssertEqual(snapshot.badgeParitySpecID, "w2-10")
        XCTAssertEqual(snapshot.leaderboardSpecID, "I07")
        XCTAssertTrue(snapshot.isFormEncodingCompliant)
        XCTAssertEqual(snapshot.badges.count, 2)
        XCTAssertEqual(snapshot.rows.count, 2)

        let view = GrowthAndLeaderboardParitySectionView(snapshot: snapshot)
        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body
    }

    func testAnonymousMonogramFallbackAndAvatarResolution() {
        let normalRow = GrowthLeaderboardAuditRow(
            id: "r1",
            rank: 1,
            memberID: 1001,
            nickname: "林深见鹿",
            avatarURL: "https://cdn.questify.com/avatars/1001.png",
            scoreText: "2,480 pt",
            badgeTitle: "城市拓荒者",
            isAnonymous: false
        )
        XCTAssertTrue(normalRow.usesRemoteAvatar)
        XCTAssertEqual(normalRow.resolvedAvatarMonogram, "林")

        let missingAvatarRow = GrowthLeaderboardAuditRow(
            id: "r2",
            rank: 2,
            memberID: 1002,
            nickname: "青川",
            avatarURL: nil,
            scoreText: "2,100 pt",
            badgeTitle: nil,
            isAnonymous: false
        )
        XCTAssertFalse(missingAvatarRow.usesRemoteAvatar)
        XCTAssertEqual(missingAvatarRow.resolvedAvatarMonogram, "匿")

        let anonymousRow = GrowthLeaderboardAuditRow(
            id: "r3",
            rank: 3,
            memberID: 1003,
            nickname: "青川",
            avatarURL: "https://cdn.questify.com/avatars/1003.png",
            scoreText: "1,980 pt",
            badgeTitle: nil,
            isAnonymous: true
        )
        XCTAssertFalse(anonymousRow.usesRemoteAvatar)
        XCTAssertEqual(anonymousRow.resolvedAvatarMonogram, "匿")
    }

    func test403Vs401AuthSeparationAndFormEncodingCompliance() {
        let forbidden403Snapshot = GrowthAndLeaderboardParitySnapshot(
            authSeparationState: .forbiddenScopeRestricted403,
            preservesSessionOn403: true
        )
        XCTAssertTrue(forbidden403Snapshot.preservesSessionOn403)
        XCTAssertTrue(forbidden403Snapshot.statusBannerText.contains("403"))
        XCTAssertTrue(forbidden403Snapshot.statusBannerText.contains("保持登录态"))

        let unauthorized401Snapshot = GrowthAndLeaderboardParitySnapshot(
            authSeparationState: .unauthorizedReauthRequired401,
            preservesSessionOn403: true
        )
        XCTAssertTrue(unauthorized401Snapshot.statusBannerText.contains("401"))
        XCTAssertTrue(unauthorized401Snapshot.statusBannerText.contains("重新认证"))

        let invalidJsonBodySnapshot = GrowthAndLeaderboardParitySnapshot(
            formEncodedContentType: "application/json",
            formEncodedBodyPreview: "{\"type\":\"CITY_SCORE\"}"
        )
        XCTAssertFalse(invalidJsonBodySnapshot.isFormEncodingCompliant)

        let forbiddenView = GrowthAndLeaderboardParitySectionView(snapshot: forbidden403Snapshot)
        _ = forbiddenView.body
    }
}
