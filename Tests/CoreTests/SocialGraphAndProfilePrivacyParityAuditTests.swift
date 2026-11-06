import XCTest
@testable import QuestifyCore

final class SocialGraphAndProfilePrivacyParityAuditTests: XCTestCase {
    func testCanonicalDescriptorsPassSocialProfileParity() {
        let result = SocialGraphAndProfilePrivacyParityAudit.verifyParity()
        XCTAssertEqual(result.totalTickets, 2)
        XCTAssertEqual(result.compliantTickets, 2)
        XCTAssertTrue(result.allTabsCovered)
        XCTAssertTrue(result.isSocialProfileReady)
        XCTAssertEqual(
            SocialGraphAndProfilePrivacyParityAudit.canonicalDescriptors.map(\.ticketID),
            ["w2-06", "w2-07"]
        )
    }

    func testMissingSocialRelationshipTabFailsCompliance() {
        let missingBlacklist = SocialAndProfileParityDescriptor(
            id: "social-missing-blacklist",
            ticketID: "w2-07",
            supportedTabs: [.following, .followers, .friends],
            supportedVisibilityScopes: ProfileVisibilityScopeKind.allCases,
            supportsSelfProfileSaveRoundtrip: true,
            supportsBlockAndUnblockMutation: true
        )
        XCTAssertFalse(missingBlacklist.isCompliant)

        let result = SocialGraphAndProfilePrivacyParityAudit.verifyParity(
            descriptors: [SocialGraphAndProfilePrivacyParityAudit.canonicalDescriptors[0], missingBlacklist]
        )
        XCTAssertEqual(result.totalTickets, 2)
        XCTAssertEqual(result.compliantTickets, 1)
        XCTAssertFalse(result.allTabsCovered)
        XCTAssertFalse(result.isSocialProfileReady)
    }

    func testMissingProfileVisibilityScopeFailsCompliance() {
        let missingFriendsOnlyScope = SocialAndProfileParityDescriptor(
            id: "profile-missing-friends-only",
            ticketID: "w2-07",
            supportedTabs: SocialRelationshipTabKind.allCases,
            supportedVisibilityScopes: [.publicScope, .privateScope],
            supportsSelfProfileSaveRoundtrip: true,
            supportsBlockAndUnblockMutation: true
        )
        XCTAssertFalse(missingFriendsOnlyScope.isCompliant)

        let result = SocialGraphAndProfilePrivacyParityAudit.verifyParity(
            descriptors: [missingFriendsOnlyScope]
        )
        XCTAssertEqual(result.compliantTickets, 0)
        XCTAssertTrue(result.allTabsCovered)
        XCTAssertFalse(result.isSocialProfileReady)
    }

    func testSelfProfileSaveRoundtripAndBlockMutationAreEnforced() {
        let noSaveRoundtrip = SocialAndProfileParityDescriptor(
            id: "profile-no-save",
            ticketID: "w2-06",
            supportedTabs: SocialRelationshipTabKind.allCases,
            supportedVisibilityScopes: ProfileVisibilityScopeKind.allCases,
            supportsSelfProfileSaveRoundtrip: false,
            supportsBlockAndUnblockMutation: true
        )
        let noBlockMutation = SocialAndProfileParityDescriptor(
            id: "social-no-block",
            ticketID: "w2-07",
            supportedTabs: SocialRelationshipTabKind.allCases,
            supportedVisibilityScopes: ProfileVisibilityScopeKind.allCases,
            supportsSelfProfileSaveRoundtrip: true,
            supportsBlockAndUnblockMutation: false
        )
        XCTAssertFalse(noSaveRoundtrip.isCompliant)
        XCTAssertFalse(noBlockMutation.isCompliant)

        let result = SocialGraphAndProfilePrivacyParityAudit.verifyParity(
            descriptors: [noSaveRoundtrip, noBlockMutation]
        )
        XCTAssertEqual(result.totalTickets, 2)
        XCTAssertEqual(result.compliantTickets, 0)
        XCTAssertFalse(result.isSocialProfileReady)
    }
}
