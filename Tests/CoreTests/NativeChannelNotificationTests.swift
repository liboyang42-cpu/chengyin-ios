import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Pure presentation regressions: no transport, storage or authorization changes.
extension NativeChannelNotificationTests {
    func testPresentationNeverEchoesUnknownOrMalformedServerErrorCodes() {
        let codes: [String?] = [nil, "", " ", "UNRECOGNIZED_INTERNAL_DETAIL", "line one\nline two",
            String(repeating: "private diagnostic ", count: 1024),
            " PREFERENCE_VERSION_CONFLICT", "PREFERENCE_VERSION_CONFLICT\n"]
        for code in codes {
            let failures: [NativeChannelNotificationError] = [
                .server(httpStatus: 409, code: 409, errorCode: code),
                .serverResponse(.init(httpStatus: 500, code: 500, errorCode: code, outcomeKnown: false))
            ]
            for failure in failures {
                XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.failed(failure)), "notification.error.read")
                XCTAssertNil(NativeChannelNotificationPresentation.failureDetailKey(failure, state: .outcomeUnknown))
                XCTAssertEqual(failure.serverDetails?.errorCode, code)
            }
        }
    }

    func testPresentationShowsKnownConflictOnceWithoutItsTechnicalCode() {
        let failure = NativeChannelNotificationError.server(httpStatus: 409, code: 409,
            errorCode: "PREFERENCE_VERSION_CONFLICT")
        let message = "notification.error.versionConflict"
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.failed(failure)), message)
        XCTAssertNil(NativeChannelNotificationPresentation.failureDetailKey(failure, state: .failed(failure)))
        XCTAssertEqual(NativeChannelNotificationPresentation.failureDetailKey(failure, state: .outcomeUnknown), message)
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.outcomeUnknown), "notification.state.outcomeUnknown")
        XCTAssertEqual(failure.serverDetails?.errorCode, "PREFERENCE_VERSION_CONFLICT")
    }

    func testPresentationDoesNotAttachStaleConflictToOtherOutcomes() {
        let failure = NativeChannelNotificationError.serverResponse(.init(httpStatus: 409, code: 409,
            errorCode: "PREFERENCE_VERSION_CONFLICT"))
        let states: [NativeChannelNotificationState] = [.idle, .loading, .ready, .saving, .checkingReceipt,
            .pending, .applied, .appliedRedacted, .refreshFailed, .persistenceFailed, .accessClosed,
            .failed(.invalidInput), .failed(failure)]
        for state in states {
            XCTAssertNil(NativeChannelNotificationPresentation.failureDetailKey(failure, state: state))
        }
        XCTAssertNil(NativeChannelNotificationPresentation.failureDetailKey(nil, state: .outcomeUnknown))
    }

    func testPresentationPreservesRecoverySuccessAndRedactionMeanings() {
        XCTAssertNil(NativeChannelNotificationPresentation.stateKey(.idle))
        XCTAssertNil(NativeChannelNotificationPresentation.stateKey(.ready))
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.pending), "notification.state.pending")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.applied), "notification.state.applied")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.appliedRedacted), "notification.state.appliedRedacted")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.refreshFailed), "notification.state.refreshFailed")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.persistenceFailed), "notification.state.persistenceFailed")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.accessClosed), "notification.state.accessClosed")
        XCTAssertEqual(NativeChannelNotificationPresentation.stateKey(.failed(.invalidInput)), "notification.error.invalidInput")
    }
}

@MainActor final class NativeChannelNotificationTests: XCTestCase {
    func testDecimalIdentityPreservesLongAndRejectsOtherRepresentations() throws {
        XCTAssertEqual(try NativeChannelNotificationScope(type: 1, value: "9223372036854775807").value, "9223372036854775807")
        for id in ["0", "01", "1e3", "1.0", "-1", "9223372036854775808"] {
            XCTAssertThrowsError(try NativeChannelNotificationScope(type: 1, value: id))
        }
        XCTAssertThrowsError(try NativeChannelNotificationScope(type: 0, value: "1"))
    }
    func testEffectiveIsIndependentFromExplicitAndUnknownPermanentFlagIsRejected() throws {
        let pref = try NotificationFixture.preference()
        XCTAssertEqual(pref.level, .inherit); XCTAssertEqual(pref.effective.level, .mentions)
        var row = NotificationFixture.row(); row.removeValue(forKey: "permanent_muted")
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationPreference.self, row))
        row = NotificationFixture.row(); row["permanent_muted"] = 1
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationPreference.self, row))
        row = NotificationFixture.row(); row["effective_level"] = 0
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationPreference.self, row))
    }
    func testQuietHoursCrossMidnightAndRejectPartialEqualOrUnknownZone() throws {
        _ = try NativeChannelNotificationQuietHours(start: "23:00", end: "07:00", timeZone: "Asia/Shanghai")
        for (start, end, zone) in [("7:00", "08:00", "UTC"), ("24:00", "08:00", "UTC"), ("07:00", "07:00", "UTC"), ("07:00", "08:00", "not-a-zone")] {
            XCTAssertThrowsError(try NativeChannelNotificationQuietHours(start: start, end: end, timeZone: zone))
        }
        var row = NotificationFixture.row(); row["quiet_start"] = "23:00"
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationPreference.self, row))
    }
    func testSaveEncodesNullReplacementAndNeverWritesPermanentFlag() throws {
        let pref = try NotificationFixture.preference()
        let command = try NativeChannelNotificationCommand(preference: pref, draft: .init(pref))
        try command.validate()
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: command.body) as? [String: Any])
        XCTAssertTrue(body["quiet_start"] is NSNull); XCTAssertTrue(body["muted_until"] is NSNull)
        XCTAssertTrue(body["show_preview"] is NSNull); XCTAssertNil(body["permanent_muted"])
        XCTAssertEqual(body["version"] as? Int, 1)
    }
    func testMuteKeepsExactOriginalBodyAcrossRestoreAndDoesNotEncodeLevel() throws {
        let harness = try NotificationHarness()
        let command = try NativeChannelNotificationCommand(scope: harness.scope, minutes: 60)
        try harness.journal.persist(command)
        let restored = try XCTUnwrap(harness.journal.restore())
        XCTAssertEqual(restored.body, command.body); XCTAssertEqual(restored.requestID, command.requestID)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: command.body) as? [String: Any])
        XCTAssertNil(body["level"]); XCTAssertNil(body["muted_until"])
        for minutes in [-1, 0, 1, 480, 43200] { try NativeChannelNotificationCommand(scope: harness.scope, minutes: minutes).validate() }
        XCTAssertThrowsError(try NativeChannelNotificationCommand(scope: harness.scope, minutes: 43201))
    }
    func testJournalSeparatesAccountNamespaceOriginAndSerializesAllScopes() throws {
        let h = try NotificationHarness(); let command = try NativeChannelNotificationCommand(scope: h.scope, minutes: -1)
        try h.journal.persist(command)
        let other = try NotificationFixture.context(account: 12)
        XCTAssertNil(try NativeChannelNotificationJournal(storage: h.storage, owner: .init(context: other)).restore())
        let namespace = try NotificationFixture.context(namespace: "CN:other")
        XCTAssertNil(try NativeChannelNotificationJournal(storage: h.storage, owner: .init(context: namespace)).restore())
        let origin = try NotificationFixture.context(origin: "https://example.org")
        XCTAssertNil(try NativeChannelNotificationJournal(storage: h.storage, owner: .init(context: origin)).restore())
        XCTAssertThrowsError(try h.journal.persist(.init(scope: h.scope, minutes: 0)))
        let lease = try XCTUnwrap(h.journal.acquire()); XCTAssertNil(h.journal.acquire()); h.journal.release(lease)
    }
    func testPersistenceFailurePreventsNetworkWrite() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.storage.failWrite = true
        await flow.save(.init(try XCTUnwrap(flow.preference)), expectedVersion: 1)
        XCTAssertEqual(flow.state, .persistenceFailed); XCTAssertEqual(h.posts.count, 0)
    }
    func testLostResponseQueriesOriginalReceiptAndReadsCurrentRatherThanHistoricalState() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.loseWriteResponse = true
        await flow.save(.init(try XCTUnwrap(flow.preference)), expectedVersion: 1)
        XCTAssertEqual(flow.state, .outcomeUnknown)
        let command = try XCTUnwrap(h.journal.restore()); XCTAssertEqual(h.posts.count, 1)
        h.receiptStatus = "APPLIED"; h.currentVersion = 9
        await flow.checkReceipt()
        XCTAssertNil(try h.journal.restore()); XCTAssertEqual(h.posts.count, 1)
        XCTAssertEqual(h.requestedReceiptKeys.last, command.requestID)
        XCTAssertEqual(flow.preference?.version, 9) // Historical receipt is version 2.
    }
    func testNotFoundIsUnknownAndExplicitRetryFirstReadsThenUsesSameBody() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.loseWriteResponse = true
        await flow.mute(minutes: 60)
        let original = try XCTUnwrap(h.journal.restore()); let firstBody = try XCTUnwrap(h.posts.first)
        await flow.checkReceipt()
        XCTAssertEqual(flow.state, .outcomeUnknown); XCTAssertEqual(h.posts.count, 1)
        await flow.retryOriginal()
        XCTAssertEqual(h.posts.count, 2); XCTAssertEqual(h.posts.last, firstBody)
        XCTAssertEqual(try h.journal.restore(), original); XCTAssertEqual(h.requestedReceiptKeys.last, original.requestID)
    }
    func testPendingNeverResubmits() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.loseWriteResponse = true
        await flow.mute(minutes: -1); h.receiptStatus = "PENDING"
        await flow.retryOriginal()
        XCTAssertEqual(flow.state, .pending); XCTAssertEqual(h.posts.count, 1); XCTAssertNotNil(try h.journal.restore())
    }
    func testRedactedAppliedReceiptClearsSensitiveProjection() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.loseWriteResponse = true
        await flow.mute(minutes: 0); h.receiptStatus = "APPLIED"; h.redacted = true
        await flow.checkReceipt()
        XCTAssertEqual(flow.state, .appliedRedacted); XCTAssertNil(flow.directory); XCTAssertNil(flow.unread)
        XCTAssertNil(try h.journal.restore())
    }
    func testRevocationAndEpochReplacementHideCacheAndBlockFinalForward() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        XCTAssertNotNil(flow.preference)
        h.authorizer.authorizationVersion = nil
        XCTAssertNil(flow.preference); XCTAssertFalse(flow.canSave)
        let next = try NotificationHarness()
        next.beforeForward = { next.authorizer.currentContext = try NotificationFixture.context(epoch: 2) }
        do { _ = try await next.service.preferences(scope: next.scope); XCTFail("Stale request must not forward") } catch { }
        XCTAssertEqual(next.forwarded, 0)
    }
    func testBusinessFailureInHTTP200IsNotSuccessAndPreservesErrorCode() async throws {
        let h = try NotificationHarness(); h.forcedEnvelope = ["code": 409, "errorCode": "PREFERENCE_STATE_INVALID"]
        do { _ = try await h.service.preferences(scope: h.scope); XCTFail("Business failure") }
        catch { XCTAssertEqual(error as? NativeChannelNotificationError, .server(httpStatus: 200, code: 409, errorCode: "PREFERENCE_STATE_INVALID")) }
    }
    func testWrongReceiptKeyScopeOrOperationDoesNotSettle() throws {
        let command = try NativeChannelNotificationCommand(scope: .init(type: 1, value: "9012"), minutes: 0)
        for field in ["request_id", "scope_id", "operation"] {
            var object = NotificationFixture.receipt(command, status: "APPLIED", redacted: false)
            object[field] = field == "request_id" ? "different-request-00001" : (field == "scope_id" ? "9" : "PREFERENCE")
            let receipt = try NotificationFixture.decode(NativeChannelNotificationReceipt.self, object)
            XCTAssertThrowsError(try receipt.validate(for: command))
        }
    }
    func testSettlingStorageFailureRetainsOriginalAndBlocksNewWrites() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.storage.failRemove = true
        await flow.mute(minutes: -1)
        XCTAssertEqual(flow.state, .persistenceFailed); XCTAssertNotNil(try h.journal.restore())
        XCTAssertFalse(flow.canSave); XCTAssertFalse(flow.canMute); XCTAssertEqual(h.posts.count, 1)
    }
    func testEndpointApprovalReplacementHidesPreviouslyReadPreferences() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        XCTAssertNotNil(flow.preference); h.authorizer.revision = UUID()
        XCTAssertNil(flow.preference); XCTAssertFalse(flow.canSave)
    }
    func testOldEditorVersionCannotOverwriteNewerRead() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        let old = try XCTUnwrap(flow.preference); h.currentVersion = 4; await flow.refresh()
        await flow.save(.init(old), expectedVersion: old.version)
        XCTAssertEqual(h.posts.count, 0); XCTAssertNil(try h.journal.restore())
        XCTAssertEqual(flow.preference?.version, 4)
    }
    func testMVCUnknownRecoverySurvivesRestartWithOriginalReturnPathAndKey() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.writeFailureStatus = 500; h.includeReturnPath = true
        await flow.mute(minutes: 480)
        let original = try XCTUnwrap(h.journal.restore())
        let context = try XCTUnwrap(h.journal.failureContext(for: original))
        XCTAssertEqual(context.outcomeKnown, false)
        XCTAssertEqual(context.recovery?.lookupPath, "/api/im/notification-requests/" + original.requestID)
        XCTAssertEqual(context.returnPath, "/subpackageB/pages/im/list/index")
        XCTAssertEqual(context.recovery?.returnPath, context.returnPath)
        XCTAssertEqual(flow.recoveryReturnPath, context.returnPath)
        XCTAssertEqual(flow.state, .accessClosed); XCTAssertNil(flow.directory)
        flow.deactivate()
        let restored = try h.flow(); await restored.activate()
        XCTAssertEqual(restored.state, .outcomeUnknown); XCTAssertEqual(h.posts.count, 1)
        XCTAssertEqual(restored.recoveryReturnPath, context.returnPath)
        XCTAssertEqual(h.requestedReceiptKeys.last, original.requestID)
        XCTAssertEqual(try h.journal.restore()?.body, original.body)
    }
    func testMVCMissingBeanOrUnmappedNewRequestNeverBecomesLegacySuccess() async throws {
        for (status, code) in [(503, "CHANNEL_PLATFORM_UNAVAILABLE"), (409, "MUTE_DURATION_UNAVAILABLE"), (409, "MUTE_REQUEST_SCOPE_UNAVAILABLE")] {
            let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
            h.writeFailureStatus = status; h.writeFailureCode = code
            await flow.mute(minutes: -1)
            let command = try XCTUnwrap(h.journal.restore())
            XCTAssertEqual(flow.state, .outcomeUnknown)
            XCTAssertEqual(flow.lastFailure?.serverDetails?.errorCode, code)
            XCTAssertEqual(h.posts.count, 1)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: command.body) as? [String: Any])
            XCTAssertEqual(body["minutes"] as? Int, -1); XCTAssertNil(body["muted"])
            await flow.checkReceipt()
            XCTAssertEqual(flow.state, .outcomeUnknown); XCTAssertEqual(h.posts.count, 1)
            XCTAssertEqual(try h.journal.restore(), command)
        }
    }
    func testMVCRecoveryRejectsOtherKeyScopeExternalLookupOrReturnPathBeforeRead() async throws {
        let h = try NotificationHarness(); let command = try NativeChannelNotificationCommand(scope: h.scope, minutes: 0)
        for (field, value) in [("request_id", "another-request-00001"), ("conversation_id", "9013"),
            ("lookup_path", "https://example.org/steal"), ("lookup_path", "/api/im/notification-requests/another-request-00001"),
            ("returnPath", "//example.org/steal")] {
            var object: [String: Any] = ["request_id": command.requestID, "conversation_id": command.scope.value,
                "lookup_path": "/api/im/notification-requests/" + command.requestID]
            object[field] = value
            let recovery = try NotificationFixture.decode(NativeChannelNotificationRecovery.self, object)
            do { _ = try await h.service.receipt(command, recovery: recovery); XCTFail("Unbound recovery must not forward") } catch { }
        }
        XCTAssertEqual(h.forwarded, 0)
    }
    func testLegacyEmptySuccessCannotSettleNewMuteIntent() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.emptyWriteSuccess = true
        await flow.mute(minutes: 0)
        XCTAssertEqual(flow.state, .outcomeUnknown); XCTAssertNotNil(try h.journal.restore()); XCTAssertEqual(h.posts.count, 1)
    }
    func testUnknownOuterFlagCannotAcknowledgeAnAppliedLookingWritePayload() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate(); h.falseKnownSuccess = true
        await flow.mute(minutes: 480)
        XCTAssertEqual(flow.state, .outcomeUnknown); XCTAssertNotNil(try h.journal.restore())
        XCTAssertEqual(flow.lastFailure?.serverDetails?.outcomeKnown, false)
    }
    func testRecoveryMetadataWriteFailureDoesNotLoseOriginalCommand() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.storage.failAfterWrites = 1; h.writeFailureStatus = 503
        await flow.mute(minutes: -1)
        XCTAssertEqual(flow.state, .persistenceFailed); XCTAssertNotNil(try h.journal.restore()); XCTAssertEqual(h.posts.count, 1)
    }
}

private enum NotificationFixture {
    static func context(account: Int = 11, epoch: UInt64 = 1, namespace: String = "CN:notification-fixture", origin: String = "https://example.com") throws -> RuntimeDependencyContext {
        let session = try PlayExperienceSession(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-token")
        return .init(market: .china, baseURL: URL(string: origin)!, role: "player", session: session)
    }
    static func row(version: Int64 = 1) -> [String: Any] {
        ["scope_type": 1, "scope_id": "9012", "level": 3, "version": version, "permanent_muted": false,
         "muted_until": NSNull(), "quiet_start": NSNull(), "quiet_end": NSNull(), "quiet_tz": NSNull(),
         "suppress_broadcast": false, "suppress_team_status": false, "show_preview": NSNull(), "effective_level": 1,
         "effective": ["level": 1, "muted": false, "permanent_muted": false, "quiet": false,
                       "suppress_broadcast": false, "suppress_team_status": false, "show_preview": false]]
    }
    static func preference() throws -> NativeChannelNotificationPreference { try decode(NativeChannelNotificationPreference.self, row()) }
    static func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    static func receipt(_ command: NativeChannelNotificationCommand, status: String, redacted: Bool) -> [String: Any] {
        if status == "NOT_FOUND" { return ["request_id": command.requestID, "status": status, "outcome": "UNKNOWN", "resume_with_same_request": true] }
        var object: [String: Any] = ["request_id": command.requestID, "status": status,
            "scope_type": command.scope.type, "scope_id": command.scope.value, "operation": command.operation.rawValue,
            "must_refresh_state": true, "result_redacted": redacted]
        if status == "PENDING" { object["outcome"] = "UNKNOWN" }
        else if !redacted { object["result"] = ["version": 2] }
        return object
    }
}
@MainActor private final class NotificationFixtureStorage: NativeChannelNotificationStorage {
    var rows: [String: Data] = [:]; var failWrite = false; var failRemove = false; var writes = 0; var failAfterWrites: Int?
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws {
        if failWrite || failAfterWrites.map({ writes >= $0 }) == true { throw NativeChannelNotificationError.persistenceFailed }
        writes += 1; rows[key] = data
    }
    func remove(_ key: String) throws { if failRemove { throw NativeChannelNotificationError.persistenceFailed }; rows.removeValue(forKey: key) }
}
@MainActor private final class NotificationFixtureAuthorizer: NativeChannelNotificationAuthorizing {
    var currentContext: RuntimeDependencyContext?
    var authorizationVersion: UUID? = UUID()
    var revision = UUID()
    var unavailableOperations: Set<NativeChannelNotificationOperation> = []
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(currentContext, context), self.authorizationVersion == authorizationVersion else { return }
        self.authorizationVersion = nil
    }
    func authorizationRevision(for operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> UUID? {
        authorizationVersion == nil || unavailableOperations.contains(operation) ? nil : revision
    }
}
@MainActor private final class NotificationFixtureDispatcher: NativeChannelNotificationDispatching {
    var handler: (@MainActor (URLRequest, NativeChannelNotificationDispatchFence) async throws -> (Data, Int))!
    func send(_ request: URLRequest, fence: NativeChannelNotificationDispatchFence) async throws -> (Data, Int) { try await handler(request, fence) }
}
@MainActor private final class NotificationHarness {
    let context: RuntimeDependencyContext
    let scope: NativeChannelNotificationScope
    let storage: NotificationFixtureStorage
    let authorizer: NotificationFixtureAuthorizer
    let dispatcher: NotificationFixtureDispatcher
    let journal: NativeChannelNotificationJournal
    let service: NativeChannelNotificationService
    var posts: [Data] = []; var requestedReceiptKeys: [String] = []; var forwarded = 0
    var loseWriteResponse = false; var receiptStatus = "NOT_FOUND"; var redacted = false; var currentVersion: Int64 = 1
    var beforeForward: (@MainActor () throws -> Void)?
    var forcedEnvelope: [String: Any]?
    var writeFailureStatus: Int?; var writeFailureCode = "OUTCOME_UNKNOWN"; var includeReturnPath = false
    var emptyWriteSuccess = false; var falseKnownSuccess = false
    init() throws {
        let context = try NotificationFixture.context()
        let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
        let storage = NotificationFixtureStorage()
        let authorizer = NotificationFixtureAuthorizer()
        let dispatcher = NotificationFixtureDispatcher()
        authorizer.currentContext = context
        let journal = NativeChannelNotificationJournal(storage: storage, owner: .init(context: context))
        let service = NativeChannelNotificationService(authority: try .init(context: context, source: authorizer), transport: dispatcher)
        self.context = context; self.scope = scope; self.storage = storage; self.authorizer = authorizer
        self.dispatcher = dispatcher; self.journal = journal; self.service = service
        dispatcher.handler = { [unowned self] request, fence in
            try beforeForward?()
            guard fence.isCurrent else { throw NativeChannelNotificationError.accessClosed }
            forwarded += 1
            let payload: [String: Any]
            if let forcedEnvelope { return (try JSONSerialization.data(withJSONObject: forcedEnvelope), 200) }
            if request.httpMethod == "POST" {
                posts.append(request.httpBody!)
                if loseWriteResponse { throw URLError(.networkConnectionLost) }
                let original = try XCTUnwrap(journal.restore())
                if let status = writeFailureStatus {
                    var recovery: [String: Any] = ["request_id": original.requestID, "conversation_id": original.scope.value,
                        "lookup_path": "/api/im/notification-requests/" + original.requestID,
                        "use_original_request": true, "query_before_retry": true]
                    var result: [String: Any] = ["code": status, "errorCode": writeFailureCode, "request_id": original.requestID]
                    if status == 500 { result["outcome_known"] = false }
                    if includeReturnPath { result["returnPath"] = "/subpackageB/pages/im/list/index"; recovery["returnPath"] = "/subpackageB/pages/im/list/index" }
                    result["recovery"] = recovery
                    return (try JSONSerialization.data(withJSONObject: result), status)
                }
                if emptyWriteSuccess { return (try JSONSerialization.data(withJSONObject: ["code": 200]), 200) }
                if falseKnownSuccess {
                    return (try JSONSerialization.data(withJSONObject: ["code": 200, "outcome_known": false,
                        "data": NotificationFixture.receipt(original, status: "APPLIED", redacted: false)]), 200)
                }
                payload = NotificationFixture.receipt(try XCTUnwrap(journal.restore()), status: "APPLIED", redacted: false)
            } else if request.url!.path.contains("notification-requests") {
                requestedReceiptKeys.append(request.url!.lastPathComponent)
                payload = NotificationFixture.receipt(try XCTUnwrap(journal.restore()), status: receiptStatus, redacted: redacted)
            } else if request.url!.lastPathComponent == "unread-summary" {
                payload = ["total": 0, "mention_count": 0, "has_mention": 0, "by_tab": ["dm": 0, "sys": 0, "channel": 0]]
            } else {
                payload = ["list": [NotificationFixture.row(version: currentVersion)], "defaults": ["level": 3, "effective_level": 1], "server_time": "2026-10-23T12:30:00.000000Z"]
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload]), 200)
        }
    }
    func flow() throws -> NativeChannelNotificationCoordinator { try .init(client: service, journal: journal, scope: scope) }
}

// Local receiver regression: source-only until the real Swift toolchain executes it.
extension NativeChannelNotificationTests {
    func testLegacyV1MissingOrNullFailurePreservesOriginalBytesAndRequest() throws {
        for explicitNull in [false, true] {
            let h = try NotificationHarness()
            let command = try NativeChannelNotificationCommand(scope: h.scope, minutes: 480)
            try h.journal.persist(command)
            let key = try XCTUnwrap(h.storage.rows.keys.first)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.storage.rows[key])) as? [String: Any])
            XCTAssertNil(raw["failure"])
            if explicitNull { raw["failure"] = NSNull() }
            let original = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            h.storage.rows[key] = original
            let writes = h.storage.writes
            let cold = NativeChannelNotificationJournal(storage: h.storage, owner: h.journal.owner)
            let restored = try XCTUnwrap(cold.restore())
            XCTAssertEqual(restored.requestID, command.requestID)
            XCTAssertEqual(restored.body, command.body)
            try cold.persist(command)
            XCTAssertEqual(h.storage.rows[key], original)
            XCTAssertEqual(h.storage.writes, writes)
            let failure = NativeChannelNotificationServerFailure(httpStatus: 503, code: 503,
                errorCode: "DEPENDENCY_UNAVAILABLE", outcomeKnown: false, requestID: command.requestID)
            try cold.rememberFailure(failure, for: command)
            XCTAssertEqual(try cold.failureContext(for: command), failure)
            XCTAssertEqual(try cold.restore()?.body, command.body)
            XCTAssertEqual(try cold.restore()?.requestID, command.requestID)
            try cold.settle(command)
            XCTAssertNil(h.storage.rows[key])
        }
    }
    func testUnrecognizedOriginalRecordIdentityCannotBeErasedByFailureOrSettlement() throws {
        for location in ["root", "owner", "command", "scope", "failure"] {
            let h = try NotificationHarness()
            let command = try NativeChannelNotificationCommand(scope: h.scope, minutes: -1)
            try h.journal.persist(command)
            let failure = NativeChannelNotificationServerFailure(httpStatus: 503, code: 503,
                errorCode: "DEPENDENCY_UNAVAILABLE", outcomeKnown: false, requestID: command.requestID)
            try h.journal.rememberFailure(failure, for: command)
            let key = try XCTUnwrap(h.storage.rows.keys.first)
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.storage.rows[key])) as? [String: Any])
            if location == "root" { raw["futureOriginalIdentity"] = "must retain" }
            else if location == "scope" {
                var value = try XCTUnwrap(raw["command"] as? [String: Any])
                var scope = try XCTUnwrap(value["scope"] as? [String: Any])
                scope["futureOriginalIdentity"] = "must retain"
                value["scope"] = scope; raw["command"] = value
            } else {
                var value = try XCTUnwrap(raw[location] as? [String: Any])
                value["futureOriginalIdentity"] = "must retain"; raw[location] = value
            }
            let original = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
            h.storage.rows[key] = original
            let writes = h.storage.writes
            XCTAssertThrowsError(try h.journal.restore())
            XCTAssertThrowsError(try h.journal.persist(command))
            XCTAssertThrowsError(try h.journal.rememberFailure(failure, for: command))
            XCTAssertThrowsError(try h.journal.settle(command))
            XCTAssertEqual(h.storage.rows[key], original)
            XCTAssertEqual(h.storage.writes, writes)
        }
    }
}

// Final lane7 ACCOUNT4 contract regression. XCTest execution remains NOT_RUN.
extension NativeChannelNotificationTests {
    private func accountRow(_ accountID: String = "11", version: Int64 = 0) -> [String: Any] {
        var row = NotificationFixture.row(version: version)
        row["scope_type"] = 4; row["scope_id"] = accountID
        return row
    }
    private func accountDirectory(_ accountID: String = "11", version: Int64 = 0) -> [String: Any] {
        let row = accountRow(accountID, version: version)
        return ["list": [row], "defaults": row, "server_time": "2026-10-23T18:00:00Z"]
    }
    func testAccount4IsExactAndReservedScope3StillRejects() throws {
        let scope = try NativeChannelNotificationScope(type: 4, value: "11")
        XCTAssertTrue(scope.isAccountDefault); XCTAssertTrue(scope.belongsToAccount("11"))
        XCTAssertFalse(scope.belongsToAccount("12"))
        for type in [0, 3, 5] { XCTAssertThrowsError(try NativeChannelNotificationScope(type: type, value: "11")) }
        XCTAssertThrowsError(try NativeChannelNotificationScope(type: 4, value: "0"))
        XCTAssertThrowsError(try NativeChannelNotificationCommand(scope: scope, minutes: 0))
    }
    func testCompleteAccountDefaultDecodesAndBindsEveryAccountRow() throws {
        let directory = try NotificationFixture.decode(NativeChannelNotificationDirectory.self, accountDirectory())
        try directory.validate(accountID: "11")
        XCTAssertEqual(directory.defaults.preference?.scope.type, 4)
        XCTAssertEqual(directory.defaults.preference?.version, 0)
        XCTAssertThrowsError(try directory.validate(accountID: "12"))
        XCTAssertThrowsError(try directory.validate())
        var mixed = accountDirectory(); mixed["list"] = [accountRow("12")]
        let wrong = try NotificationFixture.decode(NativeChannelNotificationDirectory.self, mixed)
        XCTAssertThrowsError(try wrong.validate(accountID: "11"))
    }
    func testLegacyDefaultStaysReadOnlyWithoutInventingScopeOrVersion() throws {
        let old: [String: Any] = ["list": [NotificationFixture.row()],
            "defaults": ["level": 3, "effective_level": 1], "server_time": "2026-10-23T18:00:00Z"]
        let directory = try NotificationFixture.decode(NativeChannelNotificationDirectory.self, old)
        try directory.validate(accountID: "11")
        XCTAssertNil(directory.defaults.preference)
        var partial = old
        partial["defaults"] = ["level": 3, "effective_level": 1, "scope_type": 4, "scope_id": "11"]
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationDirectory.self, partial))
        partial["defaults"] = NotificationFixture.row()
        XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationDirectory.self, partial))
    }
    func testAccountSaveUsesOriginalFullBodyCASAndProtectedJournal() throws {
        let h = try NotificationHarness()
        let row = try NotificationFixture.decode(NativeChannelNotificationPreference.self, accountRow(version: 7))
        var draft = NativeChannelNotificationDraft(row)
        draft.level = .mentions; draft.showPreview = false
        draft.quietHours = try .init(start: "23:00", end: "07:00", timeZone: "Asia/Shanghai")
        let command = try NativeChannelNotificationCommand(preference: row, draft: draft, requestID: "account-original-0001")
        try command.validate(); try h.journal.persist(command)
        let originalBytes = try XCTUnwrap(h.storage.rows.values.first)
        let cold = NativeChannelNotificationJournal(storage: h.storage, owner: h.journal.owner)
        let restored = try XCTUnwrap(cold.restore())
        XCTAssertEqual(restored.requestID, command.requestID); XCTAssertEqual(restored.body, command.body)
        XCTAssertEqual(h.storage.rows.values.first, originalBytes)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: restored.body) as? [String: Any])
        XCTAssertEqual(body["scope_type"] as? Int, 4); XCTAssertEqual(body["scope_id"] as? String, "11")
        XCTAssertEqual(body["version"] as? Int, 7); XCTAssertTrue(body["muted_until"] is NSNull)
        XCTAssertEqual(body["suppress_broadcast"] as? Bool, false); XCTAssertEqual(body["suppress_team_status"] as? Bool, false)
        XCTAssertNil(body["permanent_muted"])
    }
    func testAccountRejectsConversationOnlyFieldsWithoutNormalizingThemAway() throws {
        let row = try NotificationFixture.decode(NativeChannelNotificationPreference.self, accountRow())
        for field in ["suppress_broadcast", "suppress_team_status", "muted_until"] {
            var draft = NativeChannelNotificationDraft(row)
            if field == "suppress_broadcast" { draft.suppressBroadcast = true }
            if field == "suppress_team_status" { draft.suppressTeamStatus = true }
            if field == "muted_until" { draft.mutedUntil = "2026-10-23T18:00:00Z" }
            XCTAssertThrowsError(try NativeChannelNotificationCommand(preference: row, draft: draft))
            var raw = accountRow()
            raw[field] = field == "muted_until" ? "2026-10-23T18:00:00Z" as Any : true
            XCTAssertThrowsError(try NotificationFixture.decode(NativeChannelNotificationPreference.self, raw))
        }
    }
    func testAccountScopeOwnershipDoesNotCreateAnEndpointGrant() async throws {
        let h = try NotificationHarness()
        let mine = try NativeChannelNotificationScope(type: 4, value: "11")
        let foreign = try NativeChannelNotificationScope(type: 4, value: "12")
        XCTAssertFalse(h.service.allows(.preference, scope: foreign))
        XCTAssertFalse(h.service.allows(.mute, scope: mine))
        do { _ = try await h.service.preferences(scope: foreign); XCTFail("Foreign account must not forward") } catch { }
        XCTAssertEqual(h.forwarded, 0)
        h.authorizer.authorizationVersion = nil
        XCTAssertFalse(h.service.allows(.preference, scope: mine))
        do { _ = try await h.service.preferences(scope: mine); XCTFail("Account identity is not a grant") } catch { }
        XCTAssertEqual(h.forwarded, 0)
        XCTAssertThrowsError(try NativeChannelNotificationCoordinator(client: h.service, journal: h.journal, scope: foreign))
    }
    func testAccountDirectoryReadExposesRealDefaultButNotForeignAccount() async throws {
        let h = try NotificationHarness()
        h.forcedEnvelope = ["code": 200, "data": accountDirectory()]
        let directory = try await h.service.preferences(scope: nil)
        XCTAssertEqual(directory.defaults.preference?.scope.value, "11")
        let flow = try NativeChannelNotificationCoordinator(client: h.service, journal: h.journal, scope: nil)
        await flow.activate()
        XCTAssertEqual(flow.accountDefaultScope?.value, "11")
        h.forcedEnvelope = ["code": 200, "data": accountDirectory("12")]
        await flow.refresh()
        XCTAssertNil(flow.directory); XCTAssertNil(flow.accountDefaultScope)
        XCTAssertEqual(flow.lastFailure, .malformedResponse)
    }
    func testAccountOriginalUnknownWriteColdRecoveryReadsSameReceiptThenCurrentVersion() async throws {
        let h = try NotificationHarness()
        let scope = try NativeChannelNotificationScope(type: 4, value: "11")
        var posts: [Data] = []; var keys: [String] = []; var applied = false
        h.dispatcher.handler = { [self] request, fence in
            guard fence.isCurrent else { throw NativeChannelNotificationError.accessClosed }
            if request.httpMethod == "POST" {
                posts.append(try XCTUnwrap(request.httpBody))
                throw URLError(.networkConnectionLost)
            }
            let payload: [String: Any]
            if request.url?.path.contains("notification-requests") == true {
                keys.append(request.url!.lastPathComponent)
                payload = NotificationFixture.receipt(try XCTUnwrap(h.journal.restore()), status: applied ? "APPLIED" : "NOT_FOUND", redacted: false)
            } else if request.url?.lastPathComponent == "unread-summary" {
                payload = ["total": 0, "mention_count": 0, "has_mention": 0, "by_tab": ["dm": 0, "sys": 0, "channel": 0]]
            } else { payload = accountDirectory(version: applied ? 9 : 0) }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload]), 200)
        }
        let flow = try NativeChannelNotificationCoordinator(client: h.service, journal: h.journal, scope: scope)
        await flow.activate(); XCTAssertTrue(flow.canSave); XCTAssertFalse(flow.canMute)
        await flow.save(.init(try XCTUnwrap(flow.preference)), expectedVersion: 0)
        XCTAssertEqual(flow.state, .outcomeUnknown)
        let original = try XCTUnwrap(h.journal.restore()); XCTAssertEqual(posts.count, 1)
        flow.deactivate()
        let cold = try NativeChannelNotificationCoordinator(client: h.service, journal: h.journal, scope: scope)
        await cold.activate()
        XCTAssertEqual(cold.state, .outcomeUnknown); XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(keys.last, original.requestID); XCTAssertEqual(try h.journal.restore()?.body, original.body)
        applied = true; await cold.checkReceipt()
        XCTAssertNil(try h.journal.restore()); XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(cold.preference?.version, 9); XCTAssertEqual(cold.state, .applied)
    }
    func testAccountPermissionReplacementStillBlocksTheFinalForward() async throws {
        let h = try NotificationHarness()
        let scope = try NativeChannelNotificationScope(type: 4, value: "11")
        h.beforeForward = { h.authorizer.authorizationVersion = nil }
        do { _ = try await h.service.preferences(scope: scope); XCTFail("Revoked grant must not forward") } catch { }
        XCTAssertEqual(h.forwarded, 0)
    }
}

// Post-install receiver regressions. Swift/XCTest execution is still required.
extension NativeChannelNotificationTests {
    func testObservedMissingAuthorizationCannotRestoreRetainedCache() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        XCTAssertNotNil(flow.preference); let original = h.authorizer.authorizationVersion
        let forwarded = h.forwarded
        h.authorizer.authorizationVersion = nil
        XCTAssertNil(flow.preference); XCTAssertFalse(flow.isCurrent)
        h.authorizer.authorizationVersion = original
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.preference); XCTAssertNil(flow.unread)
        XCTAssertFalse(flow.canSave); await flow.refresh(); XCTAssertEqual(h.forwarded, forwarded)
    }
    func testObservedMissingRuntimeContextCannotRestoreRetainedCache() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        XCTAssertNotNil(flow.preference); h.authorizer.currentContext = nil
        XCTAssertNil(flow.preference); h.authorizer.currentContext = h.context
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.preference); XCTAssertNil(flow.unread)
    }
    func testObservedReplacementAuthorizationCannotRestoreOldAuthority() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        let original = h.authorizer.authorizationVersion
        h.authorizer.authorizationVersion = UUID(); XCTAssertFalse(flow.isCurrent)
        h.authorizer.authorizationVersion = original
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.preference)
    }
    func testObservedMissingCapturedOperationCannotRestoreCache() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        XCTAssertNotNil(flow.preference)
        h.authorizer.unavailableOperations.insert(.preference)
        XCTAssertNil(flow.preference)
        h.authorizer.unavailableOperations.remove(.preference)
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.preference)
    }
    func testObservedReplacementOperationCannotRestoreCache() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        let original = h.authorizer.revision
        h.authorizer.revision = UUID(); XCTAssertNil(flow.preference)
        h.authorizer.revision = original
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.preference)
    }
    func testAbsentUncapturedOperationDoesNotRetireExistingRead() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.authorizer.unavailableOperations.insert(.save)
        XCTAssertFalse(h.service.allows(.save, scope: h.scope))
        XCTAssertTrue(flow.isCurrent); XCTAssertNotNil(flow.preference)
        h.authorizer.unavailableOperations.remove(.save)
        XCTAssertTrue(h.service.allows(.save, scope: h.scope)); XCTAssertTrue(flow.isCurrent)
    }
    func testFreshAuthorityRecoversSameJournalAfterOldAuthorityRetires() async throws {
        let h = try NotificationHarness(); let flow = try h.flow(); await flow.activate()
        h.loseWriteResponse = true; await flow.mute(minutes: 60)
        let original = try XCTUnwrap(h.journal.restore()); let stored = h.storage.rows
        XCTAssertEqual(h.posts.count, 1)
        h.authorizer.authorizationVersion = nil; XCTAssertFalse(flow.isCurrent)
        h.authorizer.authorizationVersion = UUID()
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.pendingRequestID)
        XCTAssertEqual(h.storage.rows, stored); XCTAssertEqual(try h.journal.restore(), original)
        h.receiptStatus = "APPLIED"; h.currentVersion = 9
        let fresh = NativeChannelNotificationService(authority: try .init(context: h.context, source: h.authorizer), transport: h.dispatcher)
        let recovered = try NativeChannelNotificationCoordinator(client: fresh, journal: h.journal, scope: h.scope)
        await recovered.activate()
        XCTAssertEqual(h.requestedReceiptKeys.last, original.requestID)
        XCTAssertEqual(h.posts.count, 1); XCTAssertNil(try h.journal.restore())
        XCTAssertEqual(recovered.preference?.version, 9); XCTAssertFalse(flow.isCurrent)
    }
}
