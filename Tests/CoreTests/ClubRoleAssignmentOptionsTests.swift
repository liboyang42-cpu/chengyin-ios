import XCTest
@testable import QuestifyCore

final class ClubRoleAssignmentOptionsTests: XCTestCase {
    private func scope(_ activity: Int? = nil) -> ClubGovernanceScope { .init(clubID: 81, activityID: activity) }
    private func context(_ activity: Int? = nil) -> ClubGovernanceReadContext {
        .init(operation: .roles, scope: scope(activity), identity: .init(accountID: 701, epoch: 1), viewerRevision: 0, authorizationGeneration: nil)
    }
    private func permissions(_ activity: Int?, allowed: Bool = true) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([.string("CLUB_OWNER")]),
            "permissions": .array([]), "canManageRoles": .bool(allowed)]), scope: scope(activity))
    }
    private func role(_ code: String, kind: String) -> ClubGovernanceValue {
        .object(["roleCode": .string(code), "scopeType": .string(kind), "name": .string(code), "permissions": .array([])])
    }
    private func definitions() -> [ClubGovernanceValue] {
        [role("CLUB_OPERATOR", kind: "CLUB"), role("EVENT_CHECKIN", kind: "EVENT"),
         role("CLUB_CO_OWNER", kind: "CLUB"), role("EVENT_LEAD", kind: "EVENT")]
    }
    private func member(_ id: Int, owner: ClubGovernanceValue = .bool(false), name: String = " Member ") -> ClubGovernanceValue {
        .object(["id": .integer(id + 1000), "memberId": .integer(id), "isOwner": owner, "nickname": .string(name)])
    }
    private func snapshots(_ activity: Int? = nil, definitions: [ClubGovernanceValue]? = nil, rows: [ClubGovernanceValue]? = nil,
                           rolePermission: Bool = true, memberPermission: Bool = true) throws -> (ClubGovernanceSnapshot, ClubGovernanceSnapshot) {
        let roles = ClubGovernanceSnapshot(operation: .roles, scope: scope(activity), permissions: try permissions(activity, allowed: rolePermission),
            value: .object(["roles": .array(definitions ?? self.definitions()), "assignments": .array([])]))
        let members = ClubGovernanceSnapshot(operation: .members, scope: scope(activity), permissions: try permissions(activity, allowed: memberPermission),
            value: .array(rows ?? [member(7, owner: .bool(true)), member(41), member(42, owner: .null), member(43, name: "  ")]))
        return (roles, members)
    }
    private func options(_ activity: Int? = nil, definitions: [ClubGovernanceValue]? = nil, rows: [ClubGovernanceValue]? = nil) throws -> ClubRoleAssignmentOptions {
        let (roles, members) = try snapshots(activity, definitions: definitions, rows: rows)
        return try .init(roles: roles, members: members, context: context(activity))
    }
    func testClubRolesComeFromReturnedDefinitionsInSourceOrder() throws {
        let result = try options()
        XCTAssertEqual(result.roles.map(\.code), ["CLUB_OPERATOR", "CLUB_CO_OWNER"])
        XCTAssertEqual(result.roles[0].name, "CLUB_OPERATOR")
        XCTAssertEqual(result.roles[0].summaryKey, "club.rolePicker.summary.CLUB_OPERATOR")
    }
    func testEventRolesCannotLeakClubAuthority() throws {
        let result = try options(205)
        XCTAssertEqual(result.roles.map(\.code), ["EVENT_CHECKIN", "EVENT_LEAD"])
        XCTAssertEqual(result.scope.activityID, 205)
        XCTAssertFalse(result.contains(memberID: 41, roleCode: "CLUB_CO_OWNER"))
    }
    func testOwnersAndUnverifiedOwnershipAreNotAssignable() throws {
        let result = try options()
        XCTAssertEqual(result.members.map(\.id), [41, 43]); XCTAssertTrue(result.hasUnverifiedMembers)
        XCTAssertEqual(result.members[0].nickname, "Member"); XCTAssertNil(result.members[1].nickname)
        XCTAssertFalse(result.contains(memberID: 7, roleCode: "CLUB_OPERATOR"))
        XCTAssertFalse(result.contains(memberID: 42, roleCode: "CLUB_OPERATOR"))
    }
    func testOnlyMemberIDIsUsedAndForgedOrMissingSelectionIsRejected() throws {
        let result = try options()
        XCTAssertTrue(result.contains(memberID: 41, roleCode: "CLUB_OPERATOR"))
        XCTAssertFalse(result.contains(memberID: 1041, roleCode: "CLUB_OPERATOR"))
        XCTAssertFalse(result.contains(memberID: nil, roleCode: "CLUB_OPERATOR"))
        XCTAssertFalse(result.contains(memberID: 41, roleCode: ""))
        XCTAssertFalse(result.contains(memberID: 41, roleCode: "SUPER_ADMIN"))
    }
    func testRoleDefinitionMustExistAndMatchExactScope() throws {
        XCTAssertThrowsError(try options(definitions: []))
        XCTAssertThrowsError(try options(definitions: [role("CLUB_OPERATOR", kind: "EVENT")]))
        XCTAssertThrowsError(try options(205, definitions: [role("CLUB_OPERATOR", kind: "CLUB")]))
        let filtered = try options(definitions: [role("UNSUPPORTED", kind: "CLUB"), role("CLUB_OPERATOR", kind: "CLUB")])
        XCTAssertEqual(filtered.roles.count, 1)
    }
    func testDuplicateRoleCodesAndMemberIDsFail() throws {
        let duplicate = role("CLUB_OPERATOR", kind: "CLUB")
        XCTAssertThrowsError(try options(definitions: [duplicate, duplicate]))
        XCTAssertThrowsError(try options(rows: [member(41), member(41, owner: .bool(true))]))
    }
    func testMalformedMemberAndDefinitionCannotBecomeEmptySuccess() throws {
        XCTAssertThrowsError(try options(rows: [.null]))
        XCTAssertThrowsError(try options(rows: [.object(["id": .integer(41), "isOwner": .bool(false)])]))
        XCTAssertThrowsError(try options(definitions: [.object(["roleCode": .string("CLUB_OPERATOR"), "scopeType": .string("CLUB"), "name": .string(""), "permissions": .array([])])]))
        let unknown = try options(rows: [member(41, owner: .string("false"))])
        XCTAssertTrue(unknown.members.isEmpty); XCTAssertTrue(unknown.hasUnverifiedMembers)
    }
    func testBothReadSnapshotsNeedCurrentRoleManagementPermission() throws {
        for pair in [(false, true), (true, false)] {
            let (roles, members) = try snapshots(rolePermission: pair.0, memberPermission: pair.1)
            XCTAssertThrowsError(try ClubRoleAssignmentOptions(roles: roles, members: members, context: context()))
        }
    }
    func testWrongScopeOperationAndCrossClubMemberFail() throws {
        let (roles, members) = try snapshots()
        XCTAssertThrowsError(try ClubRoleAssignmentOptions(roles: roles, members: members, context: context(205)))
        XCTAssertThrowsError(try ClubRoleAssignmentOptions(roles: members, members: roles, context: context()))
        XCTAssertThrowsError(try options(rows: [.object(["memberId": .integer(41), "clubId": .integer(82), "isOwner": .bool(false)])]))
    }
    func testGenuineEmptyAssignableRosterIsNotAnError() throws {
        let result = try options(rows: [member(7, owner: .bool(true))])
        XCTAssertTrue(result.members.isEmpty); XCTAssertFalse(result.hasUnverifiedMembers); XCTAssertEqual(result.roles.count, 2)
    }
    func testChosenOptionsProduceExistingExactAssignmentCommandWithoutNewFields() throws {
        let result = try options(205)
        XCTAssertTrue(result.contains(memberID: 41, roleCode: "EVENT_LEAD"))
        var draft = ClubGovernanceFormDraft(operation: .assignRole, scope: result.scope)
        draft.text["targetMemberId"] = "41"; draft.text["roleCode"] = "EVENT_LEAD"
        let command = try draft.command()
        XCTAssertEqual(command.operation, .assignRole); XCTAssertEqual(command.fields["targetMemberId"], .integer(41))
        XCTAssertEqual(command.fields["roleCode"], .string("EVENT_LEAD")); XCTAssertEqual(command.fields["activityId"], .integer(205))
        XCTAssertEqual(command.operation.permission, "ROLES")
    }
}
