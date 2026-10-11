import XCTest
@testable import Questify

@MainActor final class ClubStatsOverviewReadTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        let storageNamespace = "synthetic-club-stats"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var reads = 0, sends = 0
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .stats); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
            reads += 1
            return try await withCheckedThrowingContinuation { pending.append($0); entered?() }
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; throw ClubGovernanceFailure.notConfigured
        }
    }
    private func context(_ access: Access, revision: UInt64 = 1) -> ClubGovernanceReadContext {
        .init(operation: .stats, scope: .init(clubID: 81), identity: access.identity,
              viewerRevision: revision, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
    private func activate(_ model: ClubStatsOverviewReadModel, _ context: ClubGovernanceReadContext) throws -> ClubStatsOverviewReadModel.Permit {
        model.bind(context); return try XCTUnwrap(model.activate(context))
    }
    private func response(count: Int = 3, owner: Bool = true) throws -> ClubGovernanceSnapshot {
        let scope = ClubGovernanceScope(clubID: 81)
        let permission: ClubGovernanceValue = .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array(owner ? [.string("CLUB_OWNER")] : []), "permissions": .array([])])
        return .init(operation: .stats, scope: scope, permissions: try .init(value: permission, scope: scope),
            value: .object(["clubId": .integer(81), "topicCount": .integer(count), "participants": .integer(10),
                "completed": .integer(3), "overallRate": .decimal(30), "topics": .array([])]))
    }
    func testLoadsExistingStatsReadAndOwnerSnapshotWithoutWrites() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let permit = try activate(model, expected), entered = expectation(description: "stats")
        access.entered = { entered.fulfill() }
        let task = Task { await model.load(permit, access: access) }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertTrue(model.loading); XCTAssertNil(model.snapshot)
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertEqual(model.accepted(expected, access: access)?.topicCount, 3)
        XCTAssertFalse(model.loading); XCTAssertNil(model.failure); XCTAssertEqual(access.sends, 0)
    }
    func testNewerRefreshWinsAgainstLateOldSuccessAndFailure() async throws {
        for fail in [false, true] {
            let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
            let permit = try activate(model, expected)
            let first = expectation(description: "first"), second = expectation(description: "second")
            access.entered = { access.reads == 1 ? first.fulfill() : second.fulfill() }
            let old = Task { await model.load(permit, access: access) }; await fulfillment(of: [first], timeout: 1)
            let new = Task { await model.load(permit, access: access) }; await fulfillment(of: [second], timeout: 1)
            access.pending[1].resume(returning: try response(count: 7)); await new.value
            if fail { access.pending[0].resume(throwing: ClubGovernanceFailure.forbidden) }
            else { access.pending[0].resume(returning: try response(count: 2)) }
            await old.value
            XCTAssertEqual(model.accepted(expected, access: access)?.topicCount, 7); XCTAssertNil(model.failure)
        }
    }
    func testRefreshFailureClearsOldDataAndRetryRestores() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let permit = try activate(model, expected)
        for index in 0..<3 {
            let started = expectation(description: "read \(index)"); access.entered = { started.fulfill() }
            let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
            XCTAssertNil(model.snapshot)
            if index == 1 { access.pending[index].resume(throwing: ClubGovernanceFailure.malformed) }
            else { access.pending[index].resume(returning: try response()) }
            await task.value
            if index == 1 { XCTAssertNil(model.accepted(expected, access: access)); XCTAssertEqual(model.failure, .malformed) }
            else { XCTAssertEqual(model.accepted(expected, access: access)?.participants, 10); XCTAssertNil(model.failure) }
        }
    }
    func testChangedIdentityEpochAndAuthoritySuppressLateSuccess() async throws {
        for change in 0..<3 {
            let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
            let permit = try activate(model, expected), started = expectation(description: "held")
            access.entered = { started.fulfill() }
            let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
            if change == 0 { access.identity = .init(accountID: 702, epoch: 1) }
            if change == 1 { access.identity = .init(accountID: 701, epoch: 2) }
            if change == 2 { access.authorizationGeneration = UUID() }
            access.pending[0].resume(returning: try response()); await task.value
            XCTAssertNil(model.accepted(expected, access: access)); XCTAssertNil(model.failure); XCTAssertFalse(model.loading)
        }
    }
    func testNewContextBindingRetiresOldRetryBeforeItCanClearCurrentRead() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), oldContext = context(access)
        let oldPermit = try activate(model, oldContext)
        let newContext = context(access, revision: 2), newPermit = try activate(model, context(access, revision: 2))
        let started = expectation(description: "new stats"); access.entered = { started.fulfill() }
        let task = Task { await model.load(newPermit, access: access) }; await fulfillment(of: [started], timeout: 1)
        await model.load(oldPermit, access: access)
        XCTAssertEqual(access.reads, 1); XCTAssertTrue(model.loading)
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertNotNil(model.accepted(newContext, access: access)); XCTAssertNil(model.accepted(oldContext, access: access))
    }
    func testLeaveReappearCannotReuseOldPermitOrLateResponse() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let oldPermit = try activate(model, expected), started = expectation(description: "held")
        access.entered = { started.fulfill() }
        let old = Task { await model.load(oldPermit, access: access) }; await fulfillment(of: [started], timeout: 1)
        model.leave(expected); let next = try XCTUnwrap(model.activate(expected))
        XCTAssertNotEqual(oldPermit, next)
        access.pending[0].resume(returning: try response()); await old.value
        await model.load(oldPermit, access: access)
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.loading); XCTAssertEqual(access.reads, 1)
    }
    func testSignedOutDisabledAndWrongAccessObjectCannotDispatch() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let permit = try activate(model, expected)
        await model.load(permit, access: Access()); XCTAssertEqual(access.reads, 0)
        access.identity = nil; await model.load(permit, access: access)
        XCTAssertEqual(model.failure, .signedOut); XCTAssertEqual(access.reads, 0)
        access.identity = expected.identity; access.isConfigured = false; await model.load(permit, access: access)
        XCTAssertEqual(model.failure, .notConfigured); XCTAssertEqual(access.reads, 0)
    }
    func testSnapshotWithoutOwnerPermissionCannotAppear() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let permit = try activate(model, expected), started = expectation(description: "stats")
        access.entered = { started.fulfill() }
        let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
        access.pending[0].resume(returning: try response(owner: false)); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNotNil(model.failure)
    }
    func testCancellationCannotPublishAndRetiredRetryCannotDispatch() async throws {
        let access = Access(), model = ClubStatsOverviewReadModel(), expected = context(access)
        let permit = try activate(model, expected), started = expectation(description: "held")
        access.entered = { started.fulfill() }
        let task = Task { await model.load(permit, access: access) }; await fulfillment(of: [started], timeout: 1)
        task.cancel(); access.pending[0].resume(returning: try response()); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(model.failure); XCTAssertFalse(model.loading)
        model.leave(expected); await model.load(permit, access: access)
        XCTAssertEqual(access.reads, 1); XCTAssertEqual(access.sends, 0)
    }
}
