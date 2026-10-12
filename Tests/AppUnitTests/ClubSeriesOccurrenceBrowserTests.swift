import XCTest
@testable import Questify

@MainActor final class ClubSeriesOccurrenceBrowserTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        var storageNamespace = "synthetic-occurrences"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var resources: [ClubGovernanceRead] = []
        var scopes: [ClubGovernanceScope] = []
        var sends = 0, activityID = 101
        var allowed = true, held = false, empty = false
        var failure: ClubGovernanceFailure?
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func response(_ operation: ClubGovernanceRead = .occurrences, scope: ClubGovernanceScope = .init(clubID: 81, topicID: 91, seriesID: 111)) throws -> ClubGovernanceSnapshot {
            let permission = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
                "roleCodes": .array([]), "permissions": .array(allowed ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: scope)
            return .init(operation: operation, scope: scope, permissions: permission, value: .array(empty ? [] : [.object([
                "occurrenceId": .integer(112), "activityId": .integer(activityID), "occurrenceAt": .string("2026-10-08 09:00:00"), "signupCount": .null])]))
        }
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            resources.append(operation); scopes.append(scope); XCTAssertTrue(options.isEmpty)
            if let failure { throw failure }
            if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
            return try response(operation, scope: scope)
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private func context(_ access: Access, seriesID: Int = 111) -> ClubSeriesOccurrenceReadModel.Context {
        ClubSeriesOccurrenceReadModel.context(scope: .init(clubID: 81, topicID: 91, seriesID: seriesID), identity: access.identity, access: access)
    }
    private func activate(_ model: ClubSeriesOccurrenceReadModel, _ context: ClubSeriesOccurrenceReadModel.Context) throws -> ClubSeriesOccurrenceReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    func testExpansionUsesRealReadContractAndActualReturnedActivityWithoutWrites() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access)
        model.bind(expected); XCTAssertTrue(access.resources.isEmpty)
        let permit = try XCTUnwrap(model.activate(expected)); await model.load(permit, access: access, current: { true })
        XCTAssertEqual(access.resources, [.occurrences]); XCTAssertEqual(access.scopes, [expected.read.scope]); XCTAssertEqual(access.sends, 0)
        let value = try XCTUnwrap(model.accepted(expected, access: access)), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        XCTAssertEqual(route.scope.activityID, 101); XCTAssertTrue(model.canOpen(route, context: expected, access: access))
    }
    func testEmptyPermissionDeniedAndRetryAreSeparateStates() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.empty = true; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.options?.rows.count, 0); XCTAssertNil(model.failure)
        access.allowed = false; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.options)
        access.allowed = true; access.failure = .malformed; await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .malformed)
        access.failure = nil; access.empty = false; await model.load(permit, access: access, current: { true }); XCTAssertNil(model.failure); XCTAssertEqual(model.options?.rows.count, 1)
        XCTAssertEqual(access.sends, 0)
    }
    func testCollapseAndReopenRetireOldSelectionPermitAndQueuedRetry() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), old = try activate(model, expected)
        await model.load(old, access: access, current: { true })
        let value = try XCTUnwrap(model.options), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        model.leave(expected); _ = model.activate(expected); let count = access.resources.count
        await model.load(old, access: access, current: { true }); XCTAssertEqual(access.resources.count, count)
        XCTAssertNil(model.options); XCTAssertFalse(model.canOpen(route, context: expected, access: access))
    }
    func testClosedOrRetiredParentPreventsReadAndLatePublication() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { false }); XCTAssertTrue(access.resources.isEmpty)
        access.held = true; var visible = true; let entered = expectation(description: "read")
        access.entered = { entered.fulfill() }; let task = Task { await model.load(permit, access: access, current: { visible }) }
        await fulfillment(of: [entered], timeout: 1); visible = false
        access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.options); XCTAssertNil(model.failure)
    }
    func testAccountEpochChangesDuringReadCannotPublish() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(); access.held = true
        let expected = context(access), permit = try activate(model, expected), entered = expectation(description: "read")
        access.entered = { entered.fulfill() }; let task = Task { await model.load(permit, access: access, current: { true }) }
        await fulfillment(of: [entered], timeout: 1); access.identity = .init(accountID: 702, epoch: 2)
        access.pending[0].resume(returning: try access.response()); await task.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.options)
    }
    func testNamespaceAuthorityAndReaderReplacementRetireRoute() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true })
        let value = try XCTUnwrap(model.options), route = try XCTUnwrap(value.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        access.storageNamespace = "new-realm"; XCTAssertFalse(model.canOpen(route, context: expected, access: access))
        access.storageNamespace = expected.namespace; access.authorizationGeneration = UUID(); XCTAssertFalse(model.canOpen(route, context: expected, access: access))
        let other = Access(); other.authorizationGeneration = expected.read.authorizationGeneration
        XCTAssertFalse(model.canOpen(route, context: expected, access: other))
    }
    func testNewerReadWinsEvenIfPreviousRequestIgnoresCancellation() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [second], timeout: 1)
        access.activityID = 102; access.pending[1].resume(returning: try access.response()); await new.value
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertEqual(model.options?.rows.first?.activityID, 102); XCTAssertFalse(model.loading)
    }
    func testSwitchingExpandedSeriesRejectsPreviousCompletion() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        access.held = true; let entered = expectation(description: "first"); access.entered = { entered.fulfill() }
        let old = Task { await model.load(permit, access: access, current: { true }) }; await fulfillment(of: [entered], timeout: 1)
        let next = context(access, seriesID: 113), nextPermit = try activate(model, next)
        access.held = false; access.activityID = 102; await model.load(nextPermit, access: access, current: { true })
        access.activityID = 101; access.pending[0].resume(returning: try access.response()); await old.value
        XCTAssertNil(model.accepted(expected, access: access)); XCTAssertEqual(model.accepted(next, access: access)?.rows.first?.activityID, 102)
    }
    func testReturningFromWorkbenchRefreshesReadAndRetiresOldRoute() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(), expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true })
        let old = try XCTUnwrap(model.options), route = try XCTUnwrap(old.route(rowID: 0, context: expected.read, snapshotID: model.snapshotID))
        await model.load(permit, access: access, current: { true })
        XCTAssertFalse(model.canOpen(route, context: expected, access: access)); XCTAssertEqual(access.resources, [.occurrences, .occurrences]); XCTAssertEqual(access.sends, 0)
        XCTAssertNotNil(model.accepted(expected, access: access))
    }
    func testSignedOutAndUnconfiguredReadersCannotDispatchRead() async throws {
        let access = Access(), model = ClubSeriesOccurrenceReadModel(); access.identity = nil
        var expected = context(access), permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .signedOut); XCTAssertTrue(access.resources.isEmpty)
        access.identity = .init(accountID: 701, epoch: 2); access.isConfigured = false
        expected = context(access); permit = try activate(model, expected)
        await model.load(permit, access: access, current: { true }); XCTAssertEqual(model.failure, .notConfigured); XCTAssertTrue(access.resources.isEmpty)
    }
}
