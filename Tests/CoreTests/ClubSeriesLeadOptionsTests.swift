import XCTest
@testable import QuestifyCore

final class ClubSeriesLeadOptionsTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    private func context(_ scope: ClubGovernanceScope? = nil, identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)) -> ClubGovernanceReadContext {
        .init(operation: .members, scope: scope ?? self.scope, identity: identity, viewerRevision: 0, authorizationGeneration: nil)
    }
    private func row(_ id: Int, name: String = " Member ", owner: ClubGovernanceValue = .null) -> ClubGovernanceValue {
        .object(["id": .integer(id + 1000), "memberId": .integer(id), "nickname": .string(name), "isOwner": owner])
    }
    private func snapshot(_ rows: [ClubGovernanceValue], permitted: Bool = true) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
        return .init(operation: .members, scope: scope, permissions: permissions, value: .array(rows))
    }
    private func options(_ rows: [ClubGovernanceValue]) throws -> ClubSeriesLeadOptions { try .init(snapshot: snapshot(rows), context: context()) }
    func testMemberIDNotRecordIDAndTrimmedNames() throws {
        let value = try options([row(41)])
        XCTAssertEqual(value.members.map(\.id), [41]); XCTAssertEqual(value.members.first?.nickname, "Member")
        XCTAssertTrue(value.contains(memberID: 41)); XCTAssertFalse(value.contains(memberID: 1041)); XCTAssertFalse(value.contains(memberID: nil))
    }
    func testOwnerAndUnknownOwnerStatusRemainEligibleExplicitMembers() throws {
        let value = try options([row(7, owner: .bool(true)), row(41, owner: .bool(false)), row(42)])
        XCTAssertEqual(value.members.map(\.id), [7, 41, 42])
    }
    func testDuplicateIDsKeepFirstSourceRowAndNamesDoNotCollapseDistinctMembers() throws {
        let value = try options([row(41, name: "Same"), row(42, name: "Same"), row(41, name: "Later")])
        XCTAssertEqual(value.members.map(\.id), [41, 42]); XCTAssertEqual(value.members.map(\.nickname), ["Same", "Same"])
    }
    func testBlankAndMissingNamesStayUnknownWithMemberIDAvailable() throws {
        let value = try options([row(41, name: "  "), .object(["memberId": .integer(42)])])
        XCTAssertNil(value.members[0].nickname); XCTAssertNil(value.members[1].nickname)
        XCTAssertEqual(value.members.map(\.id), [41, 42])
    }
    func testEmptyMembersDoesNotInventOwnerOrNullOption() throws {
        let value = try options([]); XCTAssertTrue(value.members.isEmpty)
        XCTAssertFalse(value.contains(memberID: 0)); XCTAssertFalse(value.contains(memberID: nil))
    }
    func testMalformedAndContradictoryClubRowsFail() {
        let invalidRows: [ClubGovernanceValue] = [.null, .object(["id": .integer(41)]), .object(["memberId": .bool(true)]),
            .object(["memberId": .integer(0)]), .object(["memberId": .integer(41), "clubId": .integer(82)])]
        for invalid in invalidRows {
            XCTAssertThrowsError(try options([invalid]))
        }
    }
    func testFreshActivityManagementPermissionRequiredEvenWhenMemberReadIsVisible() throws {
        XCTAssertThrowsError(try ClubSeriesLeadOptions(snapshot: snapshot([row(41)], permitted: false), context: context())) { error in
            XCTAssertEqual(error as? ClubGovernanceFailure, .forbidden)
        }
    }
    func testScopeAndSignedOutContextsCannotAcceptSnapshot() throws {
        let source = try snapshot([row(41)])
        for target in [ClubGovernanceScope(clubID: 81), .init(clubID: 82, topicID: 91), .init(clubID: 81, topicID: 92), .init(clubID: 81, topicID: 91, activityID: 101)] {
            XCTAssertThrowsError(try ClubSeriesLeadOptions(snapshot: source, context: context(target)))
        }
        XCTAssertThrowsError(try ClubSeriesLeadOptions(snapshot: source, context: context(identity: nil)))
    }
    func testExplicitMemberBuildsExistingCreateCommandWithoutRoleOrExtraField() throws {
        let value = try options([row(41)]); XCTAssertTrue(value.contains(memberID: 41))
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: scope)
        draft.text["defaultLeadMemberId"] = "41"; draft.text["startDate"] = "2026-10-12"
        let command = try draft.command()
        XCTAssertEqual(command.fields["defaultLeadMemberId"], .integer(41)); XCTAssertNil(command.fields["roleCode"])
        XCTAssertEqual(command.fields["clubId"], .integer(81)); XCTAssertEqual(command.fields["topicId"], .integer(91))
        XCTAssertEqual(command.operation.permission, "club:activity:manage")
    }
    func testUnselectedMemberStillFailsExistingNativeCommand() {
        var draft = ClubGovernanceFormDraft(operation: .createSeries, scope: scope); draft.text["startDate"] = "2026-10-12"
        XCTAssertThrowsError(try draft.command())
        draft.text["defaultLeadMemberId"] = "0"; XCTAssertThrowsError(try draft.command())
    }
}
