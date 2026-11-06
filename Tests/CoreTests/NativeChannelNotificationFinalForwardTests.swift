import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelNotificationFinalForwardTests: XCTestCase {
    func testNoSourceOrWrongJournalOwnerCannotConstruct() throws {
        let h = try NotificationForwardHarness(); h.selected = nil
        XCTAssertThrowsError(try h.adapter())
        h.selected = h.source
        let foreign = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player",
            session: try .init(accountID: 12, epoch: 1, namespace: "CN:forward", token: "fixture-token"))
        let other = NativeChannelNotificationJournal(storage: h.storage, owner: .init(context: foreign))
        XCTAssertThrowsError(try h.adapter(journal: other)); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testCanonicalReadScopesAndUnreadUseExistingService() async throws {
        let h = try NotificationForwardHarness(); let a = try h.adapter()
        let service = NativeChannelNotificationService(authority: a.authority, transport: a)
        for scope in [nil, try .init(type: 1, value: "9012"), try .init(type: 2, value: "42"), try .init(type: 4, value: "11")] as [NativeChannelNotificationScope?] {
            _ = try await service.preferences(scope: scope)
        }
        let unread = try await service.unreadSummary()
        XCTAssertEqual(unread.total, 0)
        XCTAssertEqual(h.wire.requests.count, 5)
        XCTAssertEqual(h.wire.requests[3].url?.query, "scope_type=4&scope_id=11")
    }
    func testForeignAccountScopeAndUnissuedOperationNeverForward() async throws {
        let h = try NotificationForwardHarness(); h.source.denied = [.mute]
        let a = try h.adapter(); let original = try h.command(); try h.journal.persist(original)
        await rejects(a, h.get("api/im/notify-pref?scope_type=4&scope_id=12"))
        await rejects(a, h.post(original)); XCTAssertTrue(h.wire.requests.isEmpty)
        _ = try await a.send(h.get("api/im/notification-requests/" + original.requestID), fence: .init { true })
        XCTAssertEqual(h.wire.requests.count, 1) // receipt grant is independent of mute.
    }
    func testCanonicalPreferenceAndMuteBodiesUseOriginalJournalBytesOnce() async throws {
        for mute in [false, true] {
            let h = try NotificationForwardHarness(); let a = try h.adapter()
            let original = try (mute ? h.command() : h.preferenceCommand())
            try h.journal.persist(original); let bytes = h.storage.rows
            let service = NativeChannelNotificationService(authority: a.authority, transport: a)
            let result = try await service.submit(original)
            XCTAssertEqual(result.status, "APPLIED"); XCTAssertEqual(result.requestID, original.requestID)
            XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests[0].httpBody, original.body)
            XCTAssertEqual(h.storage.rows, bytes) // only coordinator may settle, not final-forward.
        }
    }
    func testAckReceiptRejectsANumericResumeFlag() throws {
        let command = try NativeChannelNotificationCommand(ackChannelID: 9012, lastMessageID: 4, requestID: "original-request-ack01")
        var applied: [String: Any] = ["request_id": command.requestID, "status": "APPLIED", "operation": "ACK",
            "scope_type": 1, "scope_id": "9012", "result_redacted": false, "must_refresh_state": true,
            "result": ["version": 2]]
        let real = try JSONDecoder().decode(NativeChannelNotificationReceipt.self, from: JSONSerialization.data(withJSONObject: applied))
        XCTAssertNil(real.resumeWithSameRequest)
        try real.validate(for: command)
        applied["resume_with_same_request"] = 1
        XCTAssertThrowsError(try JSONDecoder().decode(NativeChannelNotificationReceipt.self, from: JSONSerialization.data(withJSONObject: applied)))
        var unknown: [String: Any] = ["request_id": command.requestID, "status": "NOT_FOUND", "outcome": "UNKNOWN"]
        let absent = try JSONDecoder().decode(NativeChannelNotificationReceipt.self, from: JSONSerialization.data(withJSONObject: unknown))
        XCTAssertNil(absent.resumeWithSameRequest)
        try absent.validate(for: command)
        unknown["resume_with_same_request"] = true
        let retry = try JSONDecoder().decode(NativeChannelNotificationReceipt.self, from: JSONSerialization.data(withJSONObject: unknown))
        XCTAssertEqual(retry.resumeWithSameRequest, true)
        try retry.validate(for: command)
    }
    func testAckForwardUsesReadAndRejectsMuteOrPreferenceRoutes() async throws {
        let h = try NotificationForwardHarness(); let ack = try h.ackCommand(); try h.journal.persist(ack)
        let adapter = try h.adapter()
        await rejects(adapter, h.post(ack))
        var muteRoute = h.post(ack); muteRoute.url = h.get("api/im/mute").url
        await rejects(adapter, muteRoute)
        let service = NativeChannelNotificationService(authority: adapter.authority, transport: adapter)
        let result = try await service.submit(ack)
        XCTAssertNil(result.resumeWithSameRequest)
        XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.wire.requests[0].url?.path, "/api/im/read")
        XCTAssertEqual(h.wire.requests[0].httpBody, ack.body)
        h.source.denied = [.ack]
        let blocked = try NotificationForwardHarness(); try blocked.journal.persist(try blocked.ackCommand())
        blocked.source.denied = [.ack]
        let blockedAdapter = try blocked.adapter()
        await rejects(blockedAdapter, blocked.postAck(try XCTUnwrap(try blocked.journal.restore())))
        XCTAssertTrue(blocked.wire.requests.isEmpty)
    }
    func testAckRetryRequiresResumeFlagRatherThanMuteNotFoundRule() async throws {
        let h = try NotificationForwardHarness(); let flow = try h.flow(scope: h.scope); await flow.activate()
        h.wire.losePostResponse = true
        await flow.acknowledge(lastMessageID: 4)
        let original = try XCTUnwrap(h.journal.restore())
        XCTAssertEqual(original.operation, .ack)
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        h.wire.losePostResponse = false; h.wire.receiptStatus = "NOT_FOUND"
        await flow.retryOriginal()
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        h.wire.resumeSameRequest = true
        await flow.retryOriginal()
        let posts = h.wire.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 2)
        XCTAssertEqual(posts.last?.url?.path, "/api/im/read")
        XCTAssertEqual(posts.last?.httpBody, original.body)
    }
    func testUnknownOuterFlagCannotAcknowledgeAnAppliedLookingAckWrite() async throws {
        for ack in [false, true] {
            let h = try NotificationForwardHarness(); let flow = try h.flow(scope: h.scope); await flow.activate()
            h.wire.outcomeKnownFalse = true
            if ack { await flow.acknowledge(lastMessageID: 4) } else { await flow.mute(minutes: 480) }
            XCTAssertEqual(flow.state, .outcomeUnknown)
            let original = try XCTUnwrap(h.journal.restore())
            XCTAssertEqual(original.operation, ack ? .ack : .mute)
            XCTAssertEqual(flow.lastFailure?.serverDetails?.outcomeKnown, false)
            XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        }
    }
    func testAckOnlyAppliedResultDoesNotReadSettingsOrCloseAccess() async throws {
        let h = try NotificationForwardHarness(); h.source.denied = [.preference, .directory, .save, .mute]
        let flow = try h.flow(scope: h.scope); await flow.activate()
        XCTAssertFalse(flow.canRead); XCTAssertTrue(flow.canAck)
        await flow.acknowledge(lastMessageID: 4)
        XCTAssertEqual(flow.state, .applied)
        XCTAssertFalse(flow.canRead)
        XCTAssertNil(try h.journal.restore())
        XCTAssertFalse(h.wire.requests.contains { $0.url?.path.contains("notify-pref") == true })
    }
    func testMissingOriginalChangedBodyWrongRouteAndWrongReceiptAreRejected() async throws {
        let h = try NotificationForwardHarness(); let a = try h.adapter(); let original = try h.command()
        await rejects(a, h.post(original)); try h.journal.persist(original)
        var different = h.post(original); different.httpBody?.append(0x20)
        await rejects(a, different)
        var wrongRoute = h.post(original); wrongRoute.url = h.get("api/im/notify-pref").url
        await rejects(a, wrongRoute)
        await rejects(a, h.get("api/im/notification-requests/different-request-0001"))
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertEqual(try h.journal.restore(), original)
    }
    func testNoncanonicalHeaderOriginPathQueryAndMethodNeverForward() async throws {
        let h = try NotificationForwardHarness(); let a = try h.adapter()
        for path in ["api/im/notify-pref?scope_id=9012&scope_type=1", "api/im/notify-pref?scope_type=01&scope_id=9012",
                     "api/im/notify-pref?scope_type=0&scope_id=11", "api/im/notify-pref?scope_type=1&scope_id=09012",
                     "api/im/notify-pref?scope_type=1&scope_id=9012&extra=1", "api/im/unread-summary?extra=1",
                     "api/im/notify-pref#fragment", "api/im/send", "api/im/notification-requests/not-persisted-0001"] {
            await rejects(a, h.get(path))
        }
        for kind in 0..<6 {
            var request = h.get("api/im/notify-pref")
            switch kind {
            case 0: request.setValue("other-token", forHTTPHeaderField: "Authorization")
            case 1: request.setValue("x=y", forHTTPHeaderField: "Cookie")
            case 2: request.httpShouldHandleCookies = true
            case 3: request.url = URL(string: "https://other.example/api/im/notify-pref")
            case 4: request.httpMethod = "DELETE"
            default: request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            await rejects(a, request)
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testHostSourceReplacementImmediatelyRetiresCachedServiceBeforeAnySend() throws {
        let h = try NotificationForwardHarness(); let a = try h.adapter()
        let service = NativeChannelNotificationService(authority: a.authority, transport: a)
        let replacement = NotificationForwardSource(context: h.context)
        replacement.authorizationVersion = h.source.authorizationVersion; replacement.revision = h.source.revision
        h.selected = replacement; XCTAssertFalse(service.isCurrent)
        h.selected = h.source; XCTAssertFalse(service.isCurrent); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testObservedMissingHostAndViewerABACannotReviveAuthority() throws {
        for viewerChange in [false, true] {
            let h = try NotificationForwardHarness(); let a = try h.adapter()
            if viewerChange { h.viewer = 3 } else { h.live = nil }
            XCTAssertFalse(a.authority.isCurrent)
            h.viewer = 2; h.live = h.context
            XCTAssertFalse(a.authority.isCurrent)
        }
    }
    func testFalseFinalFenceAndPostResponseRevocationHideResult() async throws {
        let h = try NotificationForwardHarness(); let a = try h.adapter()
        do { _ = try await a.send(h.get("api/im/notify-pref"), fence: .init { false }); XCTFail("must reject") } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.wire.beforeResponse = { h.source.authorizationVersion = nil }
        await rejects(a, h.get("api/im/notify-pref")); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testLostResponseFreshFlowReadsOriginalReceiptWithoutResending() async throws {
        let h = try NotificationForwardHarness(); let first = try h.flow(scope: h.scope)
        await first.activate(); XCTAssertTrue(first.canMute)
        h.wire.losePostResponse = true; await first.mute(minutes: 480)
        XCTAssertEqual(first.state, .outcomeUnknown)
        let original = try XCTUnwrap(h.journal.restore()); let originalBytes = h.storage.rows
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        first.deactivate(); XCTAssertEqual(h.storage.rows, originalBytes)
        // Recover through the global screen, whose visible scope is nil, not the original channel.
        let fresh = try h.flow(scope: nil); await fresh.activate()
        XCTAssertEqual(fresh.state, .applied)
        XCTAssertNil(fresh.receipt) // Historical receipt is not presented as current settings.
        XCTAssertNil(try h.journal.restore()); XCTAssertNotNil(fresh.directory)
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertTrue(h.wire.requests.contains { $0.url?.path == "/api/im/notification-requests/" + original.requestID })
    }
    func testUnknownReceiptRetainsOriginalBytesWithoutRetry() async throws {
        let h = try NotificationForwardHarness(); let original = try h.command(); try h.journal.persist(original)
        let before = h.storage.rows; h.wire.receiptStatus = "NOT_FOUND"
        let flow = try h.flow(scope: nil); await flow.activate()
        XCTAssertEqual(flow.state, .outcomeUnknown); XCTAssertEqual(try h.journal.restore(), original)
        XCTAssertEqual(h.storage.rows, before); XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testUnauthorizedReadPreservesPendingOriginalAndHidesProjection() async throws {
        let h = try NotificationForwardHarness(); let original = try h.command(); try h.journal.persist(original)
        h.wire.status = 401; let flow = try h.flow(scope: h.scope); await flow.activate()
        XCTAssertEqual(flow.state, .accessClosed); XCTAssertNil(flow.directory); XCTAssertNil(flow.receipt)
        XCTAssertEqual(try h.journal.restore(), original); XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    private func rejects(_ adapter: NativeChannelNotificationFinalForward, _ request: URLRequest) async {
        do { _ = try await adapter.send(request, fence: .init { true }); XCTFail("must reject") } catch {}
    }
}

@MainActor private final class NotificationForwardSource: NativeChannelNotificationAuthorizing {
    var currentContext: RuntimeDependencyContext?; var authorizationVersion: UUID? = UUID()
    var revision = UUID(); var denied: Set<NativeChannelNotificationOperation> = []
    init(context: RuntimeDependencyContext) { currentContext = context }
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(currentContext, context), self.authorizationVersion == authorizationVersion else { return }
        self.authorizationVersion = nil
    }
    func authorizationRevision(for operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> UUID? {
        denied.contains(operation) || authorizationVersion == nil ? nil : revision
    }
}
@MainActor private final class NotificationForwardStorage: NativeChannelNotificationStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows.removeValue(forKey: key) }
}
@MainActor private final class NotificationForwardWire: HTTPTransport {
    var requests: [URLRequest] = []; var beforeResponse: (() -> Void)?
    var losePostResponse = false; var receiptStatus = "APPLIED"; var status = 200
    var resumeSameRequest: Bool? = nil; var outcomeKnownFalse = false
    var journal: NativeChannelNotificationJournal!
    static func row(scope: NativeChannelNotificationScope) -> [String: Any] {
        ["scope_type": scope.type, "scope_id": scope.value, "level": 3, "version": 1, "permanent_muted": false,
         "muted_until": NSNull(), "quiet_start": NSNull(), "quiet_end": NSNull(), "quiet_tz": NSNull(),
         "suppress_broadcast": false, "suppress_team_status": false, "show_preview": NSNull(), "effective_level": 1,
         "effective": ["level": 1, "muted": false, "permanent_muted": false, "quiet": false,
                       "suppress_broadcast": false, "suppress_team_status": false, "show_preview": false]]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?()
        if status != 200 { return (try JSONSerialization.data(withJSONObject: ["code": status]), status) }
        if losePostResponse && request.httpMethod == "POST" { throw URLError(.networkConnectionLost) }
        if outcomeKnownFalse && request.httpMethod == "POST" {
            let command = try XCTUnwrap(journal.restore())
            let applied: [String: Any] = ["request_id": command.requestID, "status": "APPLIED",
                "scope_type": command.scope.type, "scope_id": command.scope.value, "operation": command.operation.rawValue,
                "result_redacted": false, "must_refresh_state": true, "result": ["version": 2]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "outcome_known": false, "data": applied]), 200)
        }
        var data: [String: Any]
        if request.httpMethod == "POST" || request.url!.path.contains("notification-requests") {
            let command = try XCTUnwrap(journal.restore())
            if receiptStatus == "NOT_FOUND" {
                data = ["request_id": command.requestID, "status": receiptStatus, "outcome": "UNKNOWN"]
                if let resumeSameRequest { data["resume_with_same_request"] = resumeSameRequest }
            } else {
                data = ["request_id": command.requestID, "status": receiptStatus, "scope_type": command.scope.type,
                        "scope_id": command.scope.value, "operation": command.operation.rawValue,
                        "result_redacted": false, "must_refresh_state": true, "result": ["version": 2]]
            }
        } else if request.url!.path.hasSuffix("unread-summary") {
            data = ["total": 0, "mention_count": 0, "has_mention": 0, "by_tab": ["dm": 0, "sys": 0, "channel": 0]]
        } else {
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let type = Int(q.first { $0.name == "scope_type" }?.value ?? "1")!
            let value = q.first { $0.name == "scope_id" }?.value ?? "9012"
            let scope = try NativeChannelNotificationScope(type: type, value: value)
            data = ["list": [Self.row(scope: scope)], "defaults": Self.row(scope: try .init(type: 4, value: "11")),
                    "server_time": "2026-10-24T04:00:00.000Z"]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
@MainActor private final class NotificationForwardHarness {
    let context: RuntimeDependencyContext; let scope: NativeChannelNotificationScope
    var live: RuntimeDependencyContext?; var viewer: UInt64 = 2
    let source: NotificationForwardSource; var selected: NotificationForwardSource?
    let storage = NotificationForwardStorage(); let wire = NotificationForwardWire()
    let journal: NativeChannelNotificationJournal
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:forward", token: "fixture-token"))
        live = context; scope = try .init(type: 1, value: "9012")
        source = NotificationForwardSource(context: context); selected = source
        journal = .init(storage: storage, owner: .init(context: context)); wire.journal = journal
    }
    func adapter(journal other: NativeChannelNotificationJournal? = nil) throws -> NativeChannelNotificationFinalForward {
        try .init(context: context, viewerRevision: 2, source: source, journal: other ?? journal, underlying: wire,
                  current: { self.live }, viewer: { self.viewer }, selected: { self.selected })
    }
    func flow(scope: NativeChannelNotificationScope?) throws -> NativeChannelNotificationCoordinator {
        let a = try adapter()
        return try .init(client: NativeChannelNotificationService(authority: a.authority, transport: a), journal: journal, scope: scope)
    }
    func command() throws -> NativeChannelNotificationCommand { try .init(scope: scope, minutes: 480, requestID: "original-request-0001") }
    func ackCommand() throws -> NativeChannelNotificationCommand {
        try .init(ackChannelID: 9012, lastMessageID: 4, requestID: "original-request-ack01")
    }
    func preferenceCommand() throws -> NativeChannelNotificationCommand {
        let row = try JSONDecoder().decode(NativeChannelNotificationPreference.self,
            from: JSONSerialization.data(withJSONObject: NotificationForwardWire.row(scope: scope)))
        return try .init(preference: row, draft: .init(row), requestID: "original-request-0002")
    }
    func get(_ path: String) -> URLRequest {
        var r = URLRequest(url: URL(string: path, relativeTo: context.baseURL.appendingPathComponent("/"))!.absoluteURL)
        r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Accept"); r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); return r
    }
    func post(_ command: NativeChannelNotificationCommand) -> URLRequest {
        var r = get(command.operation == .mute ? "api/im/mute" : "api/im/notify-pref")
        r.httpMethod = "POST"; r.httpBody = command.body; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); return r
    }
    func postAck(_ command: NativeChannelNotificationCommand) -> URLRequest {
        var r = get("api/im/read")
        r.httpMethod = "POST"; r.httpBody = command.body; r.setValue("application/json", forHTTPHeaderField: "Content-Type"); return r
    }
}

// Terminal HTTP status must be observed before cancellation suppresses completion.
extension NativeChannelNotificationFinalForwardTests {
    func testCancelledHTTP401PermanentlyRetiresCapturedAuthority() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter()
        h.wire.status = 401
        h.wire.beforeResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        let work = Task { @MainActor in
            try await adapter.send(h.get("api/im/notify-pref"), fence: .init { true })
        }
        do { _ = try await work.value; XCTFail("received 401 must not succeed") } catch {}
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertFalse(adapter.authority.isCurrent)
        h.wire.status = 200; h.wire.beforeResponse = nil
        await rejects(adapter, h.get("api/im/notify-pref"))
        XCTAssertEqual(h.wire.requests.count, 1) // Restored values cannot revive this captured source.
    }
    func testCancelledHTTP200HidesResultButDoesNotClaimAuthorityRevokedOrSettleOriginal() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter(); let original = try h.command()
        try h.journal.persist(original); let bytes = h.storage.rows
        h.wire.beforeResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        let work = Task { @MainActor in
            try await adapter.send(h.post(original), fence: .init { true })
        }
        do { _ = try await work.value; XCTFail("late successful response must remain hidden") } catch {}
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertTrue(adapter.authority.isCurrent)
        XCTAssertEqual(try h.journal.restore(), original); XCTAssertEqual(h.storage.rows, bytes)
    }
    func testOldIdentityLate401NeverRetiresReplacementAuthorityOrItsSession() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter(); let original = try h.command()
        try h.journal.persist(original); let bytes = h.storage.rows
        let replacementContext = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player",
            session: try .init(accountID: 12, epoch: 2, namespace: "CN:forward", token: "replacement-token"))
        let replacementSource = NotificationForwardSource(context: replacementContext)
        let replacementStorage = NotificationForwardStorage()
        let replacementJournal = NativeChannelNotificationJournal(storage: replacementStorage, owner: .init(context: replacementContext))
        var fresh: NativeChannelNotificationFinalForward?
        h.wire.status = 401
        h.wire.beforeResponse = {
            h.live = replacementContext; h.viewer = 3; h.selected = replacementSource
            do {
                fresh = try NativeChannelNotificationFinalForward(context: replacementContext, viewerRevision: 3,
                    source: replacementSource, journal: replacementJournal, underlying: h.wire,
                    current: { h.live }, viewer: { h.viewer }, selected: { h.selected })
            } catch { XCTFail("valid replacement construction failed: \(error)") }
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let work = Task { @MainActor in
            try await adapter.send(h.get("api/im/notification-requests/" + original.requestID), fence: .init { true })
        }
        do { _ = try await work.value; XCTFail("old unauthorized reply must not succeed") } catch {}
        XCTAssertFalse(adapter.authority.isCurrent)
        XCTAssertTrue(try XCTUnwrap(fresh).authority.isCurrent)
        XCTAssertEqual(h.live, replacementContext); XCTAssertNotNil(replacementSource.authorizationVersion)
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertTrue(replacementStorage.rows.isEmpty)
        XCTAssertEqual(h.storage.rows, bytes); XCTAssertEqual(try h.journal.restore(), original)
    }
    func testCancelledNetworkFailureDoesNotInvent401OrRetireAuthority() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter(); let original = try h.command()
        try h.journal.persist(original); let bytes = h.storage.rows
        h.wire.losePostResponse = true
        h.wire.beforeResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        let work = Task { @MainActor in try await adapter.send(h.post(original), fence: .init { true }) }
        do { _ = try await work.value; XCTFail("network failure must propagate") } catch {}
        XCTAssertTrue(adapter.authority.isCurrent); XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.storage.rows, bytes)
    }
    func testCancellationBeforeForwardDoesNotInventUnauthorizedResponse() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter()
        let work = Task { @MainActor in try await adapter.send(h.get("api/im/notify-pref"), fence: .init { true }) }
        work.cancel()
        do { _ = try await work.value; XCTFail("cancelled task must not forward") } catch {}
        XCTAssertTrue(adapter.authority.isCurrent); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testUncancelled401AlsoRetiresSourceWithoutChangingProtectedOriginal() async throws {
        let h = try NotificationForwardHarness(); let adapter = try h.adapter(); let original = try h.command()
        try h.journal.persist(original); let bytes = h.storage.rows; h.wire.status = 401
        await rejects(adapter, h.get("api/im/notification-requests/" + original.requestID))
        XCTAssertFalse(adapter.authority.isCurrent); XCTAssertEqual(h.storage.rows, bytes)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
}
