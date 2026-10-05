import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayExperienceTests: XCTestCase {
    private func session(_ account: Int = 9001, epoch: UInt64 = 1, namespace: String = "synthetic-cn") throws -> PlayExperienceSession { try .init(accountID: account, epoch: epoch, namespace: namespace, token: "synthetic-token") }
    private func service(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability> = [.reads, .classicCompletion, .runPersistence, .hints, .leader, .advanced, .playerCommands, .circle, .directorCommands]) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: enabled)
    }
    private func model(_ transport: any HTTPTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: try service(transport), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: current)
    }
    func testDefaultServiceCapabilitiesNeverDispatch() async throws {
        let transport = PlayExperienceTestTransport { _ in XCTFail("Dormant service sent a request"); return (Data(), 200) }
        let api = PlayExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        do { _ = try await api.nodes(scope: .activity(41), token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        XCTAssertEqual(transport.requests.count, 0)
    }
    func testBranchAnswerCarriesOnlySourceTokenAndOneScope() async throws {
        let transport = PlayRecoveryRecordingTransport(); for path in ["answer", "checkin", "sensor-result"] { transport.responses["/fixture/api/play/" + path] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701}"#), 200) }
        _ = try await service(transport).complete(scope: .topic(71), nodeID: 701, evidence: .answer("A & + 中文"), advance: .init(actionID: "same-action", expectedVersion: 2), token: "synthetic")
        let request = try XCTUnwrap(transport.requests.first), body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/fixture/api/play/answer")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data"))
        for field in ["topicId", "nodeId", "answer", "routeActionId", "expectedRouteVersion"] { XCTAssertTrue(body.contains("name=\"\(field)\"")) }
        for field in ["activityId", "outcomeCode", "targetNodeId", "latitude", "longitude"] { XCTAssertFalse(body.contains("name=\"\(field)\"")) }
    }
    func testQRDoesNotManufactureNodeIDField() async throws {
        let transport = PlayRecoveryRecordingTransport(); for path in ["answer", "checkin", "sensor-result"] { transport.responses["/fixture/api/play/" + path] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701}"#), 200) }
        _ = try await service(transport).complete(scope: .activity(41), nodeID: 701, evidence: .scan("synthetic-code"), advance: nil, token: "synthetic")
        let body = String(decoding: transport.requests[0].httpBody!, as: UTF8.self)
        XCTAssertFalse(body.contains("nodeId")); XCTAssertTrue(body.contains("name=\"code\""))
    }
    func testWrongCoordinateSystemRejectedBeforeDispatch() async throws {
        let transport = PlayExperienceTestTransport { _ in XCTFail(); return (Data(), 200) }
        do { _ = try await service(transport).complete(scope: .activity(41), nodeID: 701, evidence: .location(longitude: 121, latitude: 31, coordinateSystem: "WGS84"), advance: nil, token: "synthetic"); XCTFail() } catch {}
        XCTAssertEqual(transport.requests.count, 0)
    }
    func testSensorBodyUsesJSONAndNumericRouteVersion() async throws {
        let transport = PlayRecoveryRecordingTransport(); for path in ["answer", "checkin", "sensor-result"] { transport.responses["/fixture/api/play/" + path] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701}"#), 200) }
        _ = try await service(transport).complete(scope: .topic(71), nodeID: 701, evidence: .sensor(type: "still", payload: ["heldSec": .int(5)]), advance: .init(actionID: "same", expectedVersion: 2), token: "synthetic")
        let request = transport.requests[0], json = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(json["expectedRouteVersion"], .int(2)); XCTAssertEqual(json["payload"]["heldSec"], .int(5)); XCTAssertEqual(json["activityId"], .null)
    }
    func testMerchantModeNeverTreatsPhotoProofAsCompletion() throws {
        var raw = try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.mode2).object!
        let document: PlayExperienceDocument = try PlayWireValue.object(raw).decoded()
        XCTAssertEqual(PlayNodeTask.resolve(mode: 2, node: document.base.nodes[0]), .merchantVerify)
        XCTAssertFalse(try PlaySnapshot(scope: .activity(41), result: document.base).isDone(document.base.nodes[0]))
        var node = raw["nodes"]!.array![0].object!; node["arrived"] = .bool(false); node["selfReported"] = .bool(false)
        raw["nodes"] = .array([.object(node)]); let fresh: PlayExperienceDocument = try PlayWireValue.object(raw).decoded()
        XCTAssertEqual(PlayNodeTask.resolve(mode: 2, node: fresh.base.nodes[0]), .merchantScan)
    }
    func testUnknownValidationMethodHasNoFallback() throws {
        let node: PlayNode = try PlayExperienceSyntheticFixtures.wire(#"{"nodeId":1,"validationMethod":999,"needGps":true}"#).decoded()
        XCTAssertEqual(PlayNodeTask.resolve(mode: 1, node: node), .unsupported)
    }
    func testUnknownCompletionRemainsLockedAfterUnchangedReadback() async throws {
        let current = try session()
        let transport = PlayRecoveryRecordingTransport()
        transport.responses["/fixture/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
        transport.responses["/fixture/api/play/answer"] = .failure(.unknownResult)
        let coordinator = try model(transport, current: { current }); await coordinator.load()
        let review = try coordinator.review(nodeID: 701, evidence: .answer("synthetic")); await coordinator.submit(review); await coordinator.load()
        XCTAssertTrue(coordinator.unresolved); XCTAssertFalse(coordinator.canWrite)
        XCTAssertThrowsError(try coordinator.review(nodeID: 701, evidence: .answer("again")))
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testReadbackDoneReconcilesWithoutInventingReward() async throws {
        let current = try session(), transport = PlayRecoveryRecordingTransport()
        transport.queues["/fixture/api/play/nodes"] = [.reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200), .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.complete), 200)]
        transport.responses["/fixture/api/play/answer"] = .failure(.unknownResult)
        let coordinator = try model(transport, current: { current }); await coordinator.load()
        await coordinator.submit(try coordinator.review(nodeID: 701, evidence: .answer("synthetic"))); await coordinator.load()
        XCTAssertFalse(coordinator.unresolved); XCTAssertNil(coordinator.reward); XCTAssertEqual(coordinator.snapshot?.availability, .completed)
    }
    func testReviewInvalidatedByAccountEpochChange() async throws {
        var current: PlayExperienceSession? = try session()
        let transport = PlayExperienceTestTransport { _ in (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200) }
        let coordinator = try model(transport, current: { current }); await coordinator.load()
        let review = try coordinator.review(nodeID: 701, evidence: .answer("synthetic")); current = try session(epoch: 2)
        await coordinator.submit(review); XCTAssertEqual(transport.requests.count, 1); XCTAssertFalse(coordinator.canWrite)
    }
    func testStaleReadCannotClearNewerSnapshot() async throws {
        let current = try session(); var calls = 0; var coordinator: PlayExperienceCoordinator!
        let transport = PlayExperienceTestTransport { _ in
            calls += 1
            if calls == 1 { await coordinator.load(); return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200) }
            return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.complete), 200)
        }
        coordinator = try model(transport, current: { current }); await coordinator.load()
        XCTAssertEqual(coordinator.snapshot?.availability, .completed)
    }
    func testPausedReconciliationHonorsNewerRemoteAndTombstone() throws {
        let local = try PlayPausedRecord(elapsedSeconds: 20, savedAt: 100)
        let remote = try PlayPausedRecord(elapsedSeconds: 10, savedAt: 200)
        XCTAssertEqual(PlayPausedRecord.reconcile(local: local, remote: .init(record: remote)), remote)
        XCTAssertNil(PlayPausedRecord.reconcile(local: local, remote: .init(endedAt: 100)))
        XCTAssertEqual(PlayPausedRecord.reconcile(local: local, remote: nil), local)
        XCTAssertThrowsError(try PlayPausedRecord(elapsedSeconds: 604801, savedAt: 100))
        XCTAssertThrowsError(try JSONDecoder().decode(PlayPausedRecord.self, from: Data(#"{"elapsedSeconds":-1,"savedAt":20}"#.utf8)))
    }
    func testRunClockDoesNotCountBackgroundTime() throws {
        var clock = PlayRunClock(); try clock.start(monotonicNow: 10)
        let paused = try clock.pause(monotonicNow: 20, savedAt: 100); XCTAssertEqual(paused.elapsedSeconds, 10)
        try clock.start(monotonicNow: 1000); XCTAssertEqual(clock.elapsed(monotonicNow: 1001), 11)
    }
    func testRunStorageSeparatesAccountNamespaceAndActivityTopic() throws {
        let a = PlayRunStorageKey.make(session: try session(), scope: .activity(41))
        XCTAssertNotEqual(a, PlayRunStorageKey.make(session: try session(9002), scope: .activity(41)))
        XCTAssertNotEqual(a, PlayRunStorageKey.make(session: try session(namespace: "synthetic-us"), scope: .activity(41)))
        XCTAssertNotEqual(a, PlayRunStorageKey.make(session: try session(), scope: .topic(41)))
        XCTAssertEqual(a, PlayRunStorageKey.make(session: try session(epoch: 2), scope: .activity(41)))
    }
    func testLeaderboardRejectsUnmatchedRankAndDoesNotInferMissingScores() throws {
        let board = try PlayCompanionLeaderboard(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.board))
        XCTAssertEqual(board.me.score, 1)
        XCTAssertThrowsError(try PlayCompanionLeaderboard(PlayExperienceSyntheticFixtures.wire(#"{"list":[],"me":{"memberId":1,"rank":1,"score":0}}"#)))
        XCTAssertThrowsError(try PlayCompanionLeaderboard(PlayExperienceSyntheticFixtures.wire(#"{"list":[],"me":{"memberId":1}}"#)))
    }
    func testLeaderIdentityAndAllArrivedAreRequired() throws {
        let progress = try PlayLeadProgress(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.lead))
        XCTAssertTrue(progress.allArrived); XCTAssertTrue(progress.allows(.unlockChapter, accountID: 9001))
        XCTAssertFalse(progress.allows(.broadcast, accountID: 9002))
        let empty = try PlayLeadProgress(PlayExperienceSyntheticFixtures.wire(#"{"exists":false}"#))
        XCTAssertFalse(empty.exists); XCTAssertFalse(empty.allArrived)
    }
    func testLeaderEditOpsIsJSONNotMultipart() async throws {
        let transport = PlayExperienceTestTransport { _ in (PlayExperienceSyntheticFixtures.envelope("null"), 200) }
        try await service(transport).lead(activityID: 41, action: .editTime, text: "2026-10-02 10:00", token: "synthetic")
        let request = transport.requests[0], body = try JSONDecoder().decode(PlayWireValue.self, from: request.httpBody!)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(Set(body.object!.keys), ["activityId", "startDate"])
    }
    func testAdvancedConversionsAndCrossKitActions() throws {
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "reaction", action: "SUBMIT_REACTION", detail: ["times": .array([.int(200)])]), ["roundsMs": .array([.int(200)])])
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "quietHold", action: "SUBMIT_QUIET_HOLD", detail: ["heldSeconds": .number(1.5)]), ["heldMs": .int(1500)])
        XCTAssertEqual(try PlayKitActionCatalog.payload(kind: "coinFlip", action: "FLIP_COIN", detail: ["result": .string("heads")]), [:])
        XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind: "qa", action: "FLIP_COIN", detail: [:]))
        XCTAssertThrowsError(try PlayKitActionCatalog.payload(kind: "silentOrder", action: "SUBMIT", detail: [:]))
    }
    func testAdvancedForeignIdentityAndVersionAreRejected() async throws {
        let transport = PlayExperienceTestTransport { _ in (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200) }
        do { _ = try await service(transport).startAdvanced(activityID: 99, topicID: 71, nodeID: 701, token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .malformed) }
        do { _ = try await service(transport).advancedAction(.init(sessionID: 601, version: 2, key: "stable", action: "DRAW", payload: [:]), token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .malformed) }
    }
    func testPlayerTextEvidenceUsesCanonicalPercentEncoding() throws {
        let evidence = try PlayPlayerCommand.textEvidence("hello & 中文")
        XCTAssertTrue(evidence.hasPrefix("text:")); XCTAssertFalse(evidence.contains(" "))
        XCTAssertNoThrow(try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .submit, payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string(evidence)])]))
        XCTAssertThrowsError(try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .submit, payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string("file:///tmp/photo.jpg")])]))
    }
    func testPlayerReceiptBindsAllIdentityAndTerminalReceiptID() throws {
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, requestID: "synthetic-request", expectedRevision: 2, action: .choice, payload: ["choiceId": .string("LEFT")])
        let valid = try PlayExperienceSyntheticFixtures.wire(#"{"activityId":41,"requestId":"synthetic-request","action":"PLAYER_CHOICE","outcome":"PENDING","revision":2}"#)
        XCTAssertEqual(try PlayGameReceipt(valid, command: command).outcome, "PENDING")
        XCTAssertThrowsError(try PlayGameReceipt(PlayExperienceSyntheticFixtures.wire(#"{"activityId":41,"requestId":"synthetic-request","action":"PLAYER_CHOICE","outcome":"APPLIED","revision":3}"#), command: command))
        XCTAssertThrowsError(try PlayGameReceipt(PlayExperienceSyntheticFixtures.wire(#"{"activityId":42,"requestId":"synthetic-request","action":"PLAYER_CHOICE","outcome":"APPLIED","receiptId":1,"revision":3}"#), command: command))
    }
    func testPlayerChoiceRequiresServerCandidateAndRevision() throws {
        let projection = try PlayPlayerGameProjection(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player))
        let valid = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .choice, payload: ["choiceId": .string("LEFT")])
        let forged = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .choice, payload: ["choiceId": .string("FORGED")])
        XCTAssertTrue(projection.allows(valid)); XCTAssertFalse(projection.allows(forged))
    }
    func testCircleReadbackRequiresExactRecordOrAnswer() throws {
        let card = try PlayCircleCard(PlayExperienceSyntheticFixtures.wire(#"{"sessionId":801,"themeCode":"FITNESS","records":[{"offerId":2}],"answers":[{"answerStage":"PRE_CHOICE","answerValue":"A"}]}"#), expectedSessionID: "801")
        XCTAssertTrue(card.confirms(.record(offerID: "2", note: "ignored by source readback")))
        XCTAssertTrue(card.confirms(.answer(stage: "PRE_CHOICE", value: " A ")))
        XCTAssertFalse(card.confirms(.answer(stage: "PRE_CHOICE", value: "B")))
        XCTAssertFalse(card.stages.contains("PRE_CHOICE")); XCTAssertFalse(card.stages.contains("POST_CHOICE"))
    }
    func testCircleRejectsPathInjectionBeforeNetwork() async throws {
        let transport = PlayExperienceTestTransport { _ in XCTFail(); return (Data(), 200) }
        do { _ = try await service(transport).circleCard(sessionID: "../other", token: "synthetic"); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testStillnessRequiresFiveSamplesAndExcludesPausedAndLargeGaps() throws {
        var machine = PlayStillnessMachine(configuration: try .init(durationSeconds: 1))
        for index in 0...4 { machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: Double(index) * 0.1)) }
        XCTAssertEqual(machine.stableSeconds, 0)
        machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: 0.5)); XCTAssertEqual(machine.stableSeconds, 0.1, accuracy: 0.0001)
        machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: 50)); XCTAssertEqual(machine.stableSeconds, 0.1, accuracy: 0.0001)
        machine.pause(); machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: 51)); XCTAssertEqual(machine.phase, .paused)
        machine.resume(); XCTAssertNil(machine.sourcePayload)
    }
    func testStillnessMovementResetsAndCompletionIsOnce() throws {
        var machine = PlayStillnessMachine(configuration: try .init(durationSeconds: 1))
        for index in 0...7 { machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: Double(index) / 10)) }
        machine.ingest(.init(x: 20, y: 0, z: 1, timestamp: 0.8)); XCTAssertEqual(machine.resetCount, 1); XCTAssertEqual(machine.stableSeconds, 0)
        for index in 9...40 { machine.ingest(.init(x: 0, y: 0, z: 1, timestamp: Double(index) / 10)) }
        XCTAssertEqual(machine.completionCount, 1); XCTAssertEqual(machine.sourcePayload, ["heldSec": .int(1)])
    }
    func testStopwatchClampsAndBackgroundVoidsRound() {
        var machine = PlayStopwatchMachine(target: 0)
        XCTAssertEqual(machine.target, 3); machine.begin(now: 10); XCTAssertNil(machine.visibleElapsed(now: 11))
        machine.interrupt(); XCTAssertEqual(machine.phase, .idle); XCTAssertEqual(machine.rounds, 0)
        machine.begin(now: 20); machine.stop(now: 23); XCTAssertEqual(machine.result?.stars, 3); XCTAssertEqual(machine.bestDifference, 0)
    }
    func testDeviceProviderNeverReturnsEvidenceAfterSessionReplacement() async throws {
        let first = try PlayDeviceContext(session: session(), scope: .activity(41), nodeID: 701)
        var context: PlayDeviceContext? = first
        let provider = PlaySyntheticDeviceProvider(supported: [.scan]) { _, _ in context = nil; return .scan("synthetic") }
        let capture = PlayDeviceCaptureCoordinator(provider: provider, current: { context }); await capture.capture(.scan)
        XCTAssertNil(capture.output); capture.cancel(); XCTAssertFalse(capture.busy)
    }
    func testEmptyEndingIsSuccessfulNoStoryState() throws {
        let ending: PlayEndingDocument = try PlayExperienceSyntheticFixtures.wire(#"{"opener":"","fragments":[]}"#).decoded()
        XCTAssertFalse(ending.hasStory)
    }
    func testDirectorNotPreparedShellAndReadinessGates() throws {
        let raw = try PlayExperienceSyntheticFixtures.wire(#"{"perspective":"CLUB","activityId":41,"status":"NOT_PREPARED","revision":0,"availableActions":["PREPARE"]}"#)
        let projection = try PlayDirectorProjection(raw, activityID: 41)
        XCTAssertNil(projection.sessionID); XCTAssertFalse(projection.canStart)
        XCTAssertTrue(projection.allows(try .init(activityID: 41, nodeID: nil, expectedRevision: 0, action: .prepare, payload: [:])))
        XCTAssertThrowsError(try PlayDirectorProjection(raw, activityID: 42))
    }
    func testDirectorCommandsRejectWrongNodeAndPayloadShape() {
        XCTAssertThrowsError(try PlayDirectorCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .broadcast, payload: ["targetType": .string("ALL"), "content": .string("Synthetic")]))
        XCTAssertThrowsError(try PlayDirectorCommand(activityID: 41, nodeID: nil, expectedRevision: 2, action: .visibility, payload: ["visible": .string("true")]))
        XCTAssertNoThrow(try PlayDirectorCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .pause, payload: ["reasonCode": .string("WEATHER"), "reason": .string("Synthetic reason"), "resumeEta": .string("Synthetic time")]))
    }
}
private final class PlayExperienceTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}
