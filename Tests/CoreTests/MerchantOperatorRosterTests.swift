import XCTest
@testable import QuestifyCore

final class MerchantOperatorRosterTests: XCTestCase {
    private func member(_ id: Int, _ status: String = "ACTIVE", version: Int = 0) -> MerchantBusinessValue {
        .object(["id": .int(id), "nickname": .string("Example \(id)"), "roleCode": .string("MERCHANT_CHECKIN"),
                 "status": .string(status), "acceptedAt": .string("2026-09-01T09:00:00"), "version": .int(version)])
    }
    private func invite(_ id: Int, _ status: String = "PENDING", expiresAt: String = "2026-10-08T09:00:00") -> MerchantBusinessValue {
        .object(["id": .int(id), "roleCode": .string("MERCHANT_MARKETING"),
                 "status": .string(status), "expiresAt": .string(expiresAt), "version": .int(2)])
    }
    private func document(_ members: [MerchantBusinessValue] = [], _ invites: [MerchantBusinessValue] = []) throws -> MerchantBusinessDocument {
        try .init(query: .operators, payload: .object(["operators": .array(members), "invites": .array(invites)]))
    }

    func testExactServerStatusesPartitionCurrentRowsAndAllHistory() throws {
        let roster = try MerchantOperatorRoster(document: document(
            [member(1), member(2, "REVOKED")],
            [invite(1), invite(2, "ACCEPTED"), invite(3, "EXPIRED"), invite(4, "REVOKED")]))
        XCTAssertEqual(roster.activeMembers.map(\.id), ["1"])
        XCTAssertEqual(roster.pendingInvites.map(\.id), ["1"])
        XCTAssertEqual(roster.previousMembers.map(\.id), ["2"])
        XCTAssertEqual(roster.previousInvites.map(\.id), ["2", "3", "4"])
        XCTAssertTrue(roster.hasHistory)
    }

    func testCountsUseOnlyLoadedRowsAndDoNotCountHistory() throws {
        let roster = try MerchantOperatorRoster(document: document(
            [member(8), member(7), member(6, "REVOKED")], [invite(9, "EXPIRED")]))
        XCTAssertEqual(roster.activeMembers.count, 2)
        XCTAssertEqual(roster.pendingInvites.count, 0)
        XCTAssertEqual(roster.previousMembers.count, 1)
        XCTAssertEqual(roster.previousInvites.count, 1)
    }

    func testEmptyResponseHasTwoHonestZeroCountsWithoutHistory() throws {
        let roster = try MerchantOperatorRoster(document: document())
        XCTAssertTrue(roster.activeMembers.isEmpty)
        XCTAssertTrue(roster.pendingInvites.isEmpty)
        XCTAssertFalse(roster.hasHistory)
    }

    func testHistoryOnlyResponseDoesNotPretendToHaveCurrentEmployeesOrInvites() throws {
        let roster = try MerchantOperatorRoster(document: document([member(1, "REVOKED")], [invite(2, "ACCEPTED")]))
        XCTAssertTrue(roster.activeMembers.isEmpty)
        XCTAssertTrue(roster.pendingInvites.isEmpty)
        XCTAssertTrue(roster.hasHistory)
    }

    func testPendingInviteDoesNotHideEmptyEmployeeState() throws {
        let roster = try MerchantOperatorRoster(document: document([], [invite(1)]))
        XCTAssertTrue(roster.activeMembers.isEmpty)
        XCTAssertEqual(roster.pendingInvites.count, 1)
        XCTAssertFalse(roster.hasHistory)
    }

    func testProjectionKeepsOriginalRecordsVersionsAndOrderWithinEachGroup() throws {
        let source = try document([member(12, version: 9), member(3, "REVOKED"), member(8, version: 21)],
                                  [invite(18, "EXPIRED"), invite(7), invite(5, "ACCEPTED")])
        let before = source
        let roster = try MerchantOperatorRoster(document: source)
        XCTAssertEqual(roster.activeMembers, [source.rows[0], source.rows[2]])
        XCTAssertEqual(roster.previousMembers, [source.rows[1]])
        XCTAssertEqual(roster.pendingInvites, [source.rows[4]])
        XCTAssertEqual(roster.previousInvites, [source.rows[3], source.rows[5]])
        XCTAssertEqual(roster.activeMembers[1].fields["version"], .int(21))
        XCTAssertEqual(source, before)
    }

    func testMatchingNumericIDsRemainSeparateMemberAndInvitationIdentities() throws {
        let roster = try MerchantOperatorRoster(document: document([member(9)], [invite(9)]))
        XCTAssertEqual(roster.activeMembers.first?.kind, .operatorMember)
        XCTAssertEqual(roster.pendingInvites.first?.kind, .invite)
        XCTAssertEqual(roster.activeMembers.first?.id, roster.pendingInvites.first?.id)
    }

    func testServerStatusIsNotInferredFromOldOrFutureExpiryDates() throws {
        let roster = try MerchantOperatorRoster(document: document([], [
            invite(1, "PENDING", expiresAt: "2000-01-01T00:00:00"),
            invite(2, "EXPIRED", expiresAt: "2099-01-01T00:00:00")]))
        XCTAssertEqual(roster.pendingInvites.map(\.id), ["1"])
        XCTAssertEqual(roster.previousInvites.map(\.id), ["2"])
    }

    func testRefreshedResponseReplacesPreviousStateWithoutCaching() throws {
        let original = try MerchantOperatorRoster(document: document([member(1)], [invite(2)]))
        let refreshed = try MerchantOperatorRoster(document: document([member(1, "REVOKED")], [invite(2, "ACCEPTED")]))
        XCTAssertEqual(original.activeMembers.count, 1)
        XCTAssertTrue(refreshed.activeMembers.isEmpty)
        XCTAssertTrue(refreshed.pendingInvites.isEmpty)
        XCTAssertEqual(refreshed.previousMembers.map(\.id), ["1"])
        XCTAssertEqual(refreshed.previousInvites.map(\.id), ["2"])
        XCTAssertFalse(try MerchantOperatorRoster(document: document()).hasHistory)
    }

    func testNonTeamDocumentCannotBecomeRoster() throws {
        for query in [MerchantBusinessQuery.roles, .overview] {
            let other = try MerchantBusinessDocument(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query))
            XCTAssertThrowsError(try MerchantOperatorRoster(document: other))
        }
    }

    func testUnknownAndNormalizedStatusVariantsFailExistingDocumentBoundary() throws {
        for status in ["active", "ACTIVE ", "PENDING", "UNKNOWN"] {
            XCTAssertThrowsError(try document([member(1, status)]))
        }
        for status in ["pending", "PENDING ", "ACTIVE", "UNKNOWN"] {
            XCTAssertThrowsError(try document([], [invite(1, status)]))
        }
    }

    func testProjectionDoesNotChangeExistingExactMutationPayloads() throws {
        let source = try document([member(12, version: 9)], [invite(7)])
        let mutations: [MerchantBusinessMutation] = [
            .operatorRole(id: try .init(12), version: 9, role: "MERCHANT_FINANCE"),
            .removeOperator(id: try .init(12), version: 9, reason: "Review only"),
            .revokeInvite(id: try .init(7), version: 2, reason: "Review only")]
        let before = try mutations.map { try $0.request(requestID: "roster-review-only") }
        _ = try MerchantOperatorRoster(document: source)
        let after = try mutations.map { try $0.request(requestID: "roster-review-only") }
        XCTAssertEqual(before, after)
    }
}
