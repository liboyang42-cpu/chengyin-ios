import XCTest
@testable import QuestifyCore

final class ClubOpsGovernancePresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private func permissions(_ granted: [String] = ["club:member:manage"], roles: [String] = ["CLUB_OWNER"], canManageRoles: Bool = true) throws -> ClubGovernancePermissions {
        try .init(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array(roles.map(ClubGovernanceValue.string)),
                                  "permissions": .array(granted.map(ClubGovernanceValue.string)), "canManageRoles": .bool(canManageRoles)]), scope: scope)
    }
    private func ban(_ id: Int, source: String = "CLUB", status: String = "ACTIVE", expires: ClubGovernanceValue = .string("2026-10-31T09:30:00"),
                     nickname: ClubGovernanceValue = .string(" Rider "), version: ClubGovernanceValue = .integer(2)) -> ClubGovernanceValue {
        .object(["id": .integer(id), "clubId": .integer(81), "targetMemberId": .integer(700 + id), "targetNickname": nickname, "status": .string(status),
                 "sourceType": .string(source), "banReason": .string("Synthetic"), "expiresAt": expires, "bannedAt": .string("2026-10-01 08:00:00"), "version": version])
    }
    private func cases(_ value: ClubGovernanceValue, permitted: Bool = true) throws -> ClubOpsCaseList {
        var granted: ClubGovernancePermissions?
        if permitted { granted = try permissions([]) }
        return try .init(snapshot: .init(operation: .cases, scope: scope, permissions: granted, value: value))
    }
    private let report = ClubGovernanceValue.object(["id": .integer(171), "clubId": .integer(81), "caseType": .string("REPORT"), "targetType": .string("ACTIVITY"),
        "targetId": .integer(5), "status": .string("PENDING"), "version": .integer(0), "reason": .string("Late start"), "createTime": .string("2026-10-02T10:15:00")])
    private func activeBan(club: Int = 81) -> ClubGovernanceValue {
        .object(["id": .integer(9), "clubId": .integer(club), "status": .string("ACTIVE"), "sourceType": .string("CLUB"),
                 "banReason": .string("Synthetic"), "bannedAt": .string("2026-10-01 08:00:00"), "expiresAt": .string("2026-10-31 08:00:00")])
    }

    func testClockKeepsServerDigitsAndRendersEpochInShanghai() {
        XCTAssertEqual(ClubOpsGovernanceClock.minute(.string("2026-10-08T09:00:00")), "2026-10-08 09:00")
        XCTAssertEqual(ClubOpsGovernanceClock.minute(.integer(1_791_421_200_000)), "2026-10-08 09:00")
        XCTAssertNil(ClubOpsGovernanceClock.minute(.null)); XCTAssertNil(ClubOpsGovernanceClock.minute(.string("  ")))
        XCTAssertEqual(ClubOpsGovernanceClock.monthDay(.string("2026-10-31 23:59:59")), "10-31")
        XCTAssertNil(ClubOpsGovernanceClock.monthDay(.string("2026-10")))
    }
    func testBanRowsMirrorMiniProgramSourceStatusAndUnbanRules() throws {
        let value = ClubGovernanceValue.array([ban(1), ban(2, source: "PLATFORM", expires: .null, nickname: .null), ban(3, status: "EXPIRED"), ban(4, source: "PLATFORM", status: "UNBANNED")])
        let list = try ClubOpsBanList(snapshot: .init(operation: .bans, scope: scope, permissions: permissions(), value: value))
        XCTAssertEqual(list.rows.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(list.rows[0].nickname, "Rider"); XCTAssertNil(list.rows[1].nickname)
        XCTAssertEqual(list.rows[0].expiry, .until("2026-10-31 09:30")); XCTAssertEqual(list.rows[1].expiry, .platformPermanent)
        XCTAssertEqual(list.rows[0].bannedAt, "2026-10-01 08:00")
        XCTAssertEqual(list.rows[0].unbanSeed, ["banId": .integer(1), "version": .integer(2)])
        XCTAssertNil(list.rows[1].unbanSeed); XCTAssertNil(list.rows[2].unbanSeed); XCTAssertNil(list.rows[3].unbanSeed)
        XCTAssertTrue(list.rows[1].platformOnly); XCTAssertFalse(list.rows[3].platformOnly); XCTAssertFalse(list.rows[0].platformOnly)
        XCTAssertEqual(list.rows[2].status, .expired)
    }
    func testBanListFailsClosed() throws {
        XCTAssertThrowsError(try ClubOpsBanList(snapshot: .init(operation: .bans, scope: scope, permissions: permissions([]), value: .array([ban(1)]))))
        XCTAssertThrowsError(try ClubOpsBanList(snapshot: .init(operation: .bans, scope: scope, permissions: permissions(), value: .array([ban(1, version: .string("2"))]))))
        XCTAssertThrowsError(try ClubOpsBanList(snapshot: .init(operation: .bans, scope: scope, permissions: permissions(), value: .null)))
        XCTAssertThrowsError(try ClubOpsBanList(snapshot: .init(operation: .bans, scope: scope, permissions: nil, value: .array([]))))
    }
    func testCasesWithoutFactAreUnknownAndNeverShowAppeal() throws {
        let list = try cases(.array([report]))
        XCTAssertEqual(list.appeal, .unknown); XCTAssertFalse(list.canAppeal); XCTAssertTrue(list.canReport)
        XCTAssertEqual(list.rows.first?.kind, .report("ACTIVITY")); XCTAssertEqual(list.rows.first?.status, .pending)
        XCTAssertEqual(list.rows.first?.submittedAt, "2026-10-02 10:15"); XCTAssertNil(list.rows.first?.decisionReason)
    }
    func testKnownNoneAndKnownBanDriveAppealEntry() throws {
        let none = try cases(.object(["data": .array([]), "activeBan": .null]))
        XCTAssertEqual(none.appeal, .none); XCTAssertFalse(none.canAppeal)
        let banned = try cases(.object(["data": .array([]), "activeBan": activeBan()]), permitted: false)
        XCTAssertTrue(banned.canAppeal); XCTAssertFalse(banned.canReport)
        guard case .ban(let fact) = banned.appeal else { return XCTFail() }
        XCTAssertEqual(fact.source, .club); XCTAssertEqual(fact.expiry, .until("2026-10-31 08:00")); XCTAssertEqual(fact.reason, "Synthetic")
        XCTAssertThrowsError(try cases(.object(["data": .array([]), "activeBan": activeBan(club: 82)])))
    }
    func testCaseValidationAcceptsOnlyThisClubsActiveBanFact() throws {
        let accepted = try ClubGovernanceValidation.validate(.object(["data": .array([report]), "activeBan": activeBan()]), operation: .cases, scope: scope)
        XCTAssertNotNil(accepted["activeBan"].object)
        XCTAssertNoThrow(try ClubGovernanceValidation.validate(.object(["data": .array([]), "activeBan": .null]), operation: .cases, scope: scope))
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(["data": .array([]), "activeBan": activeBan(club: 82)]), operation: .cases, scope: scope))
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(["data": .array([]), "activeBan": .string("yes")]), operation: .cases, scope: scope))
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(.object(["data": .array([]), "activeBan": .null, "extra": .null]), operation: .cases, scope: scope))
    }
    func testServiceCarriesActiveBanOnlyForOwnCasesWhenSent() {
        let body = ClubGovernanceValue.object(["code": .integer(200), "data": .array([]), "activeBan": .null])
        XCTAssertEqual(ClubGovernanceService.payload(body, operation: .cases), .object(["data": .array([]), "activeBan": .null]))
        XCTAssertEqual(ClubGovernanceService.payload(.object(["code": .integer(200), "data": .array([])]), operation: .cases), .array([]))
        XCTAssertEqual(ClubGovernanceService.payload(body, operation: .bans), .array([]))
    }
    func testAppealReviewNeedsKnownBanForInactiveViewerAndRejectsKnownNone() throws {
        let command = try ClubGovernanceCommand(operation: .appeal, scope: scope, values: ["reason": .string("Facts"), "requestId": .string("appeal-1")])
        let banned = ClubGovernanceSnapshot(operation: .cases, scope: scope, permissions: nil, value: .object(["data": .array([]), "activeBan": activeBan()]))
        XCTAssertNoThrow(try command.validateReview(banned, accountID: 701))
        let unknownInactive = ClubGovernanceSnapshot(operation: .cases, scope: scope, permissions: nil, value: .array([]))
        XCTAssertThrowsError(try command.validateReview(unknownInactive, accountID: 701))
        let knownNone = try ClubGovernanceSnapshot(operation: .cases, scope: scope, permissions: permissions([]), value: .object(["data": .array([]), "activeBan": .null]))
        XCTAssertThrowsError(try command.validateReview(knownNone, accountID: 701))
        let report = try ClubGovernanceCommand(operation: .report, scope: scope, values: ["targetType": .string("CLUB"), "targetId": .integer(81), "reason": .string("Facts"), "requestId": .string("report-1")])
        XCTAssertThrowsError(try report.validateReview(banned, accountID: 701))
    }
    func testBanDraftSendsBoundedEpochFromDayChoice() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var draft = ClubGovernanceFormDraft(operation: .ban, scope: scope, seed: ["targetMemberId": .integer(704), "targetNickname": .string("Rider")])
        XCTAssertEqual(draft.text["banDays"], "30"); XCTAssertEqual(draft.choices("banDays"), ["7", "30", "90"])
        XCTAssertNil(draft.anchors["targetNickname"])
        draft.text["reason"] = "Harassment"
        let command = try draft.command(now: now)
        XCTAssertEqual(command.fields["expiresAtEpochMs"], .integer(1_790_000_000_000 + 30 * 86_400_000))
        XCTAssertNil(command.fields["expiresAt"]); XCTAssertNil(command.fields["banDays"]); XCTAssertNil(command.fields["targetNickname"])
        draft.text["banDays"] = "90"; XCTAssertEqual(try draft.command(now: now).fields["expiresAtEpochMs"], .integer(1_790_000_000_000 + 90 * 86_400_000))
        draft.text["banDays"] = "91"; XCTAssertThrowsError(try draft.command(now: now))
        draft.text["banDays"] = "30"; draft.text["reason"] = " "; XCTAssertThrowsError(try draft.command(now: now))
    }
    func testBanCommandRejectsPastBeyondNinetyDaysAndMixedExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000), ms = 1_790_000_000_000
        func ban(_ extra: [String: ClubGovernanceValue]) throws -> ClubGovernanceCommand {
            var values: [String: ClubGovernanceValue] = ["targetMemberId": .integer(704), "reason": .string("R"), "requestId": .string("ban-1")]
            values.merge(extra) { _, new in new }
            return try .init(operation: .ban, scope: scope, values: values, now: now)
        }
        XCTAssertNoThrow(try ban(["expiresAtEpochMs": .integer(ms + 7 * 86_400_000)]))
        XCTAssertThrowsError(try ban(["expiresAtEpochMs": .integer(ms)]))
        XCTAssertThrowsError(try ban(["expiresAtEpochMs": .integer(ms + 90 * 86_400_000 + 1)]))
        XCTAssertThrowsError(try ban(["expiresAtEpochMs": .string(String(ms + 86_400_000))]))
        XCTAssertThrowsError(try ban([:]))
        XCTAssertThrowsError(try ban(["expiresAtEpochMs": .integer(ms + 86_400_000), "expiresAt": .string("2026-10-08 09:00:00")]))
        XCTAssertNoThrow(try ban(["expiresAt": .string("2026-10-08 09:00:00")]))
    }
    func testUnbanNoteOptionalAndRevokeNoteFixed() throws {
        var unban = ClubGovernanceFormDraft(operation: .unban, scope: scope, seed: ["banId": .integer(1), "version": .integer(2)])
        XCTAssertEqual(try unban.command().fields["reason"], .string(""))
        unban.text["reason"] = String(repeating: "a", count: 501); XCTAssertThrowsError(try unban.command())
        let revoke = ClubGovernanceFormDraft(operation: .revokeRole, scope: scope, seed: ["assignmentId": .integer(181), "version": .integer(2), "roleName": .string("Operator")])
        XCTAssertEqual(try revoke.command().fields["reason"], .string("主理人在角色管理页撤销"))
        XCTAssertNil(try revoke.command().fields["roleName"])
        XCTAssertThrowsError(try ClubGovernanceCommand(operation: .transferOwner, scope: scope, values: ["targetMemberId": .integer(704), "reason": .string(""), "requestId": .string("t")]))
    }
    func testMembersExcludeOwnerAndUnprovenRows() throws {
        let value = ClubGovernanceValue.array([
            .object(["memberId": .integer(701), "nickname": .string("Owner"), "isOwner": .bool(true)]),
            .object(["memberId": .integer(704), "nickname": .string(" Rider "), "isOwner": .bool(false)]),
            .object(["memberId": .integer(705), "isOwner": .bool(false)]),
            .object(["memberId": .integer(706), "nickname": .string("Unknown")])])
        let members = try ClubOpsGovernanceMembers(snapshot: .init(operation: .members, scope: scope, permissions: permissions(), value: value))
        XCTAssertEqual(members.members.map(\.id), [704, 705]); XCTAssertEqual(members.ownerName, "Owner"); XCTAssertTrue(members.viewerIsOwner)
        XCTAssertEqual(members.members[0].seed, ["targetMemberId": .integer(704), "targetNickname": .string("Rider")])
        XCTAssertEqual(members.members[1].seed, ["targetMemberId": .integer(705)])
    }
    func testRoleRosterJoinsNamesClientSideWithFallbacks() throws {
        let roles = ClubGovernanceValue.object([
            "roles": .array([.object(["roleCode": .string("CLUB_OPERATOR"), "name": .string("Operator"), "scopeType": .string("CLUB"), "permissions": .array([])])]),
            "assignments": .array([
                .object(["id": .integer(181), "targetMemberId": .integer(704), "roleCode": .string("CLUB_OPERATOR"), "scopeType": .string("CLUB"), "scopeId": .integer(81), "version": .integer(2), "expiresAt": .string("2026-11-05 00:00:00")]),
                .object(["id": .integer(182), "targetMemberId": .integer(709), "roleCode": .string("CLUB_CO_OWNER"), "scopeType": .string("CLUB"), "scopeId": .integer(81), "version": .integer(0)])])])
        let source = try ClubGovernanceSnapshot(operation: .roles, scope: scope, permissions: permissions([]), value: roles)
        let bare = try ClubOpsRoleRoster(roles: source, members: nil)
        XCTAssertNil(bare.assignments[0].memberName); XCTAssertNil(bare.delegableMemberCount); XCTAssertNil(bare.ownerName)
        let members = try ClubGovernanceSnapshot(operation: .members, scope: scope, permissions: permissions([]), value: .array([
            .object(["memberId": .integer(701), "nickname": .string("Owner"), "isOwner": .bool(true)]),
            .object(["memberId": .integer(704), "nickname": .string("Rider"), "isOwner": .bool(false)])]))
        let joined = try ClubOpsRoleRoster(roles: source, members: members)
        XCTAssertEqual(joined.assignments.map(\.memberName), ["Rider", nil]); XCTAssertEqual(joined.assignments.map(\.roleName), ["Operator", nil])
        XCTAssertEqual(joined.assignments[0].expiresMonthDay, "11-05"); XCTAssertNil(joined.assignments[1].expiresMonthDay)
        XCTAssertEqual(joined.ownerName, "Owner"); XCTAssertEqual(joined.delegableMemberCount, 1)
        XCTAssertEqual(joined.assignments[0].revokeSeed, ["assignmentId": .integer(181), "version": .integer(2), "memberName": .string("Rider"), "roleName": .string("Operator")])
        XCTAssertEqual(joined.assignments[0].summaryKey, "club.rolePicker.summary.CLUB_OPERATOR")
        let otherClub = ClubGovernanceSnapshot(operation: .members, scope: .init(clubID: 82), permissions: nil, value: members.value)
        XCTAssertNil(try ClubOpsRoleRoster(roles: source, members: otherClub).ownerName)
        let denied = try ClubGovernanceSnapshot(operation: .roles, scope: scope, permissions: permissions([], roles: [], canManageRoles: false), value: roles)
        XCTAssertThrowsError(try ClubOpsRoleRoster(roles: denied, members: nil))
    }
}
