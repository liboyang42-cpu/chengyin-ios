import XCTest
@testable import QuestifyCore

@MainActor final class RoamEnrolledChaptersTests: XCTestCase {
    private func identity(account: Int = 1, epoch: UInt64 = 2, namespace: String = "roam") throws -> RoamExperienceIdentity {
        .init(scope: try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com")!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func row(_ id: Int = 1, owner: Int = 1, status: Int = 2, suffix: String = "") throws -> TicketWalletTicket {
        try JSONDecoder().decode(TicketWalletTicket.self, from: Data("{\"id\":\(id),\"ownerType\":\(owner),\"ownerId\":\(100+id),\"registrationStatus\":\(status),\"cmsTopic\":{\"name\":\"Synthetic route \(id)\"}\(suffix)}".utf8))
    }
    private func setup() throws -> (Roam, Tickets, RoamEnrolledChaptersModel) {
        let roam = Roam(identity: try identity()), tickets = Tickets()
        tickets.result = .init(tickets: [try row(), try row(2, owner: 2)])
        let model = RoamEnrolledChaptersModel(roam: roam, tickets: tickets)
        return (roam, tickets, model)
    }
    func testConstructionAndInvisibleLoadDoNotRead() async throws {
        let (roam, tickets, model) = try setup(); await model.load()
        XCTAssertEqual(tickets.reads, 0); XCTAssertEqual(roam.reads, 0); XCTAssertNil(model.snapshot)
    }
    func testExistingWalletReadProjectsOnlyActualTopicRowsAndOrder() async throws {
        let (_, tickets, model) = try setup(); tickets.result = .init(tickets: [try row(3), try row(2, owner: 2), try row(1)])
        model.appear(); await model.load(); XCTAssertEqual(model.snapshot?.topics.map(\.id), [3,1]); XCTAssertEqual(tickets.reads, 1)
    }
    func testActivityPartialFailureDoesNotHideSuccessfulTopicLane() async throws {
        let (_, tickets, model) = try setup(); tickets.result = .init(tickets: [try row()], partialFailure: .init(lane: .activity, issue: .network))
        model.appear(); await model.load(); XCTAssertEqual(model.snapshot?.topics.count, 1); XCTAssertNil(model.issue)
    }
    func testRoutePartialFailureIsErrorNotEmptyOrOtherLaneRows() async throws {
        let (_, tickets, model) = try setup(); tickets.result = .init(tickets: [try row(2, owner: 2)], partialFailure: .init(lane: .route, issue: .network))
        model.appear(); await model.load(); XCTAssertNil(model.snapshot); XCTAssertEqual(model.issue, .network)
    }
    func testSuccessfulEmptyRouteLaneRemainsEmptyEvenIfActivityLaneFailed() async throws {
        let (_, tickets, model) = try setup(); tickets.result = .init(tickets: [], partialFailure: .init(lane: .activity, issue: .network))
        model.appear(); await model.load(); XCTAssertEqual(model.snapshot?.topics.count, 0); XCTAssertNil(model.issue)
    }
    func testDuplicateRegistrationIDsAcrossLanesFailClosed() throws {
        XCTAssertThrowsError(try RoamEnrolledChaptersProjection.topics(.init(tickets: [try row(), try row(owner: 2)])))
    }
    func testUnknownOwnerTypeNeverGuessedFromTopicName() throws {
        XCTAssertThrowsError(try RoamEnrolledChaptersProjection.topics(.init(tickets: [try row(owner: 99)])))
    }
    func testInconsistentActivityOrTopicIDsNeverRoutedByNumberCoincidence() throws {
        for suffix in [",\"activityId\":101", ",\"topicId\":999"] {
            XCTAssertThrowsError(try RoamEnrolledChaptersProjection.topics(.init(tickets: [try row(suffix: suffix)])))
        }
        let valid = try RoamEnrolledChaptersProjection.topics(.init(tickets: [try row(suffix: ",\"topicId\":101")]))
        XCTAssertEqual(valid.count, 1)
    }
    func testUnknownPendingCancelledExpiredStatusesAreVisibleButCannotOpen() async throws {
        let (_, tickets, model) = try setup(); tickets.result = .init(tickets: try [1,3,4,99].enumerated().map { try row($0.offset+1, status: $0.element) })
        model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(snapshot.topics.count, 4)
        for ticket in snapshot.topics { XCTAssertNil(model.select(registrationID: ticket.id, snapshotID: snapshot.id)) }
    }
    func testSelectedRegistrationUsesExactCurrentReadIDNotTopicID() async throws {
        let (_, tickets, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        let target = try XCTUnwrap(model.select(registrationID: 1, snapshotID: snapshot.id))
        XCTAssertEqual(target.registrationID, 1); XCTAssertTrue(model.mayRemainOpen(target)); XCTAssertEqual(tickets.details, [])
        XCTAssertNil(model.select(registrationID: 101, snapshotID: snapshot.id)); XCTAssertNil(model.select(registrationID: 2, snapshotID: snapshot.id))
    }
    func testStaleSnapshotAndQueuedTapAreRejected() async throws {
        let (_, _, model) = try setup(); model.appear(); await model.load(); let old = try XCTUnwrap(model.snapshot)
        await model.load(); XCTAssertNil(model.select(registrationID: 1, snapshotID: old.id))
        let current = try XCTUnwrap(model.snapshot); model.cancelPending(); XCTAssertNil(model.select(registrationID: 1, snapshotID: current.id))
    }
    func testPushedDetailRemainsUntilBackButFullExitClearsIt() async throws {
        let (_, _, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
        let target = try XCTUnwrap(model.select(registrationID: 1, snapshotID: snapshot.id)); model.cancelPending()
        XCTAssertTrue(model.mayRemainOpen(target)); model.invalidate(); XCTAssertFalse(model.mayRemainOpen(target)); XCTAssertNil(model.snapshot)
    }
    func testReturnRefreshReadsCurrentRegistrationState() async throws {
        let (_, tickets, model) = try setup(); model.appear(); await model.load(); model.cancelPending()
        tickets.result = .init(tickets: [try row(status: 3)]); model.appear(); await model.load()
        let snapshot = try XCTUnwrap(model.snapshot); XCTAssertEqual(snapshot.topics.first?.status, .cancelled)
        XCTAssertNil(model.select(registrationID: 1, snapshotID: snapshot.id)); XCTAssertEqual(tickets.reads, 2)
    }
    func testFailureClearsOldSnapshotAndRetryUsesNewSource() async throws {
        let (_, tickets, model) = try setup(); model.appear(); await model.load(); tickets.failure = APIError.httpStatus(503)
        await model.load(); XCTAssertNil(model.snapshot); XCTAssertEqual(model.issue, .failure)
        tickets.failure = nil; await model.load(); XCTAssertEqual(model.snapshot?.topics.count, 1); XCTAssertNil(model.issue)
    }
    func testMissingIdentityOrAuthenticationCannotStartRead() async throws {
        let (roam, tickets, model) = try setup(); roam.identity = nil; model.appear(); await model.load()
        XCTAssertEqual(model.issue, .login); XCTAssertEqual(tickets.reads, 0)
        roam.identity = try identity(); tickets.isAuthenticated = false; await model.load(); XCTAssertEqual(model.issue, .login); XCTAssertEqual(tickets.reads, 0)
    }
    func testTicketConfigurationRespectedButNoNewRoamRemoteGrantRequired() async throws {
        let (roam, tickets, model) = try setup(); roam.isConfigured = false; model.appear(); await model.load(); XCTAssertEqual(tickets.reads, 1)
        tickets.isConfigured = false; await model.load(); XCTAssertEqual(model.issue, .notConfigured); XCTAssertEqual(tickets.reads, 1)
    }
    func testRoamAccountEpochAndExactNamespaceRetireRowsAndTarget() async throws {
        let identities = try [identity(account: 2), identity(epoch: 3), identity(namespace: "other")]
        for value in identities {
            let (roam, _, model) = try setup(); model.appear(); await model.load(); let snapshot = try XCTUnwrap(model.snapshot)
            let target = try XCTUnwrap(model.select(registrationID: 1, snapshotID: snapshot.id)); roam.identity = value
            XCTAssertNil(model.snapshot); XCTAssertFalse(model.mayRemainOpen(target))
        }
    }
    func testUnicodeScopeKeysAndReaderObjectsStayDistinct() throws {
        let (roam, tickets, model) = try setup(); roam.identity = try identity(namespace: "\u{00E9}"); let owner = model.owner
        roam.identity = try identity(namespace: "e\u{0301}"); XCTAssertNotEqual(owner, model.owner)
        XCTAssertNotEqual(model.owner, RoamEnrolledChaptersOwner(roam: roam, tickets: Tickets()))
        XCTAssertNotEqual(model.owner, RoamEnrolledChaptersOwner(roam: Roam(identity: roam.identity), tickets: tickets))
    }
    func testWalletScopeAuthAndConfigurationRetireRows() async throws {
        let (_, tickets, model) = try setup(); model.appear(); await model.load(); tickets.scope = UUID(); XCTAssertNil(model.snapshot)
        await model.load(); tickets.isAuthenticated = false; XCTAssertNil(model.snapshot)
        tickets.isAuthenticated = true; await model.load(); tickets.isConfigured = false; XCTAssertNil(model.snapshot)
    }
    func testLateSuccessAfterOwnerChangeIsDiscarded() async throws {
        let (roam, tickets, model) = try setup(); tickets.afterRead = { roam.identity = nil }; model.appear(); await model.load()
        XCTAssertNil(model.snapshot); XCTAssertNil(model.issue)
    }
    func testLateFailureAfterScopeChangeIsDiscarded() async throws {
        let (_, tickets, model) = try setup(); tickets.afterRead = { tickets.scope = UUID() }; tickets.failure = APIError.httpStatus(503)
        model.appear(); await model.load(); XCTAssertNil(model.snapshot); XCTAssertNil(model.issue)
    }
    func testCancelledInFlightReadCannotPublishOrEnableTarget() async throws {
        let (_, tickets, model) = try setup(); tickets.suspend = true; model.appear()
        let task = Task { await model.load() }; while tickets.pending.isEmpty { await Task.yield() }
        task.cancel(); tickets.pending.removeFirst().resume(returning: tickets.result); await task.value
        XCTAssertNil(model.snapshot); XCTAssertNil(model.issue); XCTAssertFalse(model.isLoading)
    }
    func testOlderReadCannotReplaceNewerSnapshot() async throws {
        let (_, tickets, model) = try setup(); tickets.suspend = true; model.appear()
        let old = Task { await model.load() }; while tickets.pending.count < 1 { await Task.yield() }
        let next = Task { await model.load() }; while tickets.pending.count < 2 { await Task.yield() }
        let newer = tickets.pending.removeLast(), older = tickets.pending.removeFirst()
        newer.resume(returning: .init(tickets: [try row(3)])); await next.value
        older.resume(returning: .init(tickets: [try row()])); await old.value
        XCTAssertEqual(model.snapshot?.topics.map(\.id), [3])
    }
    func testDepartureRetiresInFlightReadBeforeCompletion() async throws {
        let (_, tickets, model) = try setup(); tickets.suspend = true; model.appear()
        let task = Task { await model.load() }; while tickets.pending.isEmpty { await Task.yield() }
        model.invalidate(); tickets.pending.removeFirst().resume(returning: tickets.result); await task.value
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.isLoading)
    }
    @MainActor private final class Roam: RoamExperienceReading {
        var identity: RoamExperienceIdentity?; var isConfigured = true; var isOfflineExample = true; var reads = 0
        init(identity: RoamExperienceIdentity?) { self.identity = identity }
        func history() throws -> [RoamHistoryRecord] { reads += 1; return [] }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
    }
    @MainActor private final class Tickets: TicketWalletReading {
        var isConfigured = true; var isAuthenticated = true; var isOfflineExample = true; var scope = UUID()
        var result = TicketWalletSnapshot(tickets: []); var reads = 0; var details: [Int] = []; var failure: Error?
        var afterRead: (() -> Void)?; var suspend = false; var pending: [CheckedContinuation<TicketWalletSnapshot, Error>] = []
        func ticketWallet() async throws -> TicketWalletSnapshot {
            reads += 1; afterRead?(); if let failure { throw failure }
            if suspend { return try await withCheckedThrowingContinuation { pending.append($0) } }; return result
        }
        func ticketDetail(id: Int) async throws -> TicketWalletTicket { details.append(id); throw APIError.notConfigured }
    }
}
