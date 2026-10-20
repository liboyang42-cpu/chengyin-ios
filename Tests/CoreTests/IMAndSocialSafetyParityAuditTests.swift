import XCTest
@testable import QuestifyCore

final class IMAndSocialSafetyParityAuditTests: XCTestCase {
    func testAllFourPillarsPassByDefault() {
        let report = IMAndSocialSafetyParityAudit.evaluate()
        XCTAssertTrue(report.isAllCompliant)
        XCTAssertEqual(report.compliantPillars, SocialAndIMPillar.allCases)
        XCTAssertTrue(report.failingPillars.isEmpty)
    }

    func testMemberHomeProfileTabsAndIncompleteLinkKeyValidation() {
        let valid = MemberHomeSocialPillarAudit()
        XCTAssertTrue(valid.isCompliant)
        XCTAssertEqual(MemberHomeSocialPillarAudit.canonicalTabTitles, ["我的", "推文", "成就", "关于"])
        XCTAssertEqual(MemberHomeSocialPillarAudit.expectedIncompleteLinkKey, "social.incompleteLink")

        let wrongTabs = MemberHomeSocialPillarAudit(
            tabTitles: ["我的", "推文", "关于"],
            balancePreviewText: "100",
            incompleteLinkLocalizationKey: "social.incompleteLink"
        )
        XCTAssertFalse(wrongTabs.isCompliant)

        let report = IMAndSocialSafetyParityAudit.evaluate(memberHome: wrongTabs)
        XCTAssertFalse(report.isAllCompliant)
        XCTAssertEqual(report.failingPillars, [.memberHomeAndSocial])
    }

    func testGrowthBadgeAvatarFallbackAndForbiddenSeparationValidation() {
        let avatar = GrowthLeaderboardAvatarBadge(nickname: "  ")
        let validGrowth = GrowthAndBadgesPillarAudit(
            blankNicknameAvatarMonogram: avatar.monogram,
            usesFormEncodedLeaderboardRequest: true,
            preservesServerLeaderboardStanding: true,
            distinguishesForbiddenFromUnauthorized: GrowthCenterIssue(APIError.httpStatus(403)) == .denied
        )
        XCTAssertTrue(validGrowth.isCompliant)

        let invalidGrowth = GrowthAndBadgesPillarAudit(
            blankNicknameAvatarMonogram: "?",
            usesFormEncodedLeaderboardRequest: false,
            preservesServerLeaderboardStanding: true,
            distinguishesForbiddenFromUnauthorized: false
        )
        XCTAssertFalse(invalidGrowth.isCompliant)

        let report = IMAndSocialSafetyParityAudit.evaluate(growthBadges: invalidGrowth)
        XCTAssertFalse(report.isAllCompliant)
        XCTAssertEqual(report.failingPillars, [.growthBadgesAndStamps])
    }

    func testSquarePrivacyCacheEvictionAndTopicLikeDefaultOffGate() {
        let defaultSquare = SquarePrivacyAndLikePillarAudit()
        XCTAssertTrue(defaultSquare.isCompliant)
        XCTAssertFalse(defaultSquare.defaultLikeGrantEnabled)

        let unsafeLikeGate = SquarePrivacyAndLikePillarAudit(
            evictsMediaCacheOn404AndDeleted: true,
            supportsBidirectionalTopicLike: true,
            defaultLikeGrantEnabled: true
        )
        XCTAssertFalse(unsafeLikeGate.isCompliant)

        let missingCacheEviction = SquarePrivacyAndLikePillarAudit(
            evictsMediaCacheOn404AndDeleted: false,
            supportsBidirectionalTopicLike: true,
            defaultLikeGrantEnabled: false
        )
        XCTAssertFalse(missingCacheEviction.isCompliant)

        let report = IMAndSocialSafetyParityAudit.evaluate(squarePrivacy: unsafeLikeGate)
        XCTAssertFalse(report.isAllCompliant)
        XCTAssertEqual(report.failingPillars, [.squarePrivacyAndLikes])
    }

    func testIMInboxAndConversationSafetyReportBlockMuteGates() {
        let validIM = IMInboxAndSafetyPillarAudit()
        XCTAssertTrue(validIM.isCompliant)

        let missingBlockGate = IMInboxAndSafetyPillarAudit(
            inboxTabsConfigured: true,
            supportsReportAction: true,
            supportsBlockAction: false,
            supportsMuteAction: true,
            hidesBlockedSenderMessagesImmediately: true
        )
        XCTAssertFalse(missingBlockGate.isCompliant)

        let report = IMAndSocialSafetyParityAudit.evaluate(imSafety: missingBlockGate)
        XCTAssertFalse(report.isAllCompliant)
        XCTAssertEqual(report.failingPillars, [.imInboxAndSafety])
    }
}
