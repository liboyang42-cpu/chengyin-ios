import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayReadCapabilityTests: XCTestCase {
    func testReadOnlyReadySnapshotCannotEnableCompletionControls() async throws {
        let wire = PlayReadCapabilityWire()
        let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
            transport: wire, enabled: [.reads])
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service,
            recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertNotNil(model.snapshot); XCTAssertTrue(model.available)
        XCTAssertFalse(model.canWrite)
        XCTAssertThrowsError(try model.review(nodeID: 701, evidence: .answer("synthetic")))
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testReadOnlyRunActionsDoNotReadOrMutatePauseStorage() async throws {
        let wire = PlayReadCapabilityWire(), storage = PlayReadPauseRecorder()
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: wire, enabled: [.reads])
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service,
            recovery: PlayMemoryCompletionRecovery(), pausedStorage: storage, currentSession: { session })
        await model.load(); XCTAssertFalse(model.canManageRun)
        model.startRun(now: 10); await model.pauseRun(now: 20, savedAt: 100)
        await model.endRun(now: 30, savedAt: 200); await model.restoreRun()
        XCTAssertEqual(model.clock.phase, .idle); XCTAssertEqual(storage.accesses, 0)
        XCTAssertFalse(model.remoteRunSaveFailed); XCTAssertEqual(wire.requests.count, 1)
    }
    func testHintGrantCannotReviewOrRetryClassicCompletion() async throws {
        let wire = PlayReadCapabilityWire()
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: wire, enabled: [.reads, .hints])
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service,
            recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await model.load(); XCTAssertTrue(model.canWrite)
        XCTAssertThrowsError(try model.review(nodeID: 701, evidence: .answer("synthetic")))
        XCTAssertFalse(model.canRetryExactBranch); await model.retryExactBranchAfterReadback()
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testReadOnlyPendingBranchCannotEnableOrDispatchRetry() async throws {
        let wire = PlayReadCapabilityWire(); wire.branch = true
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let recovery = PlayMemoryCompletionRecovery()
        let review = PlayCompletionReview(nodeID: 701, evidence: .answer("synthetic"),
            advance: try .init(actionID: "original-action", expectedVersion: 2), session: session, generation: 1, routeSessionID: 501)
        let key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        let prepared = try await recovery.prepare(.init(review: review), key: key)
        let dispatching = try await recovery.transition(prepared, to: .dispatching, key: key)
        let pending = try await recovery.transition(dispatching, to: .unknown, key: key)
        let service = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: wire, enabled: [.reads])
        let model = PlayExperienceCoordinator(scope: .activity(41), service: service,
            recovery: recovery, pausedStorage: PlayMemoryPausedStorage(), currentSession: { session })
        await model.load(); XCTAssertTrue(model.unresolved); XCTAssertEqual(model.phase, .unknown)
        XCTAssertFalse(model.canRetryExactBranch); await model.retryExactBranchAfterReadback()
        XCTAssertEqual(wire.requests.count, 2); XCTAssertTrue(model.unresolved)
        let retained = try await recovery.read(key)
        XCTAssertNotNil(retained)
        XCTAssertEqual(retained, pending)
    }
    func testServerSpectatorMarkerDoesNotGrantRegistrationOrCompletion() throws {
        for spectator in [false, true] {
            let raw = "{\"topicId\":71,\"registered\":false,\"leadSpectator\":\(spectator),\"playable\":true,\"nodes\":[{\"nodeId\":701,\"done\":false}]}"
            let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
            let snapshot = try PlaySnapshot(scope: .activity(41), result: result)
            XCTAssertEqual(result.leadSpectator, spectator); XCTAssertEqual(result.registered, false)
            XCTAssertEqual(snapshot.availability, .registrationRequired)
            XCTAssertThrowsError(try snapshot.validateAnswer(nodeID: 701, answer: "synthetic"))
        }
    }
}
@MainActor private final class PlayReadPauseRecorder: PlayPausedStorage {
    var accesses = 0
    private let storage = PlayMemoryPausedStorage()
    func read(key: String) async throws -> PlayPausedStorageSnapshot {
        accesses += 1
        return try await storage.read(key: key)
    }
    func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot {
        accesses += 1
        return try await storage.write(value, replacing: snapshot, key: key)
    }
}
@MainActor private final class PlayReadCapabilityWire: HTTPTransport {
    var requests: [URLRequest] = []
    var branch = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let body = branch ? (request.url?.lastPathComponent == "route-state" ? PlayExperienceSyntheticFixtures.route : PlayExperienceSyntheticFixtures.branch) : PlayExperienceSyntheticFixtures.classic
        return (PlayExperienceSyntheticFixtures.envelope(body), 200)
    }
}
