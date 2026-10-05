import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayReadLifetimeTests: XCTestCase {
    private func nodes(_ mode: Int, done: Bool = false) -> String {
        "{\"mode\":\(mode),\"topicId\":71,\"registered\":true,\"playable\":true,\"nodes\":[{\"nodeId\":701,\"done\":\(done),\"arrived\":true,\"validationMethod\":6}]}"
    }
    private func root(_ mode: Int = 1) async throws -> (PlayExperienceCoordinator, PlayRecoveryRecordingTransport, PlayExperienceSession) {
        let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic")
        let wire = PlayRecoveryRecordingTransport()
        setMode(mode, wire: wire)
        let model = PlayExperienceCoordinator(scope: .activity(41), service: try service(wire), recovery: PlayMemoryCompletionRecovery(),
            pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner })
        await model.load(); return (model, wire, owner)
    }
    private func setMode(_ mode: Int, wire: PlayRecoveryRecordingTransport) {
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(nodes(mode)), 200)
    }
    private func service(_ wire: any HTTPTransport, lifetime: PlayInteractionLifetime? = nil) throws -> PlayExperienceService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire,
              enabled: [.reads, .advanced, .preference, .tags, .mediaUpload], readLifetime: lifetime)
    }
    private func assertStale(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected expired read lifetime", file: file, line: line) }
        catch { XCTAssertEqual(error as? PlayExperienceError, .staleSession, file: file, line: line) }
    }
    func testEveryAdvancedPreferenceTagAndUploadEndpointRejectsExpiredServiceBeforeTransport() async throws {
        for mode in [1, 2, 99] {
            let (root, reads, owner) = try await root()
            let lifetime = try XCTUnwrap(root.makeInteractionLifetime()), wire = PlayRecoveryRecordingTransport()
            let api = try service(wire, lifetime: lifetime)
            setMode(mode, wire: reads); await root.load()
            XCTAssertFalse(lifetime.isCurrent)
            let pending = PlayAdvancedPending(sessionID: 601, version: 2, key: "synthetic-action", action: "DRAW", payload: [:])
            let review = PlayPreferenceReview(choices: ["Q": "A"], reusedTagCode: nil, advance: nil, session: owner, generation: 1)
            let tag = try PlayPreferenceTag(PlayExperienceSyntheticFixtures.wire(#"{"id":81,"tagCode":"SYNTHETIC","tagValue":"Synthetic"}"#))
            await assertStale { _ = try await api.startAdvanced(activityID: 41, topicID: 71, nodeID: 701, token: "synthetic") }
            await assertStale { _ = try await api.advancedState(sessionID: 601, token: "synthetic") }
            await assertStale { _ = try await api.advancedAction(pending, token: "synthetic") }
            await assertStale { _ = try await api.preference(scope: .activity(41), nodeID: 701, token: "synthetic") }
            await assertStale { _ = try await api.submitPreference(scope: .activity(41), nodeID: 701, review: review, token: "synthetic") }
            await assertStale { _ = try await api.writePreferenceTag(tag, correctedValue: nil, token: "synthetic") }
            await assertStale { _ = try await api.writePreferenceTag(tag, correctedValue: "Changed", token: "synthetic") }
            await assertStale { _ = try await api.uploadPhoto(Data([1, 2]), mimeType: "image/jpeg", token: "synthetic") }
            XCTAssertEqual(wire.requests.count, 0)
        }
    }
    func testQueuedAdvancedStartAndPreferenceLoadCannotBorrowNewMode() async throws {
        for (before, after) in [(1, 2), (2, 1), (1, 99)] {
            let (root, reads, owner) = try await root(before)
            let wire = PlayRecoveryRecordingTransport(), lifetime = try XCTUnwrap(root.makeInteractionLifetime())
            let api = try service(wire, lifetime: lifetime)
            let advanced = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: api, currentSession: { owner })
            let preference = PlayPreferenceCoordinator(scope: .activity(41), nodeID: 701, service: api, currentSession: { owner })
            setMode(after, wire: reads); await root.load()
            await advanced.start(); await advanced.refreshAuthoritative(); await advanced.recover(); await advanced.retryExact()
            await preference.load(); await preference.retryExact(); await preference.writeTag()
            XCTAssertEqual(wire.requests.count, 0)
            XCTAssertFalse(advanced.isCurrent); XCTAssertFalse(preference.hasCurrentReadLifetime)
        }
    }
    func testUnknownAdvancedActionStaysBlockedAfterModeChangeWithoutRetryOrNewStart() async throws {
        let (root, reads, owner) = try await root()
        let wire = PlayRecoveryRecordingTransport(), lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        wire.responses["/api/play/advanced/start"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200)
        wire.responses["/api/play/advanced/action"] = .failure(.unknownResult)
        let advanced = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: try service(wire, lifetime: lifetime), currentSession: { owner })
        await advanced.start()
        let review = try advanced.review(kind: "coinFlip", action: "FLIP_COIN")
        _ = await advanced.submit(review)
        let pending = try XCTUnwrap(advanced.pending), count = wire.requests.count
        XCTAssertEqual(count, 2); XCTAssertEqual(advanced.phase, "unknown")
        setMode(2, wire: reads); await root.load()
        _ = await advanced.submit(review); await advanced.recover(); await advanced.retryExact(); await advanced.start()
        XCTAssertEqual(wire.requests.count, count); XCTAssertEqual(advanced.pending, pending)
        XCTAssertTrue(advanced.blocksReadRebinding); XCTAssertFalse(advanced.hasCurrentReadLifetime)
    }
    func testUnknownPreferenceSubmissionStaysBlockedAfterModeChange() async throws {
        let (root, reads, owner) = try await root()
        let wire = PlayRecoveryRecordingTransport(), lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(nodes(1)), 200)
        wire.responses["/api/play/preference/701"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"steps":[{"key":"Q","type":"single","title":"Synthetic question","options":[{"key":"A","text":"One"},{"key":"B","text":"Two"}]}]}"#), 200)
        wire.responses["/api/play/preference/701/submit"] = .failure(.unknownResult)
        let preference = PlayPreferenceCoordinator(scope: .activity(41), nodeID: 701, service: try service(wire, lifetime: lifetime), currentSession: { owner })
        await preference.load(); preference.select(stepID: "Q", optionID: "A")
        let review = try preference.review(); await preference.submit(review)
        XCTAssertTrue(preference.blocksReadRebinding)
        let count = wire.requests.count; XCTAssertEqual(count, 3)
        setMode(2, wire: reads); await root.load()
        await preference.submit(review); await preference.retryExact(); await preference.load(); await preference.writeTag()
        XCTAssertEqual(wire.requests.count, count); XCTAssertTrue(preference.blocksReadRebinding)
    }
    func testLateResponseAndThrownUnauthorizedAreFencedBefore401Handling() async throws {
        for upload in [false, true] {
            for outcome in ["success", "http401", "thrown401"] {
                let (root, reads, _) = try await root()
                let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
                let wire = ReadLifetimeWire { _ in
                    self.setMode(2, wire: reads); await root.load()
                    if outcome == "thrown401" { throw PlayExperienceError.unauthorized }
                    if outcome == "http401" { return (Data(#"{"code":401}"#.utf8), 401) }
                    return upload ? (Data(#"{"code":200,"url":"https://example.test/photo"}"#.utf8), 200)
                        : (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200)
                }
                let api = try service(wire, lifetime: lifetime)
                if upload { await assertStale { _ = try await api.uploadPhoto(Data([1]), mimeType: "image/jpeg", token: "synthetic") } }
                else { await assertStale { _ = try await api.startAdvanced(activityID: 41, topicID: 71, nodeID: 701, token: "synthetic") } }
                XCTAssertEqual(wire.count, 1)
                XCTAssertEqual(root.gameplayMode, .freeExploration)
            }
        }
    }
    func testDefaultPlayKitDeviceCallsAndStillnessAreFencedByFactoryLifetime() async throws {
        let (root, reads, owner) = try await root()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
        let provider = PlaySyntheticDeviceProvider(supported: [.photo, .scan]) { kind, _ in kind == .photo ? .photo(Data([1]), mimeType: "image/jpeg") : .scan("Synthetic") }
        var uploads = 0
        let device = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in uploads += 1; return "https://example.test/proof" }, readLifetime: lifetime, current: { context })
        await device.capture(.photo) // The actual PlayKit path omits per-capture interaction.
        XCTAssertEqual(provider.captured.count, 1); XCTAssertTrue(device.canUpload)
        let motion = PlaySyntheticMotionProvider(samples: [])
        let stillness = PlayStillnessCoordinator(configuration: try .init(durationSeconds: 1), provider: motion, readLifetime: lifetime, currentContext: { context })
        setMode(2, wire: reads); await root.load()
        await device.capture(.scan); await device.uploadPhoto(); await stillness.start()
        XCTAssertEqual(provider.captured.count, 1); XCTAssertEqual(uploads, 0); XCTAssertEqual(motion.contexts.count, 0)
        XCTAssertNil(device.reviewedPhoto()); XCTAssertFalse(device.canReviewOutput)
    }
    func testChildNodesCannotAcceptDifferentModeThanItsIssuedRead() async throws {
        let (root, _, owner) = try await root()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime()), wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(nodes(2)), 200)
        let preference = PlayPreferenceCoordinator(scope: .activity(41), nodeID: 701,
            service: try service(wire, lifetime: lifetime), currentSession: { owner })
        await preference.load()
        XCTAssertEqual(wire.requests.count, 1); XCTAssertTrue(preference.steps.isEmpty)
        XCTAssertFalse(lifetime.isCurrent); XCTAssertNil(root.gameplayMode); XCTAssertEqual(root.phase, .needsReadback)
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }
    func testContradictoryChildReadRetiresSharedLeaseAndSiblingCommandsBeforeParentReload() async throws {
        for mode in [2, 99] {
            let (root, parentReads, owner) = try await root()
            let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
            XCTAssertTrue(lifetime === root.makeInteractionLifetime())
            let wire = PlayRecoveryRecordingTransport(), api = try service(wire, lifetime: lifetime)
            wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(nodes(1)), 200)
            wire.responses["/api/play/preference/701"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"nodeId":701,"steps":[{"key":"Q","type":"single","title":"Question","options":[{"key":"A","text":"One"},{"key":"B","text":"Two"}]}]}"#), 200)
            wire.responses["/api/play/preference/701/submit"] = .failure(.unknownResult)
            let preference = PlayPreferenceCoordinator(scope: .activity(41), nodeID: 701, service: api, currentSession: { owner })
            let advanced = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: api, currentSession: { owner })
            let deviceContext = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
            let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1]), mimeType: "image/jpeg") }
            var uploads = 0
            let device = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in uploads += 1; return "https://example.test/proof" }, readLifetime: lifetime, current: { deviceContext })
            await device.capture(.photo); XCTAssertTrue(device.canUpload)
            await preference.load(); preference.select(stepID: "Q", optionID: "A")
            await preference.submit(try preference.review())
            XCTAssertTrue(preference.blocksReadRebinding)
            wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(nodes(mode)), 200)
            await preference.load()
            XCTAssertFalse(lifetime.isCurrent); XCTAssertNil(root.makeInteractionLifetime())
            XCTAssertNil(root.gameplayMode); XCTAssertEqual(parentReads.requests.count, 1)
            let count = wire.requests.count
            await preference.retryExact(); await preference.load(); await advanced.start()
            await device.capture(.photo); await device.uploadPhoto()
            XCTAssertEqual(provider.captured.count, 1); XCTAssertEqual(uploads, 0); XCTAssertNil(device.reviewedPhoto())
            await assertStale { _ = try await api.uploadPhoto(Data([1]), mimeType: "image/jpeg", token: "synthetic") }
            XCTAssertEqual(wire.requests.count, count); XCTAssertTrue(preference.blocksReadRebinding)
            // Even another issuer call cannot revive that read; only a new parent read can.
            setMode(mode, wire: parentReads); await root.load()
            XCTAssertFalse(lifetime.isCurrent)
            if mode == 2 { XCTAssertNotEqual(root.makeInteractionLifetime()?.identity, lifetime.identity) }
        }
    }
    func testMissingChildModeRetiresAllIssuedAuthority() async throws {
        let (root, parentReads, _) = try await root()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime()), wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"topicId":71,"registered":true,"playable":true,"nodes":[]}"#), 200)
        let api = try service(wire, lifetime: lifetime)
        await assertStale { _ = try await api.nodes(scope: .activity(41), token: "synthetic") }
        XCTAssertFalse(lifetime.isCurrent); XCTAssertNil(root.snapshot); XCTAssertEqual(parentReads.requests.count, 1)
    }
    func testDispatchedAdvancedStartWithStaleResultRemainsAnUncertainStartBlock() async throws {
        let (root, reads, owner) = try await root()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        let wire = ReadLifetimeWire { _ in
            self.setMode(2, wire: reads); await root.load()
            return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200)
        }
        let advanced = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701,
            service: try service(wire, lifetime: lifetime), currentSession: { owner })
        await advanced.start()
        XCTAssertEqual(wire.count, 1); XCTAssertNil(advanced.pending); XCTAssertNil(advanced.state)
        XCTAssertTrue(advanced.startOutcomeUnknown); XCTAssertTrue(advanced.blocksReadRebinding)
        XCTAssertEqual(advanced.phase, "stale")
        await advanced.start(); await advanced.recover(); await advanced.retryExact()
        XCTAssertEqual(wire.count, 1); XCTAssertTrue(advanced.startOutcomeUnknown)
    }
    func testFreshBoundServiceStillLoadsAdvancedStateWithoutModeInference() async throws {
        for mode in [1, 2] {
            let (root, _, owner) = try await root(mode)
            let lifetime = try XCTUnwrap(root.makeInteractionLifetime()), wire = PlayRecoveryRecordingTransport()
            wire.responses["/api/play/advanced/start"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced), 200)
            let model = PlayAdvancedCoordinator(activityID: 41, topicID: 71, nodeID: 701, service: try service(wire, lifetime: lifetime), currentSession: { owner })
            await model.start(); XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(model.phase, "ready")
            XCTAssertTrue(model.isCurrent); XCTAssertEqual(model.readLifetimeID, lifetime.identity)
        }
    }
}
@MainActor private final class ReadLifetimeWire: HTTPTransport {
    private(set) var count = 0
    let operation: (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { count += 1; return try await operation(request) }
}
