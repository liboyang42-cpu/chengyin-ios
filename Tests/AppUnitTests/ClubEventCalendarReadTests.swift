import XCTest
@testable import Questify

@MainActor final class ClubEventCalendarReadTests: XCTestCase {
    @MainActor private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        let storageNamespace = "synthetic-calendar"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var reads = 0, sends = 0
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .topics); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
            reads += 1
            return try await withCheckedThrowingContinuation { continuation in pending.append(continuation); entered?() }
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue {
            sends += 1; throw ClubGovernanceFailure.notConfigured
        }
    }
    private func context(_ access: Access, revision: UInt64 = 1) -> ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: 81), identity: access.identity,
              viewerRevision: revision, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
    private func response(id: Int = 91) throws -> ClubGovernanceSnapshot {
        let scope = ClubGovernanceScope(clubID: 81)
        let permission: ClubGovernanceValue = .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array([])])
        return .init(operation: .topics, scope: scope, permissions: try ClubGovernancePermissions(value: permission, scope: scope),
                     value: .array([.object(["id": .integer(id), "name": .string("Synthetic event"), "startDate": .string("2028-02-29")])]))
    }
    func testReadUsesExistingTopicsAndExposesExactAcceptedRowsWithoutWrites() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let entered = expectation(description: "topics read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(expected, access: access) }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertTrue(model.loading); XCTAssertNil(model.snapshot)
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertEqual(model.snapshot?.events.map(\.id), [91]); XCTAssertFalse(model.loading)
        XCTAssertTrue(model.canSelect(expected, access: access)); XCTAssertEqual(access.sends, 0)
    }
    func testLatestRefreshWinsEvenWhenEarlierReadIgnoresCancellation() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.reads == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(expected, access: access) }
        await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(expected, access: access) }
        await fulfillment(of: [second], timeout: 1)
        access.pending[1].resume(returning: try response(id: 92)); await new.value
        access.pending[0].resume(returning: try response(id: 91)); await old.value
        XCTAssertEqual(model.snapshot?.events.map(\.id), [92]); XCTAssertNil(model.failure)
    }
    func testRefreshFailureClearsOldRowsAndRetryCanSucceed() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        for index in 0..<3 {
            let entered = expectation(description: "read \(index)"); access.entered = { entered.fulfill() }
            let task = Task { await model.load(expected, access: access) }
            await fulfillment(of: [entered], timeout: 1)
            XCTAssertNil(model.snapshot)
            if index == 1 { access.pending[index].resume(throwing: ClubGovernanceFailure.forbidden) }
            else { access.pending[index].resume(returning: try response()) }
            await task.value
            if index == 1 { XCTAssertNil(model.snapshot); XCTAssertEqual(model.failure, .forbidden) }
            else { XCTAssertEqual(model.snapshot?.events.count, 1); XCTAssertNil(model.failure) }
        }
    }
    func testIdentityEpochAndAuthorityChangeRejectLateResponses() async throws {
        for change in 0..<3 {
            let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
            let entered = expectation(description: "read \(change)"); access.entered = { entered.fulfill() }
            let task = Task { await model.load(expected, access: access) }
            await fulfillment(of: [entered], timeout: 1)
            if change == 0 { access.identity = .init(accountID: 702, epoch: 1) }
            if change == 1 { access.identity = .init(accountID: 701, epoch: 2) }
            if change == 2 { access.authorizationGeneration = UUID() }
            model.invalidate()
            access.pending[0].resume(returning: try response()); await task.value
            XCTAssertNil(model.snapshot); XCTAssertNil(model.failure); XCTAssertFalse(model.loading)
        }
    }
    func testSignedOutStaleAuthorityAndSuspendedScreenNeverBeginReads() async {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        access.identity = nil
        await model.load(expected, access: access)
        XCTAssertEqual(access.reads, 0)
        access.identity = expected.identity; access.authorizationGeneration = UUID()
        await model.load(expected, access: access); XCTAssertEqual(access.reads, 0)
        model.suspend()
        await model.load(context(access), access: access); XCTAssertEqual(access.reads, 0)
    }
    func testDisappearRejectsLateReadAndCoveredSourceCannotSelectAgain() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let first = expectation(description: "first"); access.entered = { first.fulfill() }
        let task = Task { await model.load(expected, access: access) }
        await fulfillment(of: [first], timeout: 1)
        model.suspend(); access.pending[0].resume(returning: try response()); await task.value
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.canSelect(expected, access: access))
        model.resume()
        let second = expectation(description: "second"); access.entered = { second.fulfill() }
        let reload = Task { await model.load(expected, access: access) }
        await fulfillment(of: [second], timeout: 1)
        access.pending[1].resume(returning: try response()); await reload.value
        model.suspend()
        XCTAssertTrue(model.accepted(expected, access: access), "A pushed detail keeps the captured topic alive")
        XCTAssertFalse(model.canSelect(expected, access: access), "A queued tap on the covered list cannot push again")
        model.resume(); XCTAssertTrue(model.canSelect(expected, access: access))
    }
    func testDifferentAccessObjectAndRoleRevisionCannotUseAcceptedSnapshot() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(expected, access: access) }
        await fulfillment(of: [entered], timeout: 1)
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertFalse(model.accepted(context(access, revision: 2), access: access))
        let replacement = Access(); replacement.authorizationGeneration = access.authorizationGeneration
        XCTAssertFalse(model.accepted(expected, access: replacement))
    }
    func testCancellationDoesNotPublishLateSuccessOrError() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(expected, access: access) }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel(); access.pending[0].resume(returning: try response()); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(model.failure); XCTAssertFalse(model.loading)
    }
    func testAuthorityLossEvenWithoutViewInvalidationEndsLoadingWithoutExposingData() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(expected, access: access) }
        await fulfillment(of: [entered], timeout: 1)
        access.authorizationGeneration = UUID()
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(model.failure); XCTAssertFalse(model.loading)
    }

}
