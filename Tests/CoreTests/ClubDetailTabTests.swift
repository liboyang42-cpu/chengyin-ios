import XCTest
@testable import QuestifyCore

final class ClubDetailTabTests: XCTestCase {
    private func policy(owner: Bool = false, joined: Bool = false, admin: Bool = false, grant: ClubDetailManageGrant? = nil) -> ClubDetailTabPolicy {
        .init(clubID: 9, isOwner: owner, isJoined: joined, viewerIsAdmin: admin, grant: grant)
    }
    private func permissions(_ values: [String], club: Int = 9, events: [ClubGovernanceValue] = []) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(club)]), "roleCodes": .array([]),
                                  "permissions": .array(values.map { .string($0) }), "canManageRoles": .bool(false), "eventAccesses": .array(events)]),
                  scope: .init(clubID: club))
    }

    func testPublicTabsAndOwnerOrAdminManageTab() {
        XCTAssertEqual(policy().tabs, [.posts, .events, .overview])
        XCTAssertEqual(policy(owner: true, joined: true).tabs, [.posts, .events, .overview, .manage])
        XCTAssertEqual(policy(joined: true, admin: true).tabs, [.posts, .events, .overview, .manage])
    }

    func testOwnersAndMembersDefaultToPostsGuestsToOverview() {
        XCTAssertEqual(policy(owner: true, joined: true).defaultTab, .posts)
        XCTAssertEqual(policy(joined: true).defaultTab, .posts)
        XCTAssertEqual(policy().defaultTab, .overview)
    }

    func testManageDeepLinkOnlyAfterServerConfirmedGovernance() {
        XCTAssertEqual(policy(owner: true, joined: true).initialTab(requested: .manage), .manage)
        XCTAssertEqual(policy().initialTab(requested: .manage), .overview)
        XCTAssertEqual(policy(owner: true, joined: true).initialTab(requested: nil), .posts)
    }

    func testSelectionIsIdempotentAndManageCannotBeForced() {
        XCTAssertEqual(policy().select(.events, from: .events), .events)
        XCTAssertEqual(policy().select(.manage, from: .events), .events)
        XCTAssertEqual(policy(owner: true).select(.manage, from: .events), .manage)
    }

    func testDelegatedPermissionOrEventScopeOpensManageTab() throws {
        XCTAssertFalse(ClubDetailManageGrant(try permissions(["club:read", "club:activity:read"])).allowsManage)
        for permission in ["club:write", "club:member:approve", "club:event:checkin", "club:finance:read", "club:notify:send"] {
            let grant = ClubDetailManageGrant(try permissions([permission]))
            XCTAssertEqual(policy(joined: true, grant: grant).tabs.last, .manage, permission)
        }
        let scoped = ClubDetailManageGrant(try permissions(["club:read"], events: [.object(["activityId": .integer(5), "topicId": .integer(6), "roleCodes": .array([.string("EVENT_CHECKIN")])])]))
        XCTAssertTrue(scoped.allowsManage)
    }

    func testRevokedOrForeignGrantFallsBackToLegacyFlags() throws {
        let foreign = ClubDetailManageGrant(try permissions(["club:write"], club: 10))
        XCTAssertNil(policy(joined: true, grant: foreign).grant)
        XCTAssertEqual(policy(joined: true, grant: foreign).tabs, ClubDetailTab.publicTabs)
        // A selected manage tab returns to the public default once the grant is gone.
        XCTAssertEqual(policy(joined: true).resolve(.manage), .posts)
        XCTAssertEqual(policy(admin: true).resolve(.manage), .manage)
        XCTAssertEqual(policy().resolve(nil), .overview)
    }

    func testOverviewFactsGridAndEnrollmentHeaderFormatting() {
        let grid = ClubDetailOverviewFactsGrid(leaderName: " 阿青 ", level: 4, city: " 杭州 ")
        XCTAssertEqual(grid.items.map(\.label), ["主理人", "等级", "所在城市"])
        XCTAssertEqual(grid.items.map(\.value), ["阿青", "L4", "杭州"])

        let fallbackGrid = ClubDetailOverviewFactsGrid(leaderName: " ", level: 0, city: nil)
        XCTAssertEqual(fallbackGrid.items.map(\.value), ["待补充", "待定", "待补充"])

        XCTAssertEqual(ClubEnrollmentReader.formatHeaderLine(clubName: "山野社", teamCount: 3), "山野社 · 3 个团")
        XCTAssertEqual(ClubEnrollmentReader.formatHeaderLine(clubName: "  ", teamCount: 2), "2 个团")
        XCTAssertEqual(ClubEnrollmentReader.formatPaymentRefundSummary(paidCount: 8, refundableCount: 5), "已支付 8 / 可退款 5")
        XCTAssertEqual(ClubEnrollmentReader.formatPaymentRefundSummary(paidCount: 8, refundableCount: nil), "已支付 8 / 可退款 待确认")
        XCTAssertEqual(ClubEnrollmentReader.failureTitle(for: .forbidden), "没有权限查看报名名册")
        XCTAssertEqual(ClubEnrollmentReader.failureTitle(for: .rejected(code: 403, message: nil)), "没有权限查看报名名册")
        XCTAssertNil(ClubEnrollmentReader.failureTitle(for: .signedOut))
    }
}
