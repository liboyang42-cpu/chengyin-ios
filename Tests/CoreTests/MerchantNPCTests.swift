import XCTest
@testable import QuestifyCore

@MainActor final class MerchantNPCTests: XCTestCase {
    final class HTTP: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []
        var json = #"{"code":200,"data":{"outcomeStatus":"SUCCEEDED","safeText":"Moderated answer"}}"#
        var status = 200
        var unknown = false
        var mutationUnknown = false
        var held = false
        var continuation: CheckedContinuation<Void, Never>?
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if held { await withCheckedContinuation { continuation = $0 } }
            if unknown || (mutationUnknown && !request.path.hasSuffix("script")) { throw MerchantNPCFailure.unknownOutcome }
            if request.path.hasSuffix("script") { return .init(status: 200, body: Data(#"{"code":200,"data":{"available":true,"script":["Synthetic authorization","2","3","4","5"],"consentIndex":0}}"#.utf8)) }
            return .init(status: status, body: Data(json.utf8))
        }
    }
    final class Journal: OperationPendingJournal {
        var records: [String: OperationPendingRecord] = [:]
        var failWrites = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
        func write(_ record: OperationPendingRecord) throws {
            if failWrites { throw MerchantNPCFailure.unknownOutcome }
            guard records[record.ownerKey + record.targetKey] == nil else { throw MerchantNPCFailure.unknownOutcome }
            records[record.ownerKey + record.targetKey] = record
        }
        func clear(_ record: OperationPendingRecord) throws { records.removeValue(forKey: record.ownerKey + record.targetKey) }
    }
    let scope = MerchantNPCScope(accountID: 901, namespace: "synthetic.invalid", epoch: UUID(), merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
    func grants() -> MerchantNPCGrants { var g = MerchantNPCGrants(); g.server = true; g.provider = true; g.legal = true; g.resourceOwnership = true; g.voiceCloning = true; g.mediaTransmission = true; return g }
    func body(_ http: HTTP) throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.requests.last).body) as? [String: Any]) }
    func media(_ kind: MerchantNPCMediaReference.Kind) throws -> MerchantNPCMediaReference { try .init(scope: scope, selectionID: UUID(), kind: kind, url: URL(string: "https://synthetic.invalid/sample")!, approvedHosts: ["synthetic.invalid"]) }
    func resource(_ http: HTTP, reader: MerchantOperationsFixtureReader? = nil, journal: (any OperationPendingJournal)? = nil) throws -> MerchantNPCResourcesCoordinator {
        let reader = reader ?? MerchantOperationsFixtureReader()
        let journal = journal ?? Journal()
        let voice = try JSONDecoder().decode(MerchantVoiceResource.self, from: Data(#"{"voiceStatus":0}"#.utf8))
        let avatar = try JSONDecoder().decode(MerchantAvatarResource.self, from: Data(#"{"available":true,"styles":["realistic"],"job":null}"#.utf8))
        reader.replace(.assets, with: .assets(.init(voice: voice, avatar: avatar)))
        return .init(scope: scope, client: .init(transport: http), reader: reader, journal: journal, currentScope: { self.scope }, grants: { self.grants() })
    }
    func testMerchantRowBodyHasNoNodeOrOwner() async throws {
        let h = HTTP(); let id = UUID(); _ = try await MerchantNPCHTTPClient(transport: h).chat(message: "Hello", requestID: id, scope: scope)
        XCTAssertEqual(h.requests.first?.path, "/api/ai/npc/merchant-chat"); XCTAssertEqual(h.requests.first?.method, "POST")
        let b = try body(h); XCTAssertEqual(Set(b.keys), ["requestId", "bizId", "message"]); XCTAssertEqual(b["bizId"] as? Int, 31); XCTAssertEqual(b["requestId"] as? String, id.uuidString)
    }
    func testBusinessErrorPreservesMessage() async {
        let h = HTTP(); h.json = #"{"code":403,"msg":"Server disabled","data":"not an object"}"#
        do { _ = try await MerchantNPCHTTPClient(transport: h).chat(message: "Hi", requestID: UUID(), scope: scope); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCFailure, .rejected(code: 403, message: "Server disabled")) }
    }
    func testDefaultTransportCannotSend() async {
        do { _ = try await MerchantNPCHTTPClient().chat(message: "Hi", requestID: UUID(), scope: scope); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
    }
    func testDefaultGrantsDoNotCallTransport() async {
        let h = HTTP(); let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { .init() })
        await c.send("Hi"); XCTAssertTrue(h.requests.isEmpty)
    }
    func testUnknownRetryReusesRequestIdentity() async throws {
        let h = HTTP(); h.unknown = true
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
        await c.send("Hi"); let first = try body(h); await c.retry(); XCTAssertEqual(try body(h)["requestId"] as? String, first["requestId"] as? String)
        await c.retry(); await c.retry(); XCTAssertEqual(h.requests.count, 3)
    }
    func testRetryAfterHonored() async {
        let h = HTTP(); h.json = #"{"code":200,"data":{"outcomeStatus":"PROCESSING","retryAfterSeconds":60}}"#
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
        await c.send("Hi"); XCTAssertFalse(c.canRetry); await c.retry(); XCTAssertEqual(h.requests.count, 1)
    }
    func testScopeChangeFencesLateReply() async {
        let h = HTTP(); h.held = true; var current: MerchantNPCScope? = scope
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { current }, grants: { self.grants() })
        let task = Task { await c.send("Private") }
        while h.continuation == nil { await Task.yield() }
        current = nil; h.continuation?.resume(); await task.value
        XCTAssertNil(c.reply); XCTAssertNil(c.message); XCTAssertFalse(c.isCurrent)
    }
    func testInterruptionClearsUnknownRequestAndResumesOnlyAnEmptyConversation() async throws {
        let h = HTTP(); h.unknown = true
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
        await c.send("Private old request"); let first = try body(h)
        XCTAssertEqual(c.failure, .unknownOutcome); XCTAssertTrue(c.canRetry)
        c.interrupt(); c.interrupt() // Inactive followed by background remains a single resumable interruption.
        XCTAssertTrue(c.isInterrupted); XCTAssertFalse(c.isCurrent); XCTAssertFalse(c.canSend); XCTAssertFalse(c.canRetry)
        XCTAssertNil(c.message); XCTAssertNil(c.reply); XCTAssertNil(c.requestID); XCTAssertNil(c.retryAt); XCTAssertNil(c.failure)
        XCTAssertFalse(c.sending); XCTAssertTrue(c.canResumeAfterInterruption)
        c.revalidateInterruption()
        XCTAssertFalse(c.isCurrent); XCTAssertEqual(h.requests.count, 1) // Foregrounding does not resume or dispatch.
        c.resumeAfterInterruption(); c.resumeAfterInterruption()
        XCTAssertTrue(c.isCurrent); XCTAssertTrue(c.canSend); XCTAssertFalse(c.isInterrupted)
        XCTAssertNil(c.message); XCTAssertNil(c.reply); XCTAssertEqual(h.requests.count, 1)
        h.unknown = false; await c.send("New explicit question")
        let second = try body(h)
        XCTAssertEqual(h.requests.count, 2)
        XCTAssertNotEqual(first["requestId"] as? String, second["requestId"] as? String)
        XCTAssertEqual(second["message"] as? String, "New explicit question")
        XCTAssertEqual(second["bizId"] as? Int, scope.merchantRowID.rawValue)
        XCTAssertNotNil(c.reply)
        c.interrupt()
        XCTAssertNil(c.reply); XCTAssertNil(c.message); XCTAssertNil(c.retryAt)
        c.revalidateInterruption(); XCTAssertEqual(h.requests.count, 2)
    }
    func testQueuedRetryCannotTargetRequestCreatedAfterInterruption() async throws {
        let h = HTTP(); h.unknown = true
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
        await c.send("Old question")
        let capturedRequestID = try XCTUnwrap(c.requestID)
        var releaseQueuedRetry: CheckedContinuation<Void, Never>?
        let queuedRetry = Task {
            await withCheckedContinuation { releaseQueuedRetry = $0 }
            await c.retry(requestID: capturedRequestID)
        }
        while releaseQueuedRetry == nil { await Task.yield() }
        c.interrupt(); c.resumeAfterInterruption()
        await c.send("New question")
        let currentRequestID = try XCTUnwrap(c.requestID)
        XCTAssertNotEqual(capturedRequestID, currentRequestID); XCTAssertTrue(c.canRetry)
        releaseQueuedRetry?.resume(); await queuedRetry.value
        XCTAssertEqual(h.requests.count, 2) // The old queued intent cannot retry the new request.
        XCTAssertEqual(c.requestID, currentRequestID); XCTAssertEqual(c.message, "New question")
        XCTAssertTrue(c.canRetry); XCTAssertEqual(c.failure, .unknownOutcome)
        await c.retry(requestID: currentRequestID) // A new explicit retry still uses the current idempotency key.
        XCTAssertEqual(h.requests.count, 3)
        XCTAssertEqual(try body(h)["requestId"] as? String, currentRequestID.uuidString)
        XCTAssertEqual(try body(h)["message"] as? String, "New question")
    }
    func testInterruptedOwnerCannotResumeAfterAnyScopeChange() async {
        let changed: [MerchantNPCScope?] = [
            nil,
            .init(accountID: 902, namespace: scope.namespace, epoch: scope.epoch, merchantRowID: scope.merchantRowID, accessRevision: scope.accessRevision),
            .init(accountID: scope.accountID, namespace: "other.invalid", epoch: scope.epoch, merchantRowID: scope.merchantRowID, accessRevision: scope.accessRevision),
            .init(accountID: scope.accountID, namespace: scope.namespace, epoch: UUID(), merchantRowID: scope.merchantRowID, accessRevision: scope.accessRevision),
            .init(accountID: scope.accountID, namespace: scope.namespace, epoch: scope.epoch, merchantRowID: PublicMerchantRowID(32)!, accessRevision: scope.accessRevision),
            .init(accountID: scope.accountID, namespace: scope.namespace, epoch: scope.epoch, merchantRowID: scope.merchantRowID, accessRevision: UUID())
        ]
        for replacement in changed {
            let h = HTTP(); var current: MerchantNPCScope? = scope
            let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { current }, grants: { self.grants() })
            c.interrupt(); current = replacement
            XCTAssertFalse(c.canResumeAfterInterruption)
            c.resumeAfterInterruption()
            XCTAssertFalse(c.isInterrupted); XCTAssertFalse(c.isCurrent)
            current = scope; c.interrupt(); c.resumeAfterInterruption()
            await c.send("Must not revive a stale owner")
            XCTAssertFalse(c.isCurrent); XCTAssertTrue(h.requests.isEmpty)
        }
    }
    func testRevokedGrantOrExplicitInvalidationPermanentlyBlocksRestart() async {
        for boundary in 0..<4 {
            let h = HTTP(); var policy = grants()
            let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { policy })
            c.interrupt()
            switch boundary {
            case 0: policy.server = false
            case 1: policy.provider = false
            case 2: policy.legal = false
            default: c.invalidate() // Session owner, logout or destination dismissal.
            }
            c.revalidateInterruption(); c.resumeAfterInterruption()
            XCTAssertFalse(c.isCurrent); XCTAssertFalse(c.isInterrupted)
            policy = grants(); c.interrupt(); c.resumeAfterInterruption()
            await c.send("Blocked after revoked authority")
            XCTAssertFalse(c.isCurrent); XCTAssertTrue(h.requests.isEmpty)
        }
    }
    func testDefaultGrantsCannotCreateResumableConversation() async {
        let h = HTTP()
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { .init() })
        c.interrupt(); c.resumeAfterInterruption(); await c.send("Blocked")
        XCTAssertFalse(c.isInterrupted); XCTAssertFalse(c.canSend); XCTAssertTrue(h.requests.isEmpty)
    }
    func testNewRequestRechecksGrantsAfterExplicitRestart() async {
        let h = HTTP(); var policy = grants()
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { policy })
        c.interrupt(); c.resumeAfterInterruption(); XCTAssertTrue(c.canSend)
        policy.legal = false
        await c.send("Not authorized now")
        XCTAssertFalse(c.canSend); XCTAssertTrue(h.requests.isEmpty)
        for transportFails in [false, true] {
            let pendingHTTP = HTTP(); pendingHTTP.held = true
            var currentPolicy = grants()
            let pending = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: pendingHTTP), currentScope: { self.scope }, grants: { currentPolicy })
            pending.interrupt(); pending.resumeAfterInterruption()
            let task = Task { await pending.send("Authority changes while waiting") }
            while pendingHTTP.continuation == nil { await Task.yield() }
            currentPolicy.legal = false; pendingHTTP.unknown = transportFails
            pendingHTTP.continuation?.resume(); await task.value
            XCTAssertFalse(pending.isCurrent); XCTAssertFalse(pending.sending)
            XCTAssertNil(pending.reply); XCTAssertNil(pending.message); XCTAssertNil(pending.failure)
            currentPolicy = grants(); pending.interrupt(); pending.resumeAfterInterruption()
            XCTAssertFalse(pending.isCurrent); XCTAssertEqual(pendingHTTP.requests.count, 1)
        }
    }
    func testLateInterruptedCompletionCannotInvalidateNewRequest() async {
        for oldOutcome in ["success", "failure", "cancelled"] {
            let h = HTTP(); h.held = true
            let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
            let oldTask = Task { await c.send("Old private question") }
            while h.continuation == nil { await Task.yield() }
            let old = h.continuation; h.continuation = nil
            c.interrupt(); c.resumeAfterInterruption()
            let newTask = Task { await c.send("New question") }
            while h.continuation == nil { await Task.yield() }
            let new = h.continuation
            h.unknown = oldOutcome == "failure"
            if oldOutcome == "cancelled" { oldTask.cancel() }
            old?.resume(); await oldTask.value
            XCTAssertTrue(c.isCurrent, oldOutcome); XCTAssertTrue(c.sending, oldOutcome)
            XCTAssertEqual(c.message, "New question", oldOutcome); XCTAssertNil(c.reply); XCTAssertNil(c.failure)
            h.unknown = false; new?.resume(); await newTask.value
            XCTAssertTrue(c.isCurrent); XCTAssertFalse(c.sending)
            XCTAssertEqual(c.message, "New question"); XCTAssertEqual(c.reply?.safeText, "Moderated answer")
            XCTAssertEqual(h.requests.count, 2)
        }
    }
    func testRejectedReplyDoesNotExposeAudio() throws {
        let reply = try JSONDecoder().decode(MerchantNPCReply.self, from: Data(#"{"outcomeStatus":"REJECTED","audioUrl":"https://synthetic.invalid/audio"}"#.utf8))
        XCTAssertNil(reply.successAudioURL); XCTAssertFalse(reply.canRetry)
    }
    func testFiveSamplesAuthorizationFirst() throws {
        let malformed = try JSONDecoder().decode(MerchantNPCVoiceScript.self, from: Data(#"{"available":true,"script":["1","2","3","4","5"],"consentIndex":1}"#.utf8))
        XCTAssertFalse(malformed.isUsable)
    }
    func testMediaRejectsUnapprovedHost() {
        XCTAssertThrowsError(try MerchantNPCMediaReference(scope: scope, selectionID: UUID(), kind: .avatarImage, url: URL(string: "https://elsewhere.invalid/a")!, approvedHosts: ["synthetic.invalid"]))
    }
    func testConsentAndOwnershipRequired() async throws {
        let h = HTTP(); let c = try resource(h); await c.refresh(); let samples = try (0..<5).map { try media(.voiceSample(index: $0)) }
        XCTAssertThrowsError(try c.prepare(.enroll(samples: samples, requestID: UUID()), ownsVoice: false, explicitConsent: true))
        XCTAssertThrowsError(try c.prepare(.enroll(samples: samples, requestID: UUID()), ownsVoice: true, explicitConsent: false))
    }
    func testOutOfOrderSamplesRejected() async throws {
        let h = HTTP(); let c = try resource(h); await c.refresh(); let samples = try (0..<5).reversed().map { try media(.voiceSample(index: $0)) }
        XCTAssertThrowsError(try c.prepare(.enroll(samples: samples, requestID: UUID()), ownsVoice: true, explicitConsent: true))
    }
    func testEnrollExactBodyAcceptanceNotReady() async throws {
        let h = HTTP(); h.json = #"{"code":200,"msg":"Accepted","data":true}"#
        let c = try resource(h); await c.refresh(); let id = UUID(); let samples = try (0..<5).map { try media(.voiceSample(index: $0)) }
        try c.prepare(.enroll(samples: samples, requestID: id), ownsVoice: true, explicitConsent: true)
        await c.confirm(try XCTUnwrap(c.review).id)
        let request = try XCTUnwrap(h.requests.first { $0.path.hasSuffix("enroll") }); let b = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(Set(b.keys), ["sampleUrls", "requestId"]); XCTAssertEqual((b["sampleUrls"] as? [String])?.count, 5)
        XCTAssertEqual(c.outcome, .accepted(.accepted(message: "Accepted"))); XCTAssertEqual(c.resources?.voice.voiceStatus, 0)
    }
    func testUnknownWriteLocksRepeat() async throws {
        let h = HTTP(); let c = try resource(h); await c.refresh(); h.mutationUnknown = true
        let action = MerchantNPCResourceAction.revoke(requestID: UUID()); try c.prepare(action, ownsVoice: false, explicitConsent: true)
        await c.confirm(try XCTUnwrap(c.review).id); XCTAssertEqual(c.outcome, .unknown)
        XCTAssertThrowsError(try c.prepare(action, ownsVoice: false, explicitConsent: true))
    }
    func testRevokeFailureNotSuccess() async throws {
        let h = HTTP(); let c = try resource(h); await c.refresh(); h.json = #"{"code":500,"msg":"Remote deletion failed"}"#
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true); await c.confirm(try XCTUnwrap(c.review).id)
        XCTAssertEqual(c.outcome, .rejected)
    }
    func testAvatarExactBodyNoInventedRequestID() async throws {
        let h = HTTP(); h.json = #"{"code":200,"data":{"jobId":41,"status":"PENDING"}}"#
        _ = try await MerchantNPCHTTPClient(transport: h).perform(.avatar(image: try media(.avatarImage), style: "realistic"), scope: scope)
        XCTAssertEqual(Set(try body(h).keys), ["imageUrl", "style"])
    }
    func testUnknownAvatarStatusDoesNotPoll() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader)
        let voice = try JSONDecoder().decode(MerchantVoiceResource.self, from: Data(#"{"voiceStatus":99}"#.utf8))
        let avatar = try JSONDecoder().decode(MerchantAvatarResource.self, from: Data(#"{"available":false,"styles":[],"job":{"jobId":1,"status":"UNRECOGNIZED"}}"#.utf8))
        reader.replace(.assets, with: .assets(.init(voice: voice, avatar: avatar))); await c.refresh(); XCTAssertFalse(c.shouldPoll)
    }
    func testFailedReadPreservesObservedStatus() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader); await c.refresh()
        let old = c.resources; reader.failure = .malformedResponse; await c.refresh(); XCTAssertEqual(c.resources, old); XCTAssertNil(c.script)
    }
    func testReviewInvalidatesAfterSignOut() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader); await c.refresh()
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true); let id = try XCTUnwrap(c.review).id
        reader.signOut(); await c.confirm(id); XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("revoke") })
    }
    func testDeniedRefreshPreservesDisplayButRevokesReviewAndAuthority() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader)
        await c.refresh(); let observed = c.resources
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        let reviewID = try XCTUnwrap(c.review).id
        reader.denied = true; await c.refresh()
        XCTAssertEqual(c.resources, observed); XCTAssertNil(c.review); XCTAssertFalse(c.canGenerate); XCTAssertFalse(c.canEnroll)
        XCTAssertThrowsError(try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true))
        await c.confirm(reviewID); XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("revoke") })
    }
    func testConfirmRechecksAccessEvenWithoutExplicitRefresh() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader)
        await c.refresh(); try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        let reviewID = try XCTUnwrap(c.review).id; reader.denied = true
        await c.confirm(reviewID); XCTAssertNil(c.review); XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("revoke") })
    }
    func testConfirmRechecksAvatarPendingStatus() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let c = try resource(h, reader: reader)
        await c.refresh(); try c.prepare(.avatar(image: try media(.avatarImage), style: "realistic"), ownsVoice: false, explicitConsent: true)
        let reviewID = try XCTUnwrap(c.review).id
        let avatar = try JSONDecoder().decode(MerchantAvatarResource.self, from: Data(#"{"available":true,"styles":["realistic"],"job":{"jobId":42,"status":"PENDING"}}"#.utf8))
        reader.replace(.assets, with: .assets(.init(voice: try XCTUnwrap(c.resources).voice, avatar: avatar)))
        await c.confirm(reviewID); XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("generate") })
    }
    func testUnknownSurvivesRecreationAndLoginEpochWithDurableStore() async throws {
        let suite = "merchant-npc-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let h = HTTP(); let reader = MerchantOperationsFixtureReader()
        let c = try resource(h, reader: reader, journal: OperationDefaultsJournal(defaults: defaults))
        await c.refresh(); h.mutationUnknown = true
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        await c.confirm(try XCTUnwrap(c.review).id); XCTAssertEqual(c.outcome, .unknown); c.invalidate()
        let newScope = MerchantNPCScope(accountID: scope.accountID, namespace: scope.namespace, epoch: UUID(), merchantRowID: scope.merchantRowID, accessRevision: UUID())
        let reopened = MerchantNPCResourcesCoordinator(scope: newScope, client: .init(transport: h), reader: reader, journal: OperationDefaultsJournal(defaults: try XCTUnwrap(UserDefaults(suiteName: suite))), currentScope: { newScope }, grants: { self.grants() })
        await reopened.refresh(); XCTAssertTrue(reopened.hasUnresolvedWrite); XCTAssertEqual(reopened.outcome, .unknown)
        XCTAssertThrowsError(try reopened.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true))
        XCTAssertEqual(h.requests.filter { $0.path.hasSuffix("revoke") }.count, 1)
    }
    func testJournalFailureStopsBeforeDispatch() async throws {
        let h = HTTP(); let journal = Journal(); journal.failWrites = true
        let c = try resource(h, journal: journal); await c.refresh()
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        await c.confirm(try XCTUnwrap(c.review).id); XCTAssertEqual(c.outcome, .unknown)
        XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("revoke") })
    }
    func testMalformedDispatchedChatPreservesUUIDForRetry() async throws {
        let h = HTTP(); h.json = #"{"code":200,"data":null}"#
        let c = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: h), currentScope: { self.scope }, grants: { self.grants() })
        await c.send("Do not bill twice"); let first = try body(h)
        XCTAssertEqual(c.failure, .unknownOutcome); XCTAssertTrue(c.canRetry)
        h.json = #"{"code":200,"data":{"outcomeStatus":"SUCCEEDED","safeText":"Safe reply"}}"#
        await c.retry(); let second = try body(h)
        XCTAssertEqual(first["requestId"] as? String, second["requestId"] as? String)
        XCTAssertEqual(first["message"] as? String, second["message"] as? String)
        XCTAssertEqual(h.requests.count, 2)
    }

    func testJournalNamespaceAndAccountIsolation() async throws {
        let h = HTTP(); let reader = MerchantOperationsFixtureReader(); let journal = Journal()
        let c = try resource(h, reader: reader, journal: journal); await c.refresh(); h.mutationUnknown = true
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        await c.confirm(try XCTUnwrap(c.review).id); XCTAssertTrue(c.hasUnresolvedWrite)
        let otherNamespace = MerchantNPCScope(accountID: scope.accountID, namespace: "another.invalid", epoch: scope.epoch, merchantRowID: scope.merchantRowID, accessRevision: scope.accessRevision)
        let otherAccount = MerchantNPCScope(accountID: 902, namespace: scope.namespace, epoch: scope.epoch, merchantRowID: scope.merchantRowID, accessRevision: scope.accessRevision)
        for isolated in [otherNamespace, otherAccount] {
            let other = MerchantNPCResourcesCoordinator(scope: isolated, client: .init(transport: h), reader: reader, journal: journal, currentScope: { isolated }, grants: { self.grants() })
            XCTAssertFalse(other.hasUnresolvedWrite)
        }
    }

    func testConsentChangeDuringConfirmationReadCancelsDispatch() async throws {
        let h = HTTP(); let c = try resource(h); await c.refresh()
        try c.prepare(.revoke(requestID: UUID()), ownsVoice: false, explicitConsent: true)
        let id = try XCTUnwrap(c.review).id; h.held = true
        let task = Task { await c.confirm(id) }
        while h.continuation == nil { await Task.yield() }
        c.discardReview() // Same call used when consent/ownership/style changes in the editor.
        h.held = false; h.continuation?.resume(); await task.value
        XCTAssertNil(c.review); XCTAssertFalse(c.hasUnresolvedWrite)
        XCTAssertFalse(h.requests.contains { $0.path.hasSuffix("revoke") })
    }

}
