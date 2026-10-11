import XCTest
@testable import QuestifyCore

final class ClubMemberReportTargetTests: XCTestCase {
    private func member(_ id: Int = 702, name: String = "Sample member") throws -> ClubMember {
        let data = try JSONSerialization.data(withJSONObject: ["memberId": id, "nickname": name])
        return try JSONDecoder().decode(ClubMember.self, from: data)
    }
    private func directory(members: [ClubMember], joined: Bool = true, clubID: Int = 81) throws -> ClubMemberDirectory {
        let data = try JSONSerialization.data(withJSONObject: ["id": clubID, "name": "Sample club", "isJoined": joined])
        return .init(club: try JSONDecoder().decode(ClubRecord.self, from: data), members: members)
    }
    private func context(account: Int? = 701, epoch: UInt64 = 1, revision: UInt64 = 1, authorization: UUID? = nil) -> ClubGovernanceReadContext {
        .init(operation: .members, scope: .init(clubID: 81), identity: .init(accountID: account, epoch: epoch), viewerRevision: revision, authorizationGeneration: authorization)
    }
    func testOtherMemberProducesExactFrozenMemberTargetAndDisplayOnlyName() throws {
        let member = try member(name: "  Sample\n member  "), directory = try directory(members: [member])
        let target = try XCTUnwrap(ClubMemberReportTarget(member: member, directory: directory, context: context()))
        XCTAssertEqual(target.clubID, 81); XCTAssertEqual(target.memberID, 702)
        XCTAssertEqual(target.displayName, "Sample member")
        XCTAssertEqual(target.scope, .init(clubID: 81))
        XCTAssertEqual(target.seed, ["targetType": .string("MEMBER"), "targetId": .integer(702)])
        var draft = ClubGovernanceFormDraft(operation: .report, scope: target.scope, seed: target.seed)
        draft.text["reason"] = "  Specific facts  "
        let command = try draft.command()
        XCTAssertEqual(command.fields["targetId"], .integer(702)); XCTAssertEqual(command.fields["targetType"], .string("MEMBER"))
        XCTAssertEqual(command.fields["clubId"], .integer(81)); XCTAssertEqual(command.fields["reason"], .string("Specific facts"))
        XCTAssertEqual(command.fields["evidence"], .object([:])); XCTAssertNil(command.fields["targetName"])
        XCTAssertEqual(command.operation.path, "api/club/governance/cases/report")
    }
    func testSelfGuestNonmemberAndUnknownRowCannotCreateTarget() throws {
        let member = try member(), directory = try directory(members: [member])
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: directory, context: context(account: 702)))
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: directory, context: context(account: nil)))
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: try self.directory(members: [member], joined: false), context: context()))
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: try self.directory(members: []), context: context()))
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: try self.directory(members: [member], clubID: 82), context: context()))
        XCTAssertNil(ClubMemberReportTarget(member: member, directory: try self.directory(members: [member, member]), context: context()))
    }
    func testSignedInOwnerCanReportOtherMemberWithoutAdminRoleInference() throws {
        let member = try member(), data = Data(#"{"id":81,"isOwner":true,"isJoined":false}"#.utf8)
        let directory = ClubMemberDirectory(club: try JSONDecoder().decode(ClubRecord.self, from: data), members: [member])
        XCTAssertNotNil(ClubMemberReportTarget(member: member, directory: directory, context: context()))
    }
    func testTargetExpiresOnRefreshRemovalAccountEpochRoleAndAuthorityChange() throws {
        let member = try member(), directory = try directory(members: [member])
        let target = try XCTUnwrap(ClubMemberReportTarget(member: member, directory: directory, context: context()))
        XCTAssertTrue(target.isCurrent(directory: directory, context: context()))
        XCTAssertFalse(target.isCurrent(directory: nil, context: context()))
        XCTAssertFalse(target.isCurrent(directory: try self.directory(members: []), context: context()))
        for changed in [context(account: 703), context(epoch: 2), context(revision: 2), context(authorization: UUID())] {
            XCTAssertFalse(target.isCurrent(directory: directory, context: changed))
        }
    }
    func testContextualReportCannotChangeTargetThroughEditableDictionary() throws {
        var draft = ClubGovernanceFormDraft(operation: .report, scope: .init(clubID: 81), seed: ["targetType": .string("MEMBER"), "targetId": .integer(702)])
        XCTAssertEqual(Set(draft.text.keys), ["reason"])
        draft.text["reason"] = "Facts"; let first = try draft.command()
        draft.text["reason"] = "Updated facts"; let second = try draft.command()
        XCTAssertEqual(first.fields["targetId"], second.fields["targetId"])
        XCTAssertNotEqual(first.fields["requestId"], second.fields["requestId"])
        draft.text["targetId"] = "703"
        XCTAssertThrowsError(try draft.command())
    }
    func testMalformedContextualSeedNeverFallsBackToClub() throws {
        for seed in [["targetId": ClubGovernanceValue.integer(702)], ["targetType": .string("MEMBER")], ["targetType": .string("BAD"), "targetId": .integer(702)], ["targetType": .string("MEMBER"), "targetId": .integer(0)]] {
            var draft = ClubGovernanceFormDraft(operation: .report, scope: .init(clubID: 81), seed: seed)
            draft.text["reason"] = "Facts"
            XCTAssertThrowsError(try draft.command())
            XCTAssertNil(draft.text["targetType"]); XCTAssertNil(draft.text["targetId"])
        }
    }
    func testUnseededGenericReportRemainsEditableAndDefaultsToClub() throws {
        var draft = ClubGovernanceFormDraft(operation: .report, scope: .init(clubID: 81))
        XCTAssertTrue(draft.anchors.isEmpty); XCTAssertEqual(draft.text["targetType"], "CLUB")
        draft.text["reason"] = "Facts"; XCTAssertEqual(try draft.command().fields["targetId"], .integer(81))
        draft.text["targetType"] = "MEMBER"; draft.text["targetId"] = "702"
        XCTAssertEqual(try draft.command().fields["targetId"], .integer(702))
    }
    func testNamesAreBoundedAndUnknownIsNotInvented() throws {
        for name in ["", " \n ", String(repeating: "a", count: 60)] {
            let member = try member(name: name), directory = try directory(members: [member])
            let target = try XCTUnwrap(ClubMemberReportTarget(member: member, directory: directory, context: context()))
            if name.count == 60 { XCTAssertEqual(target.displayName?.count, 40) } else { XCTAssertNil(target.displayName) }
        }
    }
    @MainActor private final class ReadOnlyAccess: ClubGovernanceAccess {
        let identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        let isConfigured = true, allowsOfflineWrites = false
        let storageNamespace = "synthetic-member-report"
        var reads = 0, sends = 0
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            reads += 1
            XCTAssertEqual(operation, .cases); XCTAssertEqual(scope, .init(clubID: 81))
            let value: ClubGovernanceValue = .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array([])])
            return .init(operation: operation, scope: scope, permissions: try ClubGovernancePermissions(value: value, scope: scope), value: .array([]))
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; throw ClubGovernanceFailure.notConfigured
        }
    }
    @MainActor func testExistingCoordinatorCanReviewTargetWhileDisabledDispatchNeverSends() async throws {
        let access = ReadOnlyAccess(), coordinator = ClubGovernanceCoordinator(access: access)
        var draft = ClubGovernanceFormDraft(operation: .report, scope: .init(clubID: 81), seed: ["targetType": .string("MEMBER"), "targetId": .integer(702)])
        draft.text["reason"] = "Specific facts"
        let review = try await coordinator.prepare(draft.command())
        XCTAssertEqual(review.command.fields["targetType"], .string("MEMBER"))
        XCTAssertEqual(review.command.fields["targetId"], .integer(702))
        do { _ = try await coordinator.confirm(review); XCTFail("Dispatch must stay disabled") }
        catch { XCTAssertEqual(error as? ClubGovernanceFailure, .notConfigured) }
        XCTAssertEqual(access.reads, 1); XCTAssertEqual(access.sends, 0)
    }

}
