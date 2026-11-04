import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayThemeBackpackActionsTests: XCTestCase {
    private final class Identity {
        var value: PlayExperienceSession?
        init(_ value: PlayExperienceSession?) { self.value = value }
    }
    private struct Harness {
        let actions: PlayThemeBackpackActions
        let http: PlayRecoveryRecordingTransport
        let store: PlayThemeBackpackRecoveryStore
        let identity: Identity
        let anchors: BackpackRecoveryTestAnchors
        let ciphertexts: BackpackRecoveryTestCiphertexts
    }
    private func session(account: Int = 11, epoch: UInt64 = 1, namespace: String = "fixture-backpack", role: String = "player") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-token", role: role)
    }
    private func raw(version: Int = 3, run: Int = 41, status: String = "ACTIVE", activity: Int = 0) -> String {
        """
        {"sessionId":\(run),"topicId":7,"activityId":\(activity),"version":\(version),"status":"\(status)","inventoryEnabled":true,"runtimeScope":"PLAYER","used":3,"capacity":6,"allowDiscard":true,"contents":[{"kind":"ITEM","id":"tea","name":"Tea","stat":"sys.hp","delta":2,"quantity":3,"slotCost":1}],"pending":{"chapter:1:END:0":{"itemId":"tea","quantity":1,"slots":1,"name":"Tea reward"}},"allowedActions":[{"operation":"RECEIVE","contentId":"chapter:1:END:0","claimOnly":true}]}
        """
    }
    private func wire(_ text: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(text.utf8)) }
    private func response(_ text: String) -> PlayRecoveryRecordingTransport.Response {
        .reply(Data(("{\"code\":200,\"data\":" + text + "}").utf8), 200)
    }
    private func harness(accepted: Bool = true, completed: Bool = false) throws -> Harness {
        let identity = Identity(try session())
        let anchors = BackpackRecoveryTestAnchors(), ciphertexts = BackpackRecoveryTestCiphertexts()
        let store = try PlayThemeBackpackRecoveryStore(session: identity.value!, scope: .topic(7), topicID: 7, anchors: anchors, ciphertexts: ciphertexts)
        let http = PlayRecoveryRecordingTransport()
        http.responses["/api/play/theme/state"] = response(raw(version: 4))
        http.queues["/api/play/theme/state"] = [response(raw())]
        http.responses["/api/play/theme/action"] = response(raw(version: 4))
        let service = PlayThemeBackpackActionService(configuration: try .init(baseURL: URL(string: "https://fixture.example/")!), transport: http, accepted: accepted, completedReceiveAccepted: completed)
        let actions = PlayThemeBackpackActions(service: service, scope: .topic(7), topicID: 7, current: { identity.value }, recovery: store)
        return .init(actions: actions, http: http, store: store, identity: identity, anchors: anchors, ciphertexts: ciphertexts)
    }
    private func posts(_ h: Harness) -> [URLRequest] { h.http.requests.filter { $0.httpMethod == "POST" } }
    private func loseReply(_ h: Harness, operation: PlayThemeBackpackOperation = .use, content: String = "tea") async throws {
        await h.actions.refresh()
        try h.actions.begin(operation, contentID: content)
        h.http.responses["/api/play/theme/action"] = .failure(.unknownResult)
        await h.actions.confirm()
        XCTAssertEqual(h.actions.phase, .unknown)
    }
    func testUseRequiresReviewAndPersistsBeforeOriginalPost() async throws {
        let h = try harness(); await h.actions.refresh()
        XCTAssertEqual(posts(h).count, 0)
        try h.actions.begin(.use, contentID: "tea")
        XCTAssertEqual(posts(h).count, 0)
        let reviewed = try XCTUnwrap(h.actions.review)
        await h.actions.confirm()
        XCTAssertEqual(posts(h).count, 1)
        XCTAssertEqual(posts(h)[0].httpBody, reviewed.body)
        XCTAssertEqual(h.actions.lastConfirmedOperation, .use)
        let stored = try await h.store.read(); XCTAssertNil(stored)
    }
    func testDiscardAndReceiveUseOnlyOriginalPersonalRoute() async throws {
        for (operation, id) in [(PlayThemeBackpackOperation.discard, "tea"), (.receive, "chapter:1:END:0")] {
            let h = try harness(); await h.actions.refresh()
            try h.actions.begin(operation, contentID: id); await h.actions.confirm()
            let request = try XCTUnwrap(posts(h).first)
            XCTAssertEqual(request.url?.path, "/api/play/theme/action")
            let body = try JSONDecoder().decode(PlayThemeBackpackCommand.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(body.operation, operation); XCTAssertEqual(body.contentId, id)
            XCTAssertNil(body.discardOwned)
        }
    }
    func testUnknownRefreshCannotClearOrChangeOriginalVersion() async throws {
        let h = try harness(); try await loseReply(h)
        let original = try XCTUnwrap(posts(h).first?.httpBody)
        h.http.responses["/api/play/theme/state"] = response(raw(version: 20))
        await h.actions.refresh()
        XCTAssertEqual(h.actions.phase, .unknown)
        XCTAssertEqual(h.actions.pendingCommand?.expectedVersion, 3)
        XCTAssertThrowsError(try h.actions.begin(.discard, contentID: "tea"))
        XCTAssertEqual(posts(h).count, 1)
        h.http.responses["/api/play/theme/action"] = response(raw(version: 4))
        await h.actions.recover()
        XCTAssertEqual(posts(h).count, 2); XCTAssertEqual(posts(h)[1].httpBody, original)
        XCTAssertEqual(h.actions.facts?.version, 20)
        XCTAssertEqual(h.actions.phase, .ready)
    }
    func testDeclaredErrorDoesNotUnlockUnknownIntent() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        h.http.responses["/api/play/theme/action"] = .reply(Data(#"{"code":409,"msg":"本局已更新，请刷新"}"#.utf8), 200)
        await h.actions.confirm()
        XCTAssertEqual(h.actions.phase, .unknown)
        let stored = try await h.store.read(); XCTAssertEqual(stored?.value.state, .unknown)
    }
    func testMalformedOrWrongRunReceiptDoesNotAcknowledge() async throws {
        for value in [raw(version: 4, run: 42), raw(version: 3), raw(version: 5), raw(version: 4, activity: 9)] {
            let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
            h.http.responses["/api/play/theme/action"] = response(value)
            await h.actions.confirm()
            XCTAssertEqual(h.actions.phase, .unknown); XCTAssertNil(h.actions.lastConfirmedOperation)
            let stored = try await h.store.read(); XCTAssertNotNil(stored)
        }
    }
    func testRestartReplaysSameBytesOnlyAfterExplicitRetry() async throws {
        let h = try harness(); try await loseReply(h)
        let body = try XCTUnwrap(posts(h).first?.httpBody)
        let nextSession = try session(epoch: 2); h.identity.value = nextSession
        let store = try PlayThemeBackpackRecoveryStore(session: nextSession, scope: .topic(7), topicID: 7, anchors: h.anchors, ciphertexts: h.ciphertexts, processID: UUID())
        let service = PlayThemeBackpackActionService(configuration: try .init(baseURL: URL(string: "https://fixture.example/")!), transport: h.http, accepted: true)
        let restored = PlayThemeBackpackActions(service: service, scope: .topic(7), topicID: 7, current: { h.identity.value }, recovery: store)
        await restored.refresh()
        XCTAssertEqual(restored.phase, .unknown); XCTAssertEqual(posts(h).count, 1)
        XCTAssertTrue(h.http.requests.last?.url?.query?.contains("sessionId=41") == true)
        h.http.responses["/api/play/theme/action"] = response(raw(version: 4))
        await restored.recover()
        XCTAssertEqual(posts(h).count, 2); XCTAssertEqual(posts(h)[1].httpBody, body)
    }
    func testCurrentProcessActiveRequestCannotBeReplayed() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        let stored = try await h.store.prepare(XCTUnwrap(h.actions.review))
        _ = try await h.store.transition(stored, to: .dispatching)
        h.actions.cancelReview(); await h.actions.refresh()
        XCTAssertEqual(h.actions.phase, .active)
        await h.actions.recover(); XCTAssertEqual(posts(h).count, 0)
    }
    func testOldProcessDispatchRestoresUnknownWithoutAutomaticPost() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        let stored = try await h.store.prepare(XCTUnwrap(h.actions.review))
        _ = try await h.store.transition(stored, to: .dispatching)
        let nextStore = try PlayThemeBackpackRecoveryStore(session: h.identity.value!, scope: .topic(7), topicID: 7, anchors: h.anchors, ciphertexts: h.ciphertexts, processID: UUID())
        let service = PlayThemeBackpackActionService(configuration: try .init(baseURL: URL(string: "https://fixture.example/")!), transport: h.http, accepted: true)
        let next = PlayThemeBackpackActions(service: service, scope: .topic(7), topicID: 7, current: { h.identity.value }, recovery: nextStore)
        await next.refresh(); XCTAssertEqual(next.phase, .unknown); XCTAssertEqual(posts(h).count, 0)
        await next.recover(); XCTAssertEqual(posts(h).count, 1)
    }
    func testSwitchAccountWhileWriteInFlightHidesResultAndKeepsJournal() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        h.http.pauseResponse = true
        let work = Task { await h.actions.confirm() }
        for _ in 0..<1_000 { if h.http.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(h.http.isAwaitingResponse)
        h.identity.value = try session(account: 12)
        h.http.resumeResponse(); await work.value
        XCTAssertNil(h.actions.facts); XCTAssertNil(h.actions.lastConfirmedOperation)
        XCTAssertEqual(h.actions.phase, .stale)
        let stored = try await h.store.read(); XCTAssertEqual(stored?.value.state, .unknown)
    }
    func testBackgroundSuspensionCannotStartNewActionOrDisplayLateReceipt() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        h.http.pauseResponse = true
        let work = Task { await h.actions.confirm() }
        for _ in 0..<1_000 { if h.http.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(h.http.isAwaitingResponse)
        h.actions.suspend(); h.http.resumeResponse(); await work.value
        XCTAssertNil(h.actions.facts); XCTAssertEqual(h.actions.phase, .stale)
        XCTAssertEqual(posts(h).count, 1)
        h.actions.activate(); await h.actions.refresh()
        XCTAssertEqual(h.actions.phase, .unknown); XCTAssertEqual(posts(h).count, 1)
    }
    func testCancelledWriteRemainsUnknownAndNotAutomaticRetry() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        h.http.pauseResponse = true
        let work = Task { await h.actions.confirm() }
        for _ in 0..<1_000 { if h.http.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(h.http.isAwaitingResponse)
        work.cancel(); h.http.resumeResponse(); await work.value
        XCTAssertEqual(h.actions.phase, .unknown); XCTAssertEqual(posts(h).count, 1)
        let stored = try await h.store.read(); XCTAssertEqual(stored?.value.state, .unknown)
    }
    func testAcknowledgedWriteWithFailedRefreshRequiresFreshReadBeforeNewIntent() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        h.http.responses["/api/play/theme/state"] = .failure(.unknownResult)
        await h.actions.confirm()
        XCTAssertEqual(h.actions.lastConfirmedOperation, .use)
        XCTAssertFalse(h.actions.canStart); XCTAssertEqual(posts(h).count, 1)
        let stored = try await h.store.read(); XCTAssertNil(stored)
        h.http.responses["/api/play/theme/state"] = response(raw(version: 4))
        await h.actions.refresh(); XCTAssertTrue(h.actions.canStart); XCTAssertEqual(posts(h).count, 1)
    }
    func testNoAcceptanceAndNoStoreFailClosed() async throws {
        let h = try harness(accepted: false); await h.actions.refresh()
        XCTAssertTrue(h.http.requests.isEmpty); XCTAssertFalse(h.actions.canStart)
        let service = PlayThemeBackpackActionService(configuration: try .init(baseURL: URL(string: "https://fixture.example/")!), transport: h.http, accepted: true)
        let actions = PlayThemeBackpackActions(service: service, scope: .topic(7), topicID: 7, current: { h.identity.value }, recovery: nil)
        await actions.refresh(); XCTAssertEqual(actions.phase, .storageUnavailable); XCTAssertTrue(h.http.requests.isEmpty)
    }
    func testSelfPlayReadIncludesExplicitZeroActivityAndNeverPretendsReadIsReceipt() async throws {
        let h = try harness(); await h.actions.refresh()
        XCTAssertEqual(h.http.requests.first?.url?.query, "activityId=0&topicId=7")
        XCTAssertNil(h.actions.lastConfirmedOperation)
    }
    func testTeamUnknownScopeAndWrongTopicNeverProduceActions() throws {
        for replacement in ["\"scope\":\"TEAM\",", "\"scope\":\"FUTURE\",", "\"runtimeScope\":\"OTHER\","] {
            let value = raw().replacingOccurrences(of: "\"runtimeScope\":\"PLAYER\",", with: replacement)
            XCTAssertThrowsError(try PlayThemeBackpackActionFacts(wire(value), scope: .topic(7), topicID: 7))
        }
        XCTAssertThrowsError(try PlayThemeBackpackActionFacts(wire(raw()), scope: .topic(8), topicID: 8))
        XCTAssertThrowsError(try PlayThemeBackpackActionFacts(wire(raw(activity: 9)), scope: .topic(7), topicID: 7))
    }
    func testCompletedClaimsRemainClosedWithoutSeparateBackendAcceptance() throws {
        let facts = try PlayThemeBackpackActionFacts(wire(raw(status: "COMPLETED")), scope: .topic(7), topicID: 7)
        XCTAssertFalse(facts.allows(.use, contentID: "tea", completedReceiveAccepted: true))
        XCTAssertFalse(facts.allows(.discard, contentID: "tea", completedReceiveAccepted: true))
        XCTAssertFalse(facts.allows(.receive, contentID: "chapter:1:END:0", completedReceiveAccepted: false))
        XCTAssertTrue(facts.allows(.receive, contentID: "chapter:1:END:0", completedReceiveAccepted: true))
        XCTAssertFalse(try PlayThemeBackpackActionFacts(wire(raw(status: "ENDED")), scope: .topic(7), topicID: 7).allows(.receive, contentID: "chapter:1:END:0", completedReceiveAccepted: true))
    }
    func testHeldWearMissingStatsAndDisallowedDiscardCannotStartUse() throws {
        let worn = raw().replacingOccurrences(of: "\"delta\":2", with: "\"delta\":2,\"worn\":true")
        XCTAssertFalse(try PlayThemeBackpackActionFacts(wire(worn), scope: .topic(7), topicID: 7).allows(.use, contentID: "tea", completedReceiveAccepted: false))
        let noDiscard = raw().replacingOccurrences(of: "\"allowDiscard\":true", with: "\"allowDiscard\":false")
        XCTAssertFalse(try PlayThemeBackpackActionFacts(wire(noDiscard), scope: .topic(7), topicID: 7).allows(.discard, contentID: "tea", completedReceiveAccepted: false))
    }
    func testCompletedDiscardSelectionValidatesOwnerQuantityAndActiveRejectsField() throws {
        let completed = try PlayThemeBackpackActionFacts(wire(raw(status: "COMPLETED")), scope: .topic(7), topicID: 7)
        XCTAssertThrowsError(try completed.review(.receive, contentID: "chapter:1:END:0", discardOwned: [.init(itemID: "tea", quantity: 4)], completedReceiveAccepted: true))
        XCTAssertThrowsError(try completed.review(.receive, contentID: "chapter:1:END:0", discardOwned: [.init(itemID: "other", quantity: 1)], completedReceiveAccepted: true))
        let active = try PlayThemeBackpackActionFacts(wire(raw()), scope: .topic(7), topicID: 7)
        XCTAssertThrowsError(try active.review(.receive, contentID: "chapter:1:END:0", discardOwned: [], completedReceiveAccepted: true))
    }
    func testBodyDistinguishesOmittedAndEmptyDiscardsAndPreservesUTF8() throws {
        let original = try PlayThemeBackpackCommand(sessionID: 41, version: 3, operation: .receive, contentID: "e\u{301}", discardOwned: nil, actionID: "bag_same")
        let empty = try PlayThemeBackpackCommand(sessionID: 41, version: 3, operation: .receive, contentID: "e\u{301}", discardOwned: [], actionID: "bag_same")
        let composed = try PlayThemeBackpackCommand(sessionID: 41, version: 3, operation: .receive, contentID: "é", discardOwned: nil, actionID: "bag_same")
        XCTAssertNotEqual(original, empty); XCTAssertNotEqual(original, composed)
        let intent = try PlayThemeBackpackIntent(session: session(), scope: .topic(7), topicID: 7, command: original)
        let bytes = try PropertyListEncoder().encode(intent)
        let restored = try PropertyListDecoder().decode(PlayThemeBackpackIntent.self, from: bytes)
        XCTAssertEqual(restored.body, intent.body); try restored.validate()
    }
    func testReservedSuppliesAndCapacityPreventKnownRejectedNewWrites() throws {
        let reserved = raw().replacingOccurrences(of: "\"used\":3", with: "\"activeQuest\":\"quest1\",\"used\":3")
        let facts = try PlayThemeBackpackActionFacts(wire(reserved), scope: .topic(7), topicID: 7)
        XCTAssertTrue(facts.hasReservedSupplies)
        XCTAssertFalse(facts.allows(.use, contentID: "tea", completedReceiveAccepted: false))
        XCTAssertFalse(facts.allows(.discard, contentID: "tea", completedReceiveAccepted: false))
        let full = try PlayThemeBackpackActionFacts(wire(raw().replacingOccurrences(of: "\"used\":3", with: "\"used\":6")), scope: .topic(7), topicID: 7)
        XCTAssertFalse(full.hasRoomForPending("chapter:1:END:0"))
        XCTAssertFalse(full.allows(.receive, contentID: "chapter:1:END:0", completedReceiveAccepted: false))
    }
    func testCompletedCapacityChoiceCannotDiscardMoreThanNeededFactsPermit() throws {
        let full = try PlayThemeBackpackActionFacts(wire(raw(status: "COMPLETED").replacingOccurrences(of: "\"used\":3", with: "\"used\":6")), scope: .topic(7), topicID: 7)
        XCTAssertThrowsError(try full.review(.receive, contentID: "chapter:1:END:0", discardOwned: [], completedReceiveAccepted: true))
        let command = try full.review(.receive, contentID: "chapter:1:END:0", discardOwned: [.init(itemID: "tea", quantity: 1)], completedReceiveAccepted: true)
        XCTAssertEqual(command.discardOwned, [.init(itemID: "tea", quantity: 1)])
    }
    func testMissingCapacityFactsNeverEnableReceive() throws {
        let missing = raw().replacingOccurrences(of: "\"slots\":1,", with: "")
        let facts = try PlayThemeBackpackActionFacts(wire(missing), scope: .topic(7), topicID: 7)
        XCTAssertFalse(facts.allows(.receive, contentID: "chapter:1:END:0", completedReceiveAccepted: false))
    }
    func testReviewCannotDispatchAfterRoleOrEpochChanges() async throws {
        for next in [try session(epoch: 2), try session(role: "merchant"), try session(namespace: "other-fixture")] {
            let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
            h.identity.value = next; await h.actions.confirm()
            XCTAssertTrue(posts(h).isEmpty); XCTAssertNil(h.actions.facts)
            let stored = try await h.store.read(); XCTAssertNil(stored)
        }
    }
    func testNewerReadIsNotAnAcknowledgementAndStaleReadDoesNotEnableNewWrite() async throws {
        let h = try harness(); await h.actions.refresh()
        h.http.responses["/api/play/theme/state"] = response(raw(version: 2)); await h.actions.refresh()
        XCTAssertFalse(h.actions.canStart); XCTAssertNil(h.actions.lastConfirmedOperation)
        XCTAssertTrue(posts(h).isEmpty)
    }

    func testReturnedActivityMismatchIsMalformedNotAnOwnerChange() async throws {
        for (scope, activity) in [(PlaySessionScope.topic(7), 9), (.activity(9), 10)] {
            XCTAssertThrowsError(try PlayThemeBackpackActionFacts(wire(raw(activity: activity)), scope: scope, topicID: 7)) { error in
                XCTAssertEqual(error as? PlayExperienceError, .malformed)
            }
        }
    }
    func testWrongActivityReceiptKeepsOriginalIntentUntilExactReplay() async throws {
        let h = try harness(); await h.actions.refresh(); try h.actions.begin(.use, contentID: "tea")
        let reviewed = try XCTUnwrap(h.actions.review)
        h.http.responses["/api/play/theme/action"] = response(raw(version: 4, activity: 9))
        await h.actions.confirm()
        XCTAssertEqual(h.actions.phase, .unknown); XCTAssertTrue(h.actions.isCurrent)
        XCTAssertNil(h.actions.lastConfirmedOperation)
        let pending = try await h.store.read()
        XCTAssertEqual(pending?.value.state, .unknown)
        XCTAssertEqual(pending?.value.intent, reviewed)
        XCTAssertEqual(posts(h).count, 1); XCTAssertEqual(posts(h)[0].httpBody, reviewed.body)
        h.http.responses["/api/play/theme/action"] = response(raw(version: 4))
        await h.actions.recover()
        XCTAssertEqual(posts(h).count, 2); XCTAssertEqual(posts(h)[1].httpBody, reviewed.body)
        XCTAssertEqual(h.actions.phase, .ready); XCTAssertEqual(h.actions.lastConfirmedOperation, .use)
        let final = try await h.store.read(); XCTAssertNil(final)
    }
    func testWrongActivityReadCannotRetireOwnerOrClearPendingIntent() async throws {
        let h = try harness(); try await loseReply(h)
        let original = try await h.store.read()
        h.http.responses["/api/play/theme/state"] = response(raw(version: 20, activity: 9))
        await h.actions.refresh()
        XCTAssertEqual(h.actions.phase, .unknown); XCTAssertTrue(h.actions.isCurrent)
        XCTAssertTrue(h.actions.canRecover); XCTAssertFalse(h.actions.canStart)
        XCTAssertNil(h.actions.lastConfirmedOperation); XCTAssertEqual(posts(h).count, 1)
        let preserved = try await h.store.read(); XCTAssertEqual(preserved, original)
        h.http.responses["/api/play/theme/state"] = response(raw(version: 20))
        await h.actions.refresh()
        XCTAssertEqual(h.actions.phase, .unknown); XCTAssertEqual(posts(h).count, 1)
        let afterRead = try await h.store.read(); XCTAssertEqual(afterRead, original)
    }
}
