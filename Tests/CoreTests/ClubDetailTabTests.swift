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
}
