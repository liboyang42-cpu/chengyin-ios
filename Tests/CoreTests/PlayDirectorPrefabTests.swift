import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayDirectorPrefabTests: XCTestCase {
    private func wire(_ value: String) throws -> PlayWireValue { try PlayExperienceSyntheticFixtures.wire(value) }
    private func session(_ accountID: Int = 9001, epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: accountID, epoch: epoch, namespace: "synthetic-prefab", token: "synthetic-token") }
    private func service(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability> = [.reads, .classicCompletion, .mediaUpload, .directorCommands]) throws -> PlayExperienceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: enabled)
    }
    func testDirectorStartRequiresReadinessNotOnlyActionName() throws {
        let raw = try wire(#"{"activityId":41,"sessionId":501,"perspective":"CLUB","revision":2,"status":"READY","availableActions":["START"],"club":{"readiness":{"requiredStations":2,"readyStations":1,"teamsReady":true}}}"#)
        let projection = try PlayDirectorProjection(raw, activityID: 41)
        XCTAssertFalse(projection.canStart)
        XCTAssertFalse(projection.allows(try .init(activityID: 41, nodeID: nil, expectedRevision: 2, action: .start, payload: [:])))
    }
    func testDirectorTakeoverRequiresUnassignedTarget() throws {
        let raw = try wire(#"{"activityId":41,"sessionId":501,"perspective":"CLUB","revision":2,"status":"RUNNING","availableActions":["TAKEOVER_ROLE"],"club":{"roles":[{"teamId":61,"memberId":1,"roleCode":"OBSERVE","confirmationStatus":"CONFIRMED"},{"teamId":61,"memberId":2,"roleCode":"LEAD","confirmationStatus":"CONFIRMED"}]}}"#)
        let projection = try PlayDirectorProjection(raw, activityID: 41)
        let command = try PlayDirectorCommand(activityID: 41, nodeID: nil, expectedRevision: 2, action: .takeover, payload: ["teamId": .int(61), "sourceMemberId": .int(1), "targetMemberId": .int(2), "reason": .string("Synthetic absence")])
        XCTAssertFalse(projection.allows(command))
    }
    func testDirectorReceiptRejectsOtherActionAndForeignActivity() throws {
        let command = try PlayDirectorCommand(activityID: 41, nodeID: nil, requestID: "synthetic-prepare", expectedRevision: 0, action: .prepare, payload: [:])
        XCTAssertThrowsError(try PlayDirectorReceipt(wire(#"{"activityId":42,"requestId":"synthetic-prepare","action":"PREPARE","outcome":"APPLIED","receiptId":1,"revision":1}"#), command: command))
        XCTAssertThrowsError(try PlayDirectorReceipt(wire(#"{"activityId":41,"requestId":"synthetic-prepare","action":"START","outcome":"APPLIED","receiptId":1,"revision":1}"#), command: command))
    }
    func testUploadUsesFilePartAndTopLevelURL() async throws {
        let transport = PlayExtensionTestTransport { _ in (Data(#"{"code":200,"url":"https://example.com/synthetic.jpg"}"#.utf8), 200) }
        let url = try await service(transport).uploadPlayPhoto(bytes: Data([1,2,3]), mimeType: "image/jpeg", token: "synthetic")
        XCTAssertEqual(url, "https://example.com/synthetic.jpg")
        let request = try XCTUnwrap(transport.requests.first), body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertEqual(request.url?.path, "/fixture/api/common/uploadOSS"); XCTAssertTrue(body.contains("name=\"file\""))
        XCTAssertFalse(body.contains("bizType")); XCTAssertFalse(body.contains("localPath"))
    }
    func testUploadSizeAndDormantCapabilityFailBeforeTransport() async throws {
        let transport = PlayExtensionTestTransport { _ in XCTFail(); return (Data(), 200) }
        do { _ = try await service(transport, enabled: []).uploadPlayPhoto(bytes: Data([1]), mimeType: "image/jpeg", token: "synthetic"); XCTFail() } catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        do { _ = try await service(transport).uploadPlayPhoto(bytes: Data(repeating: 0, count: 10 * 1024 * 1024 + 1), mimeType: "image/jpeg", token: "synthetic"); XCTFail() } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testRecapExportFiltersPrivateFields() throws {
        let metrics: PlayWireValue = .array([.object(["key": .string("NODES"), "label": .string("Synthetic nodes"), "value": .int(1), "unit": .string(""), "phone": .string("private")])])
        func zeros(_ keys: [String]) -> PlayWireValue { .object(Dictionary(uniqueKeysWithValues: keys.map { ($0, PlayWireValue.int(0)) })) }
        let recap: PlayWireValue = .object(["schemaVersion": .string("GAME_RECAP_V1"), "generatedAt": .string("2026-10-01 12:00:00"), "exportAvailable": .bool(true), "metrics": metrics, "stations": .array([]), "funnel": zeros(["paidPlayers","arrivedPlayers","taskSubmitters","normalCompleters","fallbackCompleters","finishedTeams"]), "hints": zeros(["level1Uses","level2Uses","answerReveals"]), "incidents": zeros(["merchantPauseEvents","merchantFallbackCompletions","playerRejectedSubmissions"]), "collaboration": zeros(["eligibleTeams","completedTeams","ratePercent"]), "takeovers": zeros(["count"]), "evidence": .string("private")])
        let raw: PlayWireValue = .object(["schemaVersion": .string("GAME_RECAP_EXPORT_V1"), "activityId": .int(41), "sessionId": .int(501), "generatedAt": .string("2026-10-01 12:00:00"), "recap": recap, "memberId": .int(9001)])
        let safe = try PlayDirectorRecap.normalizeExport(raw, activityID: 41)
        let encoded = String(decoding: try JSONEncoder().encode(safe), as: UTF8.self)
        XCTAssertFalse(encoded.contains("phone")); XCTAssertFalse(encoded.contains("evidence")); XCTAssertFalse(encoded.contains("memberId"))
        XCTAssertThrowsError(try PlayDirectorRecap.normalizeExport(raw, activityID: 42))
    }
    func testRecapDateValidationDoesNotAcceptImpossibleDates() {
        XCTAssertTrue(PlayDirectorRecap.validDateTime("2024-02-29 23:59:59"))
        XCTAssertFalse(PlayDirectorRecap.validDateTime("2026-02-29 23:59:59"))
        XCTAssertFalse(PlayDirectorRecap.validDateTime("2026-10-01 24:00:00"))
    }
    func testCircleUnknownOpenCannotBeReissuedByRefreshingOffers() async throws {
        let current = try session(); var openings = 0
        let transport = PlayExtensionTestTransport { request in
            if request.url?.path.hasSuffix("/offers") == true { return (PlayExperienceSyntheticFixtures.envelope("[{\"id\":1},{\"id\":2},{\"id\":3}]"), 200) }
            openings += 1; throw URLError(.timedOut)
        }
        let coordinator = PlayCircleCoordinator(topicID: 71, service: try service(transport, enabled: [.reads, .circle]), currentSession: { current })
        await coordinator.loadOffers(); await coordinator.open(); XCTAssertEqual(coordinator.phase, "unknownOpen")
        await coordinator.loadOffers(); await coordinator.open(); XCTAssertEqual(openings, 1); XCTAssertEqual(coordinator.phase, "unknownOpen")
    }
    func testRuntimeRecordStripsPreviewPhotosAndSyncedFlag() {
        var preview = PrefabPreviewState(); preview.photos["hall"] = "https://example.com/preview.jpg"; preview.synced = true; preview.profile.avatar = "https://example.com/avatar.jpg"
        let runtime = PlayPrefabRuntimeRecord(story: preview, owner: "synthetic", scopeComponent: "activityId:41")
        XCTAssertTrue(runtime.story.photos.isEmpty); XCTAssertFalse(runtime.story.synced); XCTAssertTrue(runtime.story.profile.avatar.isEmpty)
        XCTAssertNil(runtime.hallPhotoURL)
    }
    func testRuntimeStorageDoesNotReadPreviewNamespaceAndClearsLocalSyncedFlag() throws {
        let memory = PlayExtensionMemoryStorage(), store = PlayPrefabRuntimeStore(storage: memory), session = try session()
        var record = PlayPrefabRuntimeRecord(owner: PlayPrefabRuntimeStore.owner(session), scopeComponent: PlayPrefabRuntimeStore.scope(.activity(41)))
        record.story.synced = true; try store.save(record, session: session, scope: .activity(41))
        XCTAssertFalse(try XCTUnwrap(store.load(session: session, scope: .activity(41))).story.synced)
        XCTAssertTrue(memory.values.keys.allSatisfy { $0.hasPrefix("prefab-runtime.v1.") })
        XCTAssertNil(try store.load(session: session, scope: .topic(41)))
    }
    func testRuntimePhotoSyncRequiresAuthoritativeNodeReadback() async throws {
        let current = try session(), memory = PlayExtensionMemoryStorage(), store = PlayPrefabRuntimeStore(storage: memory)
        var record = PlayPrefabRuntimeRecord(owner: PlayPrefabRuntimeStore.owner(current), scopeComponent: PlayPrefabRuntimeStore.scope(.activity(41)))
        record.story.scene = .flow; record.hallPhotoURL = "https://example.com/hall.jpg"; record.story.photos["hall"] = record.hallPhotoURL
        try store.save(record, session: current, scope: .activity(41)); var submitted = false
        let transport = PlayExtensionTestTransport { request in
            if request.url?.path.hasSuffix("/photo") == true { submitted = true; return (PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701}"#), 200) }
            let nodes = #"{"topicId":71,"topicName":"预制人生","mode":1,"playable":true,"nodes":[{"nodeId":701,"name":"Synthetic hall","done":false,"arrived":true,"validationMethod":2}]}"#
            return (PlayExperienceSyntheticFixtures.envelope(nodes), 200)
        }
        let coordinator = PlayPrefabRuntimeCoordinator(scope: .activity(41), service: try service(transport), provider: PlayDormantDeviceProvider(), store: store, currentSession: { current })
        await coordinator.load(); await coordinator.syncCompletion()
        XCTAssertTrue(submitted); XCTAssertEqual(coordinator.phase, "unknown"); XCTAssertFalse(coordinator.record?.story.synced ?? true)
        await coordinator.syncCompletion(); XCTAssertEqual(transport.requests.filter { $0.url?.path.hasSuffix("/photo") == true }.count, 1)
    }
    func testSceneBootTargetTimingAndWrongPrefix() throws {
        var state = PrefabPreviewState(); state.scene = .boot
        var machine = PlayPrefabSceneMachine(story: state)
        for index in 1...PlayPrefabSceneMachine.bootTarget.count {
            machine.typeBoot(String(PlayPrefabSceneMachine.bootTarget.prefix(index)), now: 10 + Double(index) * 0.3)
        }
        XCTAssertTrue(machine.bootDone); XCTAssertEqual(machine.story.skills["precision"], 2)
        try machine.next(); XCTAssertEqual(machine.story.scene, .walk)
        machine = .init(story: state); machine.typeBoot("wrong", now: 0); XCTAssertTrue(machine.bootFailed); XCTAssertFalse(machine.bootDone)
    }
    func testBootPasteCannotBypassSourceKeySequence() {
        var state = PrefabPreviewState(); state.scene = .boot; var machine = PlayPrefabSceneMachine(story: state)
        machine.typeBoot("hello world", now: 1); XCTAssertFalse(machine.bootDone); XCTAssertTrue(machine.bootFailed)
    }
    func testRestoredWalkCheckpointCannotSkipChoice() {
        var state = PrefabPreviewState(); state.scene = .walk; state.walkProgress = 50
        var machine = PlayPrefabSceneMachine(story: state); machine.startWalk(now: 0); _ = machine.tick(now: 5)
        XCTAssertTrue(machine.waitingForRoute); XCTAssertEqual(machine.story.walkProgress, 50)
        state.walkProgress = 74; state.picks["signAsked"] = .bool(true)
        machine = .init(story: state); XCTAssertTrue(machine.waitingForSign)
    }
    func testBootTimeoutNeverAwardsPrecision() {
        var state = PrefabPreviewState(); state.scene = .boot; var machine = PlayPrefabSceneMachine(story: state)
        machine.typeBoot("h", now: 0); _ = machine.tick(now: 11)
        XCTAssertTrue(machine.bootFailed); XCTAssertEqual(machine.story.skills["precision"], 1)
    }
    func testWalkRequiresRouteAndSignCheckpoints() throws {
        var state = PrefabPreviewState(); state.scene = .walk; var machine = PlayPrefabSceneMachine(story: state)
        machine.startWalk(now: 0)
        for i in 1...30 { _ = machine.tick(now: Double(i)) }
        XCTAssertEqual(machine.story.walkProgress, 50); XCTAssertTrue(machine.waitingForRoute)
        try machine.chooseRoute(1, now: 30); XCTAssertEqual(machine.story.luck, 3)
        for i in 31...50 { _ = machine.tick(now: Double(i)) }
        XCTAssertEqual(machine.story.walkProgress, 74); XCTAssertTrue(machine.waitingForSign)
        try machine.skipSign(now: 50)
        for i in 51...70 { _ = machine.tick(now: Double(i)) }
        XCTAssertEqual(machine.story.scene, .hall)
    }
    func testBirthHoldMustReachThreeSecondsAndInterruptionResets() throws {
        var state = PrefabPreviewState(); state.scene = .birth; state.step = 1
        var machine = PlayPrefabSceneMachine(story: state); machine.beginHold(now: 0); _ = machine.tick(now: 2)
        XCTAssertEqual(machine.story.step, 1); machine.interrupt(); _ = machine.tick(now: 10); XCTAssertEqual(machine.story.step, 1)
        machine.beginHold(now: 20); _ = machine.tick(now: 23); XCTAssertEqual(machine.story.step, 2)
    }
    func testQuizSourceAnswersAndTeacherCheckOutcome() throws {
        var state = PrefabPreviewState(); state.scene = .learning; var machine = PlayPrefabSceneMachine(story: state)
        for answer in [1,0,1] { try machine.answerQuiz(answer) }
        XCTAssertEqual(machine.story.picks["quiz"]?.integer, 3); XCTAssertEqual(machine.story.luck, 3); XCTAssertEqual(machine.story.step, 1)
        try machine.recordCount(2, now: 0); try machine.chooseTeacher(0, rolls: [6,6]); XCTAssertNotNil(machine.check)
        machine.closeCheck(); XCTAssertEqual(machine.story.scene, .dream2); XCTAssertTrue(machine.story.thoughts.contains("standard"))
    }
    func testDreamIsLocalAndNeverSetsSyncedOrRemoteReward() {
        var state = PrefabPreviewState(); state.scene = .dream1; var machine = PlayPrefabSceneMachine(story: state)
        _ = machine.tick(now: 0); _ = machine.tick(now: 20)
        XCTAssertEqual(machine.story.scene, .learning); XCTAssertEqual(machine.story.dreams, 1); XCTAssertFalse(machine.story.synced)
    }
    func testContinuousMotionStreamCompletesOnlyAfterSufficientSamples() async throws {
        let current = try session(), context = try PlayDeviceContext(session: current, scope: .activity(41), nodeID: 701)
        let samples = (0...20).map { PlayAccelerationSample(x: 0, y: 0, z: 1, timestamp: Double($0) / 10) }
        let provider = PlaySyntheticMotionProvider(samples: samples)
        let coordinator = PlayStillnessCoordinator(configuration: try .init(durationSeconds: 1), provider: provider, currentContext: { context })
        await coordinator.start(); XCTAssertEqual(coordinator.machine.phase, .completed); XCTAssertEqual(coordinator.machine.completionCount, 1)
        XCTAssertEqual(provider.contexts.count, 1); await coordinator.start(); XCTAssertEqual(provider.contexts.count, 1)
    }
    func testPrematureMotionStreamEndIsFailureNotCompletion() async throws {
        let context = try PlayDeviceContext(session: session(), scope: .activity(41), nodeID: 701)
        let coordinator = PlayStillnessCoordinator(configuration: try .init(durationSeconds: 1), provider: PlaySyntheticMotionProvider(samples: [.init(x: 0, y: 0, z: 1, timestamp: 0)]), currentContext: { context })
        await coordinator.start(); XCTAssertEqual(coordinator.machine.phase, .failed); XCTAssertNil(coordinator.machine.sourcePayload)
    }
    func testCareerOnlyAcceptsSourceJobsAndBoardStickerIsNotLocation() throws {
        var state = PrefabPreviewState(); state.scene = .career; var machine = PlayPrefabSceneMachine(story: state)
        try machine.placeSticker("未加载地图"); XCTAssertEqual(machine.story.sticker?.x, 150); XCTAssertEqual(machine.story.sticker?.y, 388)
        XCTAssertThrowsError(try machine.chooseCareer("Invented profession")); try machine.chooseCareer("程序员"); XCTAssertEqual(machine.story.scene, .work)
    }
}
private final class PlayExtensionTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}
@MainActor private final class PlayExtensionMemoryStorage: TemplateAuthoringStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
