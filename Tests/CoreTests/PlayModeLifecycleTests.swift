import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayModeLifecycleTests: XCTestCase {
    private func session() throws -> PlayExperienceSession { try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic") }
    private func free(arrived: Bool = false, reported: Bool = false, done: Bool = false, hasGame: Bool = false) -> String {
        "{\"mode\":2,\"registered\":true,\"playable\":true,\"total\":1,\"doneCount\":\(done ? 1 : 0),\"nodes\":[{\"nodeId\":701,\"done\":\(done),\"arrived\":\(arrived),\"selfReported\":\(reported),\"hasGame\":\(hasGame)}]}"
    }
    private func model(_ wire: any HTTPTransport, _ storage: ModePauseSpy, _ owner: PlayExperienceSession,
                       recovery: PlayMemoryCompletionRecovery? = nil) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!),
              transport: wire, enabled: [.reads, .classicCompletion, .runPersistence, .hints, .leader]), recovery: recovery ?? PlayMemoryCompletionRecovery(),
              pausedStorage: storage, currentSession: { owner })
    }
    func testFreeModeCannotTouchOrientationClockStorageOrRunEndpointsEvenWithCapability() async throws {
        let wire = PlayRecoveryRecordingTransport(), storage = ModePauseSpy(), owner = try session()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free()), 200)
        let value = try model(wire, storage, owner); await value.load(); await value.restoreRun()
        value.startRun(now: 1); await value.pauseRun(now: 2, savedAt: 10); await value.endRun(now: 3, savedAt: 20)
        XCTAssertEqual(value.gameplayMode, .freeExploration); XCTAssertFalse(value.canManageRun)
        XCTAssertEqual(value.clock.phase, .idle); XCTAssertEqual(storage.accesses, 0)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/play/nodes"])
    }
    func testOrientationRetainsOwnRunAndPauseRestoration() async throws {
        let wire = PlayRecoveryRecordingTransport(), storage = ModePauseSpy(), owner = try session()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
        wire.responses["/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200)
        let value = try model(wire, storage, owner); await value.load(); await value.restoreRun(); value.startRun(now: 1)
        XCTAssertEqual(value.gameplayMode, .cityOrientation); XCTAssertTrue(value.canManageRun)
        XCTAssertEqual(value.clock.phase, .running); XCTAssertGreaterThan(storage.accesses, 0)
    }
    func testFreshFreeModeDiscardsOnlyInMemoryOrientationState() async throws {
        let wire = PlayRecoveryRecordingTransport(), storage = ModePauseSpy(), owner = try session()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
        wire.responses["/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200)
        let value = try model(wire, storage, owner); await value.load(); await value.restoreRun(); value.startRun(now: 1)
        let accesses = storage.accesses, requests = wire.requests.count
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free()), 200)
        await value.load(); await value.restoreRun(); await value.pauseRun(now: 2, savedAt: 10); await value.endRun(now: 3, savedAt: 20)
        XCTAssertEqual(value.clock.phase, .idle); XCTAssertEqual(storage.accesses, accesses)
        XCTAssertEqual(wire.requests.count, requests + 1)
    }
    func testFreeToOrientationReentersOnlyAfterFreshServerModeAndExplicitRestore() async throws {
        let wire = PlayRecoveryRecordingTransport(), storage = ModePauseSpy(), owner = try session()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free()), 200)
        wire.responses["/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200)
        let value = try model(wire, storage, owner); await value.load(); await value.restoreRun()
        XCTAssertEqual(storage.accesses, 0)
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
        await value.load(); XCTAssertEqual(value.gameplayMode, .cityOrientation)
        await value.restoreRun(); value.startRun(now: 1)
        XCTAssertEqual(value.clock.phase, .running); XCTAssertGreaterThan(storage.accesses, 0)
    }
    func testUnknownMissingAndFutureModesNeverEnableOrientationRunOrEvidence() async throws {
        for modeField in ["", "\"mode\":0,", "\"mode\":99,"] {
            let wire = PlayRecoveryRecordingTransport(), storage = ModePauseSpy(), owner = try session()
            let raw = "{\(modeField)\"registered\":true,\"playable\":true,\"nodes\":[{\"nodeId\":701,\"done\":false,\"arrived\":true,\"validationMethod\":1,\"question\":\"Question\"}]}"
            wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw), 200)
            let value = try model(wire, storage, owner); await value.load(); await value.restoreRun()
            value.startRun(now: 1); await value.pauseRun(now: 2, savedAt: 10); await value.endRun(now: 3, savedAt: 20)
            XCTAssertNil(value.gameplayMode); XCTAssertFalse(value.canManageRun); XCTAssertEqual(storage.accesses, 0)
            XCTAssertThrowsError(try value.review(nodeID: 701, evidence: .answer("answer")))
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testLateOldFreeResponseCannotReplaceNewOrientationSnapshot() async throws {
        let owner = try session(), storage = ModePauseSpy(); var reads = 0
        var value: PlayExperienceCoordinator!
        let wire = ModeReadWire { _ in
            reads += 1
            if reads == 1 {
                await value.load()
                return (PlayExperienceSyntheticFixtures.envelope(self.free()), 200)
            }
            return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200)
        }
        value = try model(wire, storage, owner); await value.load()
        XCTAssertEqual(value.gameplayMode, .cityOrientation); XCTAssertEqual(storage.accesses, 0)
        XCTAssertEqual(value.snapshot?.result.mode, 1); XCTAssertEqual(reads, 2)
    }
    func testFreeEvidenceRejectsOrientationAnswerGPSAndSensorCommands() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free()), 200)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        for evidence in [PlayCompletionEvidence.answer("answer"), .location(longitude: 1, latitude: 1, coordinateSystem: "GCJ02"),
                         .sensor(type: "still", payload: ["heldSec": .int(5)]), .photo("https://example.test/proof")] {
            XCTAssertThrowsError(try value.review(nodeID: 701, evidence: evidence))
        }
        let review = try value.review(nodeID: 701, evidence: .scan("store-code"))
        XCTAssertEqual(review.gameplayMode, .freeExploration); XCTAssertNil(review.advance)
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testStoreArrivalDoesNotRequireAnOrientationAdvancedTaskFirst() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        let raw = #"{"mode":2,"registered":true,"playable":true,"nodes":[{"nodeId":701,"done":false,"arrived":false,"hasGame":true,"advancedConfigJson":{"timer":{"enabled":true}}}]}"#
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw), 200)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        XCTAssertTrue(try XCTUnwrap(value.snapshot?.visibleNodes.first).hasAdvancedPrerequisite)
        XCTAssertNoThrow(try value.review(nodeID: 701, evidence: .scan("store-code")))
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testStoreEvidenceJournalBindsModeAndArrivalReadbackDoesNotRedeemStore() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session(), recovery = PlayMemoryCompletionRecovery()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free()), 200)
        wire.responses["/api/play/checkin"] = .failure(.unknownResult)
        let value = try model(wire, ModePauseSpy(), owner, recovery: recovery); await value.load()
        await value.submit(try value.review(nodeID: 701, evidence: .scan("store-code")))
        let key = PlayRunStorageKey.make(session: owner, scope: .activity(41)), loaded = try await recovery.read(PlayRunStorageKey.make(session: owner, scope: .activity(41)))
        let pending = try XCTUnwrap(loaded)
        XCTAssertEqual(pending.value.intent.gameplayMode, .freeExploration)
        XCTAssertTrue(value.unresolved); XCTAssertFalse(value.canRetryExactBranch)
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free(arrived: true)), 200)
        await value.load(); XCTAssertFalse(value.unresolved); XCTAssertEqual(value.snapshot?.visibleNodes.first?.done, false)
        let cleared = try await recovery.read(key); XCTAssertNil(cleared)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testCrossModeAndLegacyPendingWritesDoNotSettleFromSameStoreArrival() async throws {
        for mode in [nil, .cityOrientation] as [PlayGameplayMode?] {
            let owner = try session(), wire = PlayRecoveryRecordingTransport(), recovery = PlayMemoryCompletionRecovery()
            let review = PlayCompletionReview(nodeID: 701, evidence: .scan("old-code"), advance: nil, session: owner,
                generation: 1, routeSessionID: nil, gameplayMode: mode)
            let key = PlayRunStorageKey.make(session: owner, scope: .activity(41))
            let prepared = try await recovery.prepare(.init(review: review), key: key)
            let dispatched = try await recovery.transition(prepared, to: .dispatching, key: key)
            _ = try await recovery.transition(dispatched, to: .unknown, key: key)
            wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free(arrived: true)), 200)
            let value = try model(wire, ModePauseSpy(), owner, recovery: recovery); await value.load()
            XCTAssertTrue(value.unresolved); XCTAssertTrue(value.hasModeRecoveryBlock); XCTAssertFalse(value.canRetryExactBranch)
            let retained = try await recovery.read(key); XCTAssertNotNil(retained); XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testFreeEndingRequiresRedemptionAndDoesNotLoadOrientationLeaderboard() async throws {
        let owner = try session(), wire = PlayRecoveryRecordingTransport()
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free(arrived: true, reported: true)), 200)
        wire.responses["/api/play/ending"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"opener":"Synthetic ending","fragments":[]}"#), 200)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        await value.loadFreeExplorationEnding(); await value.loadEndingAndLeaderboard(); XCTAssertEqual(wire.requests.count, 1)
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(free(arrived: true, reported: true, done: true)), 200)
        await value.load(); await value.loadFreeExplorationEnding()
        XCTAssertEqual(wire.requests.last?.url?.path, "/api/play/ending")
        XCTAssertFalse(wire.requests.contains { $0.url?.path.contains("leaderboard") == true })
    }
    private func interactionNodes(_ mode: Int) -> String {
        "{\"mode\":\(mode),\"topicId\":71,\"registered\":true,\"playable\":true,\"nodes\":[{\"nodeId\":701,\"done\":false,\"arrived\":true,\"validationMethod\":1,\"question\":\"Question\",\"advancedConfigJson\":{\"timer\":{\"enabled\":true}}}]}"
    }
    private func prepareInteractionWire(_ wire: PlayRecoveryRecordingTransport, mode: Int) {
        wire.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(interactionNodes(mode)), 200)
        wire.responses["/api/club/lead/team-progress"] = .reply(PlayExperienceSyntheticFixtures.envelope(
            PlayExperienceSyntheticFixtures.lead.replacingOccurrences(of: "9001", with: "7")), 200)
        wire.responses["/api/club/lead/broadcast"] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200)
        for path in ["/api/play/hint/unlock", "/api/play/puzzle/hint"] {
            wire.responses[path] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"hint":"Synthetic hint","cost":2}"#), 200)
        }
    }
    private func advancedReadyState() throws -> PlayAdvancedState {
        try .init(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.advanced.replacingOccurrences(of: "\"readyForBase\":false", with: "\"readyForBase\":true")))
    }
    func testQueuedHintAndLeadCommandsCannotAcquireChangedModeAuthority() async throws {
        for (before, after) in [(1, 2), (2, 1), (1, 99), (2, 0)] {
            let wire = PlayRecoveryRecordingTransport(), owner = try session()
            prepareInteractionWire(wire, mode: before)
            let value = try model(wire, ModePauseSpy(), owner); await value.load()
            let issued = try XCTUnwrap(value.interactionContext)
            await value.loadLead(context: issued)
            // Capture the rendered authority before the queued button work runs.
            let queued: () async -> Void = {
                await value.requestHint(nodeID: 701, level: nil, context: issued)
                await value.requestHint(nodeID: 701, level: 1, context: issued)
                await value.loadLead(context: issued)
                await value.performLead(.broadcast, text: "Queued", context: issued)
            }
            prepareInteractionWire(wire, mode: after); await value.load()
            await value.loadLead(context: value.interactionContext)
            let count = wire.requests.count
            await queued()
            XCTAssertThrowsError(try value.review(nodeID: 701, evidence: .scan("Delayed device event"), context: issued))
            XCTAssertEqual(wire.requests.count, count)
            XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
            XCTAssertNil(value.hint)
            if after > 2 || after == 0 { XCTAssertNil(value.interactionContext) }
        }
    }
    func testSameModeRefreshAndABARejectOldInteractionContext() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 1)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext)
        for mode in [1, 2, 1] {
            prepareInteractionWire(wire, mode: mode); await value.load()
            await value.loadLead(context: value.interactionContext)
            let count = wire.requests.count
            await value.requestHint(nodeID: 701, level: nil, context: issued)
            await value.loadLead(context: issued)
            await value.performLead(.broadcast, text: "Old", context: issued)
            XCTAssertEqual(wire.requests.count, count)
        }
    }
    func testMissingOrOtherCoordinatorContextCannotDispatch() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 1)
        let first = try model(wire, ModePauseSpy(), owner), second = try model(wire, ModePauseSpy(), owner)
        await first.load(); await second.load(); await second.loadLead(context: second.interactionContext)
        let count = wire.requests.count
        for context in [nil, first.interactionContext] {
            await second.requestHint(nodeID: 701, level: nil, context: context)
            await second.loadLead(context: context)
            await second.performLead(.broadcast, text: "Cross instance", context: context)
            XCTAssertThrowsError(try second.acceptAdvanced(advancedReadyState(), context: context))
        }
        XCTAssertEqual(wire.requests.count, count)
    }
    func testFreshLeadAndGenericHintKeepTheirSourceBackedModeIndependentAuthority() async throws {
        for mode in [1, 2] {
            let wire = PlayRecoveryRecordingTransport(), owner = try session()
            prepareInteractionWire(wire, mode: mode)
            let value = try model(wire, ModePauseSpy(), owner); await value.load()
            await value.loadLead(context: value.interactionContext)
            XCTAssertTrue(try XCTUnwrap(value.lead).allows(.broadcast, accountID: owner.accountID))
            await value.performLead(.broadcast, text: "Synthetic", context: value.interactionContext)
            XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/club/lead/broadcast" }.count, 1)
            await value.requestHint(nodeID: 701, level: nil, context: value.interactionContext)
            XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/play/hint/unlock" }.count, 1)
            XCTAssertEqual(value.gameplayMode?.rawValue, mode)
        }
    }
    func testBothHintFamiliesCarryExactActivityOrTopicScope() async throws {
        for scope in [PlaySessionScope.activity(41), .topic(71)] {
            for level in [nil, 1] as [Int?] {
                let wire = PlayRecoveryRecordingTransport(); prepareInteractionWire(wire, mode: 1)
                let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!),
                    transport: wire, enabled: [.hints])
                _ = try await service.hint(scope: scope, nodeID: 701, level: level, token: "Synthetic")
                let request = try XCTUnwrap(wire.requests.first)
                let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
                XCTAssertEqual(request.url?.path, level == nil ? "/api/play/hint/unlock" : "/api/play/puzzle/hint")
                switch scope {
                case .activity:
                    XCTAssertTrue(body.contains("name=\"activityId\"")); XCTAssertFalse(body.contains("name=\"topicId\""))
                case .topic:
                    XCTAssertTrue(body.contains("name=\"topicId\"")); XCTAssertFalse(body.contains("name=\"activityId\""))
                }
                XCTAssertEqual(wire.requests.count, 1)
            }
        }
    }
    func testPuzzleHintRequiresCurrentOrientationModeEvenWithFreshContext() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 2)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        await value.requestHint(nodeID: 701, level: 1, context: value.interactionContext)
        XCTAssertEqual(wire.requests.count, 1)
        prepareInteractionWire(wire, mode: 1); await value.load()
        await value.requestHint(nodeID: 701, level: 1, context: value.interactionContext)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/play/puzzle/hint" }.count, 1)
    }
    func testAdvancedReadinessCannotCrossModeOrReturnThroughABA() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 1)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext), state = try advancedReadyState()
        try value.acceptAdvanced(state, context: issued)
        XCTAssertNoThrow(try value.review(nodeID: 701, evidence: .answer("Synthetic")))
        value.cancelReview()
        prepareInteractionWire(wire, mode: 2); await value.load()
        XCTAssertThrowsError(try value.acceptAdvanced(state, context: issued))
        prepareInteractionWire(wire, mode: 1); await value.load()
        XCTAssertThrowsError(try value.review(nodeID: 701, evidence: .answer("Synthetic")))
        XCTAssertThrowsError(try value.acceptAdvanced(state, context: issued))
        try value.acceptAdvanced(state, context: value.interactionContext)
        XCTAssertNoThrow(try value.review(nodeID: 701, evidence: .answer("Synthetic")))
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }

    func testDeviceCaptureRejectsLateOutputAfterModeChangesBeforeProviderReturns() async throws {
        for (before, after) in [(1, 2), (2, 1), (2, 99)] {
            let wire = PlayRecoveryRecordingTransport(), owner = try session()
            prepareInteractionWire(wire, mode: before)
            let value = try model(wire, ModePauseSpy(), owner); await value.load()
            let issued = try XCTUnwrap(value.interactionContext)
            let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
            let provider = PlaySyntheticDeviceProvider(supported: [.scan]) { _, _ in
                self.prepareInteractionWire(wire, mode: after); await value.load()
                return .scan("Old capture")
            }
            let device = PlayDeviceCaptureCoordinator(provider: provider, current: { context })
            await device.capture(.scan, interaction: .init(context: issued, current: { value.interactionContext }))
            XCTAssertNil(device.output); XCTAssertNil(device.outputInteractionContext); XCTAssertFalse(device.canReviewOutput)
            XCTAssertEqual(provider.captured.count, 1)
            XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
        }
    }
    func testRetainedDeviceResultUsesOriginalLeaseEvenWhenNewViewOffersFreshCallback() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 1)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext)
        let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
        let provider = PlaySyntheticDeviceProvider(supported: [.scan]) { _, _ in .scan("Captured") }
        let device = PlayDeviceCaptureCoordinator(provider: provider, current: { context })
        await device.capture(.scan, interaction: .init(context: issued, current: { value.interactionContext }))
        XCTAssertEqual(device.outputInteractionContext, issued); XCTAssertTrue(device.canReviewOutput)
        prepareInteractionWire(wire, mode: 2); await value.load()
        XCTAssertNotNil(device.output); XCTAssertFalse(device.canReviewOutput)
        XCTAssertEqual(device.outputInteractionContext, issued)
        XCTAssertNotEqual(device.outputInteractionContext, value.interactionContext)
        // The new View passes the result's lease, not its latest rendered lease.
        XCTAssertThrowsError(try value.review(nodeID: 701, evidence: .scan("Captured"), context: device.outputInteractionContext))
        let fresh = try XCTUnwrap(value.interactionContext)
        await device.capture(.scan, interaction: .init(context: fresh, current: { value.interactionContext }))
        XCTAssertTrue(device.canReviewOutput); XCTAssertEqual(device.outputInteractionContext, fresh)
        device.cancel(); XCTAssertNil(device.outputInteractionContext); XCTAssertNil(device.output)
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }
    func testStaleOrMissingCaptureLeaseCannotStartProviderOrUploadOldPhoto() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 2)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext)
        let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
        var uploads = 0
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1, 2]), mimeType: "image/jpeg") }
        let device = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in uploads += 1; return "https://example.test/photo" }, current: { context })
        await device.capture(.photo, interaction: .init(context: nil, current: { value.interactionContext }))
        XCTAssertEqual(provider.captured.count, 0)
        await device.capture(.photo, interaction: .init(context: issued, current: { value.interactionContext }))
        XCTAssertTrue(device.canUpload)
        prepareInteractionWire(wire, mode: 1); await value.load()
        await device.uploadPhoto(expectedOutputID: device.outputID)
        await device.capture(.photo, interaction: .init(context: issued, current: { value.interactionContext }))
        XCTAssertEqual(uploads, 0); XCTAssertEqual(provider.captured.count, 1)
        XCTAssertNil(device.reviewedPhoto()); XCTAssertFalse(device.canUpload)
    }
    func testPhotoUploadCannotRebindResultAfterModeSwitchDuringUpload() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 2)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext)
        let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
        var uploads = 0
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1, 2]), mimeType: "image/jpeg") }
        let device = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in
            uploads += 1; self.prepareInteractionWire(wire, mode: 1); await value.load()
            return "https://example.test/photo"
        }, current: { context })
        await device.capture(.photo, interaction: .init(context: issued, current: { value.interactionContext }))
        await device.uploadPhoto(expectedOutputID: device.outputID)
        XCTAssertEqual(uploads, 1); XCTAssertNil(device.uploadedPhoto); XCTAssertNil(device.reviewedPhoto())
        XCTAssertFalse(device.canReviewOutput); XCTAssertEqual(device.outputInteractionContext, issued)
        XCTAssertFalse(wire.requests.contains { $0.httpMethod == "POST" })
    }

    func testQueuedPhotoUploadCannotUseReplacementCaptureWithinSameMode() async throws {
        let wire = PlayRecoveryRecordingTransport(), owner = try session()
        prepareInteractionWire(wire, mode: 2)
        let value = try model(wire, ModePauseSpy(), owner); await value.load()
        let issued = try XCTUnwrap(value.interactionContext)
        let context = try PlayDeviceContext(session: owner, scope: .activity(41), nodeID: 701)
        var uploads = 0
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1, 2]), mimeType: "image/jpeg") }
        let device = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in uploads += 1; return "https://example.test/photo" }, current: { context })
        let lease = PlayDeviceInteraction(context: issued, current: { value.interactionContext })
        await device.capture(.photo, interaction: lease)
        let first = try XCTUnwrap(device.outputID)
        await device.capture(.photo, interaction: lease)
        let second = try XCTUnwrap(device.outputID); XCTAssertNotEqual(first, second)
        await device.uploadPhoto(expectedOutputID: first); XCTAssertEqual(uploads, 0)
        await device.uploadPhoto(expectedOutputID: second); XCTAssertEqual(uploads, 1)
        XCTAssertNil(device.reviewedPhoto(expectedOutputID: first))
        XCTAssertNotNil(device.reviewedPhoto(expectedOutputID: second))
    }

}
@MainActor private final class ModePauseSpy: PlayPausedStorage {
    var accesses = 0
    private let storage = PlayMemoryPausedStorage()
    func read(key: String) async throws -> PlayPausedStorageSnapshot { accesses += 1; return try await storage.read(key: key) }
    func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot {
        accesses += 1; return try await storage.write(value, replacing: snapshot, key: key)
    }
}

@MainActor private final class ModeReadWire: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
