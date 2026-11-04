import XCTest
@testable import Questify

@MainActor private final class NearbyOwnedDelayedService: TeamServing {
    var authority: TeamServiceAuthority { .readOnly }
    private var pending: CheckedContinuation<[OwnedTeam], Error>?
    var started: Bool { pending != nil }
    func myTeams(session: TeamSession) async throws -> [OwnedTeam] {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ rows: [OwnedTeam]) { let request = pending; pending = nil; request?.resume(returning: rows) }
    func fail() { let request = pending; pending = nil; request?.resume(throwing: TeamFailure.invalidContract) }
    func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail { throw TeamFailure.notConfigured }
    func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext { throw TeamFailure.notConfigured }
    func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome { .notSent }
    func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { nil }
}

@MainActor final class RoamNearbyOwnedTeamsLifecycleTests: XCTestCase {
    private final class Owner { var key = "account-901:epoch-1:grant-1"; var session: TeamSession? }
    private func makeOwner() throws -> Owner {
        let owner = Owner(); owner.session = try TeamSyntheticFixtures.session(); return owner
    }
    private func rows(_ id: Int) throws -> [OwnedTeam] {
        try JSONDecoder().decode([OwnedTeam].self, from: Data("[{\"id\":\(id),\"title\":\"Synthetic\",\"status\":0}]".utf8))
    }
    private func coordinator(_ service: NearbyOwnedDelayedService, _ owner: Owner) -> TeamCoordinator {
        TeamCoordinator(service: service, journal: TeamMemoryJournal(), currentSession: { owner.session })
    }
    private func waitForRead(_ service: NearbyOwnedDelayedService) async {
        for _ in 0..<1000 { if service.started { return }; await Task.yield() }
        XCTFail("Synthetic read did not start")
    }
    func testDisappearanceRejectsLateSameOwnerReadback() async throws {
        let owner = try makeOwner(), service = NearbyOwnedDelayedService(), model = NearbyOwnedTeamsReadModel()
        let reader = coordinator(service, owner)
        let task = Task { await model.load(owner: owner.key, makeCoordinator: { reader }, currentOwner: { owner.key }) }
        await waitForRead(service); model.cancel(); service.finish(try rows(41)); await task.value
        XCTAssertEqual(model.currentStatus(owner: owner.key), .loading)
        XCTAssertTrue(model.currentRows(owner: owner.key).isEmpty)
    }
    func testNewVisitCannotBeReplacedByOldSameAccountCompletion() async throws {
        let owner = try makeOwner(), first = NearbyOwnedDelayedService(), second = NearbyOwnedDelayedService()
        let model = NearbyOwnedTeamsReadModel(), a = coordinator(first, owner), b = coordinator(second, owner)
        let old = Task { await model.load(owner: owner.key, makeCoordinator: { a }, currentOwner: { owner.key }) }
        await waitForRead(first)
        let fresh = Task { await model.load(owner: owner.key, makeCoordinator: { b }, currentOwner: { owner.key }) }
        await waitForRead(second); second.finish(try rows(42)); await fresh.value
        first.finish(try rows(41)); await old.value
        XCTAssertEqual(model.currentStatus(owner: owner.key), .loaded)
        XCTAssertEqual(model.currentRows(owner: owner.key).map(\.id), [42])
    }
    func testChangedAccountEpochOrGrantHidesOldRowsImmediately() async throws {
        let owner = try makeOwner(), service = NearbyOwnedDelayedService(), model = NearbyOwnedTeamsReadModel()
        let reader = coordinator(service, owner), original = owner.key
        let task = Task { await model.load(owner: original, makeCoordinator: { reader }, currentOwner: { owner.key }) }
        await waitForRead(service); owner.key = "account-902:epoch-2:grant-2"
        owner.session = try TeamSyntheticFixtures.session(epoch: 2, accountID: 902)
        service.finish(try rows(41)); await task.value
        XCTAssertEqual(model.currentStatus(owner: owner.key), .loading)
        XCTAssertTrue(model.currentRows(owner: owner.key).isEmpty)
    }
    func testFailureIsNotSuccessfulEmptyMembership() async throws {
        let owner = try makeOwner(), service = NearbyOwnedDelayedService(), model = NearbyOwnedTeamsReadModel()
        let reader = coordinator(service, owner)
        let task = Task { await model.load(owner: owner.key, makeCoordinator: { reader }, currentOwner: { owner.key }) }
        await waitForRead(service); service.fail(); await task.value
        XCTAssertEqual(model.currentStatus(owner: owner.key), .failed("team.loadFailed"))
        XCTAssertTrue(model.currentRows(owner: owner.key).isEmpty)
    }
    func testSignedOutCannotConstructSuccessfulMembership() async throws {
        let owner = try makeOwner(); owner.session = nil
        let service = NearbyOwnedDelayedService(), model = NearbyOwnedTeamsReadModel(), reader = coordinator(service, owner)
        await model.load(owner: owner.key, makeCoordinator: { reader }, currentOwner: { owner.key })
        XCTAssertFalse(service.started)
        XCTAssertEqual(model.currentStatus(owner: owner.key), .failed("team.signIn"))
    }
    func testCancelledQueuedReadDoesNotRetireNewerLoadedVisit() async throws {
        let owner = try makeOwner(), service = NearbyOwnedDelayedService(), model = NearbyOwnedTeamsReadModel()
        let reader = coordinator(service, owner)
        let initial = Task { await model.load(owner: owner.key, makeCoordinator: { reader }, currentOwner: { owner.key }) }
        await waitForRead(service); service.finish(try rows(42)); await initial.value
        var constructed = false
        let cancelled = Task { await model.load(owner: owner.key, makeCoordinator: { constructed = true; return reader }, currentOwner: { owner.key }) }
        cancelled.cancel(); await cancelled.value
        XCTAssertFalse(constructed)
        XCTAssertEqual(model.currentStatus(owner: owner.key), .loaded)
        XCTAssertEqual(model.currentRows(owner: owner.key).map(\.id), [42])
    }
}
