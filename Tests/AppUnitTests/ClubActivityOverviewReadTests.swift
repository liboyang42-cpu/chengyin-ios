import XCTest
@testable import Questify

@MainActor final class ClubActivityOverviewReadTests: XCTestCase {
    private final class Access: ClubGovernanceAccess {
        var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
        var isConfigured = true
        let storageNamespace = "synthetic-activity-overview"
        let allowsOfflineWrites = false
        var authorizationGeneration: UUID? = UUID()
        var reads = 0, sends = 0
        var entered: (() -> Void)?
        var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
        func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
            XCTAssertEqual(operation, .topics); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
            reads += 1
            return try await withCheckedThrowingContinuation { pending.append($0); entered?() }
        }
        func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
    }
    private let now = Date(timeIntervalSince1970: 1_791_691_200)
    private func context(_ access: Access) -> ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: 81), identity: access.identity, viewerRevision: 1,
              authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
    }
    private func response(id: Int = 91) throws -> ClubGovernanceSnapshot {
        let scope = ClubGovernanceScope(clubID: 81)
        let permission: ClubGovernanceValue = .object(["active": .bool(true), "club": .object(["id": .integer(81)]), "roleCodes": .array([]), "permissions": .array([])])
        return .init(operation: .topics, scope: scope, permissions: try ClubGovernancePermissions(value: permission, scope: scope),
                     value: .array([.object(["id": .integer(id), "name": .string("Synthetic route"), "startDate": .string("2026-10-11 12:00:00"), "locationCount": .integer(8)])]))
    }
    func testOneExistingReadPublishesBothListAndCalendarWithoutWrites() async throws {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        let entered = expectation(description: "topics"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(expected, access: access, now: { self.now }) }
        await fulfillment(of: [entered], timeout: 1)
        XCTAssertNil(model.snapshot); XCTAssertNil(model.activityOverview)
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertEqual(model.snapshot?.events.map(\.id), [91]); XCTAssertEqual(model.activityOverview?.rows.map(\.id), [91])
        XCTAssertEqual(model.activityOverview?.rows[0].stations, 8); XCTAssertEqual(model.activityOverview?.rows[0].status, .live)
        XCTAssertEqual(access.reads, 1); XCTAssertEqual(access.sends, 0)
    }
    func testClockIsSampledAfterResponseRatherThanBeforeSlowRead() async throws {
        let access = Access(), model = ClubEventCalendarReadModel()
        var clock = now.addingTimeInterval(-60)
        let entered = expectation(description: "topics"); access.entered = { entered.fulfill() }
        let task = Task { await model.load(context(access), access: access, now: { clock }) }
        await fulfillment(of: [entered], timeout: 1); clock = now
        access.pending[0].resume(returning: try response()); await task.value
        XCTAssertEqual(model.activityOverview?.observedAt, now); XCTAssertEqual(model.activityOverview?.rows[0].status, .live)
    }
    func testRefreshFailureClearsBothSnapshotsAndRetryRebuildsBoth() async throws {
        let access = Access(), model = ClubEventCalendarReadModel()
        for index in 0..<3 {
            let entered = expectation(description: "read \(index)"); access.entered = { entered.fulfill() }
            let task = Task { await model.load(context(access), access: access, now: { self.now }) }
            await fulfillment(of: [entered], timeout: 1); XCTAssertNil(model.snapshot); XCTAssertNil(model.activityOverview)
            if index == 1 { access.pending[index].resume(throwing: ClubGovernanceFailure.forbidden) }
            else { access.pending[index].resume(returning: try response()) }
            await task.value
            if index == 1 { XCTAssertNil(model.snapshot); XCTAssertNil(model.activityOverview); XCTAssertEqual(model.failure, .forbidden) }
            else { XCTAssertEqual(model.snapshot?.events.count, 1); XCTAssertEqual(model.activityOverview?.rows.count, 1) }
        }
    }
    func testNewRefreshWinsForBothProjectionsWhenOldReplyArrivesLast() async throws {
        let access = Access(), model = ClubEventCalendarReadModel()
        let first = expectation(description: "first"), second = expectation(description: "second")
        access.entered = { access.reads == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await model.load(context(access), access: access, now: { self.now }) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await model.load(context(access), access: access, now: { self.now }) }; await fulfillment(of: [second], timeout: 1)
        access.pending[1].resume(returning: try response(id: 92)); await new.value
        access.pending[0].resume(returning: try response(id: 91)); await old.value
        XCTAssertEqual(model.snapshot?.events.map(\.id), [92]); XCTAssertEqual(model.activityOverview?.rows.map(\.id), [92])
    }
    func testAccountEpochAndAuthorityRetirementRejectsLateRichRows() async throws {
        for change in 0..<3 {
            let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
            let entered = expectation(description: "read"); access.entered = { entered.fulfill() }
            let task = Task { await model.load(expected, access: access) }; await fulfillment(of: [entered], timeout: 1)
            if change == 0 { access.identity = .init(accountID: 702, epoch: 1) }
            if change == 1 { access.identity = .init(accountID: 701, epoch: 2) }
            if change == 2 { access.authorizationGeneration = UUID() }
            model.invalidate(); access.pending[0].resume(returning: try response()); await task.value
            XCTAssertNil(model.snapshot); XCTAssertNil(model.activityOverview)
        }
    }
    func testSuspendedOrSignedOutSourceCannotDispatchActivityRead() async {
        let access = Access(), model = ClubEventCalendarReadModel(), expected = context(access)
        model.suspend(); await model.load(expected, access: access); XCTAssertEqual(access.reads, 0)
        model.resume(); access.identity = nil; await model.load(expected, access: access); XCTAssertEqual(access.reads, 0)
        XCTAssertNil(model.activityOverview)
    }
}
