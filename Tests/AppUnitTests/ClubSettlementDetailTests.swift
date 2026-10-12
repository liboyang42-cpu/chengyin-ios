import XCTest
@testable import Questify

@MainActor final class ClubSettlementDetailTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-club-settlement"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = [], scopes: [ClubGovernanceScope] = []
        var sends = 0, selectedTopicID = 91
        var amount = "Server amount", omitSelected = false, allowed = true, held = false
        var failure: ClubGovernanceFailure?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        let scope = ClubGovernanceScope(clubID: 81)
        func sourceContext() -> ClubGovernanceReadContext {
            .init(operation: .settlement, scope: scope, identity: identity, viewerRevision: 31,
                  authorizationGeneration: authorizationGeneration, accessIdentity: ObjectIdentifier(self))
        }
        func response(_ operation: ClubGovernanceRead = .settlement, scope: ClubGovernanceScope = .init(clubID: 81)) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:finance:read")] : []), "canManageRoles": .bool(false)]), scope: scope)
            func row(_ id: Int, topic: Int, amount: String) -> ClubGovernanceValue {
                .object(["id": .integer(id), "topicId": .integer(topic), "name": .string("Settlement"), "status": .string("settled"),
                    "amountStatus": .string("verified"), "amountText": .string(amount), "originalAmountText": .string("Source original"),
                    "executedAdjustmentText": .string("Source adjustment"), "netAmountText": .string("Source net"),
                    "arrivedText": .string("Source arrival"), "paidText": .string("Source payout")])
            }
            return .init(operation: operation, scope: scope, permissions: permission, value: .object([
                "settledAmountStatus": .string("verified"), "settledAmountText": .string("Source total"), "unverifiedSettledCount": .integer(0),
                "topics": .array([row(201, topic: 91, amount: "First same-topic record")] + (omitSelected ? [] : [row(202, topic: selectedTopicID, amount: amount)]))]))
        }
        func target() throws -> ClubSettlementDetailTarget {
            let projection = try ClubSettlementDetailPresentation(snapshot: response(), context: sourceContext())
            return try XCTUnwrap(projection.target(recordID: 202, context: sourceContext(), snapshotGeneration: 4, namespace: storageNamespace))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); scopes.append(scope); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ access: Access, _ target: ClubSettlementDetailTarget) -> ClubSettlementDetailReadModel.Context {
        ClubSettlementDetailReadModel.context(target: target, identity: access.identity, access: access)
    }
    private func activate(_ model: ClubSettlementDetailReadModel, _ context: ClubSettlementDetailReadModel.Context) throws -> ClubSettlementDetailReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testActualClubSummaryReadSelectsSecondSameTopicRecordWithoutFinancialWrites() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target)
        let permit = try activate(model, expected); await model.load(permit, target: target, access: access, current: { true })
        XCTAssertEqual(access.resources, [.settlement]); XCTAssertEqual(access.scopes, [.init(clubID: 81)])
        XCTAssertEqual(model.accepted(expected, access: access)?.id, 202); XCTAssertEqual(model.record?.amountText, "Server amount"); XCTAssertEqual(access.sends, 0)
    }
    func testRefreshMissingRecordClearsOldAmountAndDoesNotFallbackToSameTopic() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { true })
        access.omitSelected = true; await model.load(permit, target: target, access: access, current: { true })
        XCTAssertNil(model.record); XCTAssertTrue(model.acceptedMissing(expected, access: access)); XCTAssertNil(model.failure)
    }
    func testMalformedFailureHidesStaleMoneyAndRetryReadsFresh() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { true })
        access.failure = .malformed; await model.load(permit, target: target, access: access, current: { true })
        XCTAssertNil(model.record); XCTAssertEqual(model.failure, .malformed); XCTAssertFalse(model.missing)
        access.failure = nil; access.amount = "Fresh source amount"; await model.load(permit, target: target, access: access, current: { true })
        XCTAssertEqual(model.record?.amountText, "Fresh source amount"); XCTAssertNil(model.failure)
    }
    func testFreshPermissionDeniedAndReassignedTopicFailClosed() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        access.allowed = false; await model.load(permit, target: target, access: access, current: { true }); XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.record)
        access.allowed = true; access.selectedTopicID = 92; await model.load(permit, target: target, access: access, current: { true }); XCTAssertEqual(model.failure, .targetChanged); XCTAssertNil(model.record)
    }
    func testRetiredParentAndClosedSheetRejectQueuedAndLateRead() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { false }); XCTAssertTrue(access.resources.isEmpty)
        access.held = true; let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, target: target, access: access, current: { true }) }; await fulfillment(of: [entered], timeout: 1)
        model.leave(expected); access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.record); XCTAssertFalse(model.loading)
        _ = model.activate(expected); await model.load(permit, target: target, access: access, current: { true }); XCTAssertEqual(access.resources.count, 1)
    }
    func testOldTargetCannotBeReactivatedUnderNewIdentityOrNamespace() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target()
        access.identity = .init(accountID: 702, epoch: 2)
        var expected = context(access, target), permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { true }); XCTAssertTrue(access.resources.isEmpty)
        access.identity = .init(accountID: 701, epoch: 1); access.storageNamespace = "new-realm"
        expected = context(access, target); permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { true }); XCTAssertTrue(access.resources.isEmpty)
    }
    func testIdentityChangesDuringReadCannotPublishMoney() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        access.held = true; let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, target: target, access: access, current: { true }) }; await fulfillment(of: [entered], timeout: 1)
        access.identity = .init(accountID: 701, epoch: 2); access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.record)
    }
    func testAuthorityNamespaceAndReaderReplacementHideLoadedMoney() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        await model.load(permit, target: target, access: access, current: { true })
        access.storageNamespace = "new-realm"; XCTAssertNil(model.accepted(expected, access: access))
        access.storageNamespace = expected.namespace; access.authorizationGeneration = UUID(); XCTAssertNil(model.accepted(expected, access: access))
        let other = Access(); other.authorizationGeneration = expected.read.authorizationGeneration; XCTAssertNil(model.accepted(expected, access: other))
    }
    func testNewerRefreshWinsWhenOldReaderIgnoresCancellation() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        access.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, target: target, access: access, current: { true }) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, target: target, access: access, current: { true }) }; await fulfillment(of: [second], timeout: 1)
        access.amount = "Newer"; access.pending[1].resume(returning: try access.response()); await new.value
        access.amount = "Older"; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(model.record?.amountText, "Newer"); XCTAssertFalse(model.loading)
    }
    func testAnotherRowTargetCannotUseExistingPermitAndConfiguredGateRemains() async throws {
        let access = Access(), model = ClubSettlementDetailReadModel(), target = try access.target(), expected = context(access, target), permit = try activate(model, expected)
        let other = try access.target(); await model.load(permit, target: other, access: access, current: { true }); XCTAssertTrue(access.resources.isEmpty)
        access.isConfigured = false; await model.load(permit, target: target, access: access, current: { true }); XCTAssertEqual(model.failure, .notConfigured); XCTAssertTrue(access.resources.isEmpty); XCTAssertEqual(access.sends, 0)
    }
}
