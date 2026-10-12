import XCTest
@testable import QuestifyCore

final class ClubSettlementDetailPresentationTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81)
    private func context(identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1), authority: UUID? = nil) -> ClubGovernanceReadContext {
        .init(operation: .settlement, scope: scope, identity: identity, viewerRevision: 0, authorizationGeneration: authority)
    }
    private func row(_ id: Int = 201, topic: Int = 91, status: String = "settled", unverified: Bool = false, amount: String = "¥8.00") -> ClubGovernanceValue {
        .object(["id": .integer(id), "topicId": .integer(topic), "name": .string("Club settlement"), "status": .string(status),
            "amountStatus": .string(unverified ? "unverified" : "verified"), "amountText": unverified ? .null : .string(amount),
            "originalAmountText": .string("¥10.00"), "executedAdjustmentText": .string("-¥2.00"), "netAmountText": .string("¥8.00"),
            "arrivedText": .string("Server arrival state"), "paidText": .string("Server payout state")])
    }
    private func replacing(_ value: ClubGovernanceValue, _ fields: [String: ClubGovernanceValue]) -> ClubGovernanceValue { .object((value.object ?? [:]).merging(fields) { _, new in new }) }
    private func snapshot(_ rows: [ClubGovernanceValue], permitted: Bool = true) throws -> ClubGovernanceSnapshot {
        let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:finance:read")] : []), "canManageRoles": .bool(false)]), scope: scope)
        let missing = rows.filter { $0["amountStatus"] == .string("unverified") }.count
        return .init(operation: .settlement, scope: scope, permissions: permission, value: .object([
            "settledAmountStatus": .string(missing > 0 ? "unverified" : "verified"), "settledAmountText": missing > 0 ? .null : .string("Server total"),
            "unverifiedSettledCount": .integer(missing), "topics": .array(rows)]))
    }
    private func presentation(_ rows: [ClubGovernanceValue]) throws -> ClubSettlementDetailPresentation { try .init(snapshot: snapshot(rows), context: context()) }
    private func target(_ value: ClubSettlementDetailPresentation, id: Int = 201) throws -> ClubSettlementDetailTarget {
        try XCTUnwrap(value.target(recordID: id, context: context(), snapshotGeneration: 4, namespace: "realm"))
    }
    func testSameTopicRowsStayDistinctAndTargetUsesSettlementRowID() throws {
        let value = try presentation([row(), row(202, amount: "¥16.00")]), selected = try target(value, id: 202)
        XCTAssertEqual(value.records.map(\.id), [201, 202]); XCTAssertEqual(selected.topicID, 91); XCTAssertEqual(selected.recordID, 202)
        XCTAssertEqual(try value.record(for: selected)?.amountText, "¥16.00")
        XCTAssertNil(value.target(recordID: 91, context: context(), snapshotGeneration: 4, namespace: "realm"))
    }
    func testAllFinancialAndTimelineStringsRemainVerbatim() throws {
        let source = replacing(row(), ["amountText": .string("  CNY 8.000  "), "originalAmountText": .string("10 (source)"), "executedAdjustmentText": .string("— pending adjustment"), "netAmountText": .string("Source net, not recomputed"), "arrivedText": .string("Unknown arrival"), "paidText": .string("No verified payout")])
        let record = try XCTUnwrap(presentation([source]).records.first)
        XCTAssertEqual(record.amountText, "  CNY 8.000  "); XCTAssertEqual(record.originalAmountText, "10 (source)")
        XCTAssertEqual(record.executedAdjustmentText, "— pending adjustment"); XCTAssertEqual(record.netAmountText, "Source net, not recomputed")
        XCTAssertEqual(record.arrivedText, "Unknown arrival"); XCTAssertEqual(record.paidText, "No verified payout")
    }
    func testPendingVoidUnverifiedAndCreditedRemainDifferentStates() throws {
        let rows = try presentation([row(201, status: "pending"), row(202, status: "void"), row(203, unverified: true), row(204)]).records
        XCTAssertEqual(rows.map(\.status), [.pending, .void, .unverified, .credited])
        XCTAssertNil(rows[2].amountText); XCTAssertEqual(rows[0].amountLabelKey, "club.settlementDetail.amount.pending")
        XCTAssertEqual(rows[1].amountLabelKey, "club.settlementDetail.amount.void"); XCTAssertEqual(rows[2].amountLabelKey, "club.settlementDetail.amount.credited")
    }
    func testUnverifiedCannotAcquireZeroOrNetAmountFallback() {
        XCTAssertThrowsError(try presentation([replacing(row(unverified: true), ["amountText": .integer(0)])]))
        XCTAssertThrowsError(try presentation([replacing(row(unverified: true), ["amountText": .string("¥0.00")])]))
        XCTAssertThrowsError(try presentation([row(status: "pending", unverified: true)]))
    }
    func testMissingRowDoesNotSelectFirstRecordWithSameTopic() throws {
        let old = try presentation([row(), row(202)]), selected = try target(old, id: 202)
        XCTAssertNil(try presentation([row()]).record(for: selected))
    }
    func testFreshMatchingRowCanChangeAmountsButNotTopicIdentity() throws {
        let selected = try target(presentation([row()]))
        XCTAssertEqual(try presentation([row(amount: "Server updated amount")]).record(for: selected)?.amountText, "Server updated amount")
        XCTAssertThrowsError(try presentation([row(topic: 92)]).record(for: selected)) { XCTAssertEqual($0 as? ClubGovernanceFailure, .targetChanged) }
    }
    func testForeignClubMalformedRowsAndDuplicateIDsRejectEntireProjection() {
        for source in [replacing(row(), ["clubId": .integer(82)]), replacing(row(), ["topicId": .integer(0)]), replacing(row(), ["netAmountText": .null]), replacing(row(), ["status": .string("unknown")])] {
            XCTAssertThrowsError(try presentation([source]))
        }
        XCTAssertThrowsError(try presentation([row(), row()]))
        XCTAssertThrowsError(try presentation([row(), .null]))
    }
    func testFreshScopedFinancePermissionAndSignedInIdentityRequired() throws {
        XCTAssertThrowsError(try ClubSettlementDetailPresentation(snapshot: snapshot([row()], permitted: false), context: context())) { XCTAssertEqual($0 as? ClubGovernanceFailure, .forbidden) }
        XCTAssertThrowsError(try ClubSettlementDetailPresentation(snapshot: snapshot([row()]), context: context(identity: nil)))
        let wrong = ClubGovernanceReadContext(operation: .settlement, scope: .init(clubID: 82), identity: .init(accountID: 701, epoch: 1), viewerRevision: 0, authorizationGeneration: nil)
        XCTAssertThrowsError(try ClubSettlementDetailPresentation(snapshot: snapshot([row()]), context: wrong))
    }
    func testSourceRouteRetiresOnRefreshFinancialChangeNamespaceOrIdentity() throws {
        let value = try presentation([row()]), selected = try target(value)
        XCTAssertTrue(selected.isCurrent(presentation: value, context: context(), snapshotGeneration: 4, namespace: "realm"))
        XCTAssertFalse(selected.isCurrent(presentation: value, context: context(), snapshotGeneration: 5, namespace: "realm"))
        XCTAssertFalse(selected.isCurrent(presentation: value, context: context(), snapshotGeneration: 4, namespace: "new-realm"))
        XCTAssertFalse(selected.isCurrent(presentation: value, context: context(identity: .init(accountID: 701, epoch: 2)), snapshotGeneration: 4, namespace: "realm"))
        XCTAssertFalse(selected.isCurrent(presentation: try presentation([row(amount: "Changed")]), context: context(), snapshotGeneration: 4, namespace: "realm"))
    }
    func testTargetCannotBeReusedForAnotherReadAccountAuthorityOrNamespace() throws {
        let selected = try target(presentation([row()]))
        XCTAssertTrue(selected.acceptsRead(context: context(), namespace: "realm"))
        XCTAssertFalse(selected.acceptsRead(context: context(identity: .init(accountID: 702, epoch: 1)), namespace: "realm"))
        XCTAssertFalse(selected.acceptsRead(context: context(authority: UUID()), namespace: "realm"))
        XCTAssertFalse(selected.acceptsRead(context: context(), namespace: "new-realm"))
        let other = try ClubSettlementDetailPresentation(snapshot: snapshot([row()]), context: context(identity: .init(accountID: 702, epoch: 1)))
        XCTAssertThrowsError(try other.record(for: selected))
    }
    func testEmptyValidatedSummaryProducesNoPlaceholderTarget() throws {
        let value = try presentation([]); XCTAssertTrue(value.records.isEmpty)
        XCTAssertNil(value.target(recordID: 201, context: context(), snapshotGeneration: 4, namespace: "realm"))
    }
    func testInconsistentAggregateAndRawNumericAmountAreNotSilentlyAccepted() throws {
        let source = try snapshot([row()])
        let bad = ClubGovernanceSnapshot(operation: .settlement, scope: scope, permissions: source.permissions,
            value: replacing(source.value, ["unverifiedSettledCount": .integer(1)]))
        XCTAssertThrowsError(try ClubSettlementDetailPresentation(snapshot: bad, context: context()))
        XCTAssertThrowsError(try presentation([replacing(row(), ["amountText": .decimal(8.0)])]))
    }
}
