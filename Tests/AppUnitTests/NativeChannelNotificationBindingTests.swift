import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import Questify

@MainActor final class NativeChannelNotificationBindingTests: XCTestCase {
    func testReceiptOnlyFreshGlobalBindingRecoversOriginalWithoutReadOrWriteGrant() async throws {
        let h = try NotificationBindingHarness(); let original = try h.seed()
        h.source.operations = [.receipt]
        let flow = try h.make(scope: nil)
        XCTAssertTrue(h.wire.requests.isEmpty) // Construction is not a request or retry.
        await flow.activate()
        XCTAssertEqual(flow.state, .appliedRedacted)
        XCTAssertFalse(flow.canSave); XCTAssertFalse(flow.canMute); XCTAssertFalse(flow.canRead)
        XCTAssertNil(try h.seedJournal.restore())
        XCTAssertEqual(h.wire.requests.count, 1)
        XCTAssertEqual(h.wire.requests[0].httpMethod, "GET")
        XCTAssertEqual(h.wire.requests[0].url?.path, "/api/im/notification-requests/" + original.requestID)
    }
    func testAckOnlyBindingPersistsThroughTheOriginalJournal() async throws {
        for redacted in [false, true] {
            let h = try NotificationBindingHarness(); h.source.operations = [.ack]; h.wire.redactAck = redacted
            let scope = try NativeChannelNotificationScope(type: 1, value: "9012")
            let flow = try h.make(scope: scope)
            await flow.activate()
            XCTAssertFalse(flow.canSave); XCTAssertFalse(flow.canMute); XCTAssertFalse(flow.canRead); XCTAssertTrue(flow.canAck)
            await flow.acknowledge(lastMessageID: 4)
            XCTAssertEqual(flow.state, redacted ? .appliedRedacted : .applied)
            XCTAssertFalse(flow.canRead)
            XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
            XCTAssertEqual(h.wire.requests.last?.url?.path, "/api/im/read")
            XCTAssertFalse(h.wire.requests.contains { $0.url?.path.contains("notify-pref") == true })
            XCTAssertNil(try h.seedJournal.restore())
            h.source.operations = []
            XCTAssertThrowsError(try h.make(scope: scope))
        }
    }
    func testMissingReceiptAuthorityDoesNotConsumeOriginalOrCreateFlow() throws {
        let h = try NotificationBindingHarness(); _ = try h.seed(); let raw = h.storage.rows
        h.source.operations = []
        XCTAssertThrowsError(try h.make(scope: nil))
        XCTAssertEqual(h.storage.rows, raw); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testReceiptOnlyWithoutOriginalCannotConstructOrInventRequest() throws {
        let h = try NotificationBindingHarness(); h.source.operations = [.receipt]
        XCTAssertThrowsError(try h.make(scope: nil))
        XCTAssertTrue(h.storage.rows.isEmpty); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testReadableCorruptJournalShowsPersistenceFailureWithoutRewritingIt() async throws {
        let h = try NotificationBindingHarness(); _ = try h.seed()
        let key = try XCTUnwrap(h.storage.rows.keys.first); h.storage.rows[key] = Data("unreadable-original".utf8)
        let before = h.storage.rows; let flow = try h.make(scope: nil)
        await flow.activate()
        XCTAssertEqual(flow.state, .persistenceFailed)
        XCTAssertEqual(h.storage.rows, before); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testMissingLiveSourceNeverUsesStoredOriginalAsAuthorization() throws {
        let h = try NotificationBindingHarness(); _ = try h.seed(); let raw = h.storage.rows
        h.source.authorizationVersion = nil
        XCTAssertThrowsError(try h.make(scope: nil))
        XCTAssertEqual(h.storage.rows, raw); XCTAssertTrue(h.wire.requests.isEmpty)
    }
}
@MainActor private final class NotificationBindingStorage: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows.removeValue(forKey: key) }
}
@MainActor private final class NotificationBindingSource: NativeChannelNotificationAuthorizing {
    var currentContext: RuntimeDependencyContext?; var authorizationVersion: UUID? = UUID()
    var revision = UUID()
    var operations: Set<NativeChannelNotificationOperation> = [.directory, .preference, .save, .mute, .receipt, .unread]
    func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
        guard ContentDraftContextFence.matches(currentContext, context), self.authorizationVersion == authorizationVersion else { return }
        self.authorizationVersion = nil
    }
    func authorizationRevision(for operation: NativeChannelNotificationOperation, scope: NativeChannelNotificationScope?) -> UUID? {
        operations.contains(operation) && authorizationVersion != nil ? revision : nil
    }
}
@MainActor private final class NotificationBindingWire: HTTPTransport {
    var requests: [URLRequest] = []; var journal: NativeChannelNotificationJournal?
    var status = 200
    var beforeResponse: (() -> Void)?
    var redactAck = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?()
        if status != 200 { return (try JSONSerialization.data(withJSONObject: ["code": status]), status) }
        let original = try XCTUnwrap(try journal?.restore())
        if request.httpMethod == "POST" {
            XCTAssertEqual(request.url?.path, "/api/im/read")
            XCTAssertEqual(original.operation, .ack)
            XCTAssertEqual(request.httpBody, original.body)
            var body: [String: Any] = ["request_id": original.requestID, "status": "APPLIED", "operation": "ACK",
                "scope_type": original.scope.type, "scope_id": original.scope.value,
                "result_redacted": redactAck, "must_refresh_state": true]
            if !redactAck { body["result"] = ["version": 2] }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
        }
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/im/notification-requests/" + original.requestID)
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
            "request_id": original.requestID, "status": "APPLIED", "operation": original.operation.rawValue,
            "scope_type": original.scope.type, "scope_id": original.scope.value,
            "result_redacted": true, "must_refresh_state": true]]), 200)
    }
}
@MainActor private final class NotificationBindingHarness {
    let context: RuntimeDependencyContext
    let storage = NotificationBindingStorage(); let source = NotificationBindingSource(); let wire = NotificationBindingWire()
    let seedJournal: NativeChannelNotificationJournal
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://example.com")!, role: "player",
            session: try .init(accountID: 11, epoch: 1, namespace: "CN:binding", token: "fixture-token"))
        source.currentContext = context
        seedJournal = .init(storage: NativeChannelNotificationProtectedStorage(existing: storage), owner: .init(context: context))
    }
    func seed() throws -> NativeChannelNotificationCommand {
        let original = try NativeChannelNotificationCommand(scope: .init(type: 1, value: "9012"), minutes: 480,
                                                            requestID: "original-binding-0001")
        try seedJournal.persist(original); return original
    }
    func make(scope: NativeChannelNotificationScope?) throws -> NativeChannelNotificationCoordinator {
        try NativeChannelNotificationBinding.make(context: context, storage: storage, scope: scope, makeDispatcher: { journal in
            self.wire.journal = journal
            return try .init(context: self.context, viewerRevision: 2, source: self.source, journal: journal,
                             underlying: self.wire, current: { self.context }, viewer: { 2 }, selected: { self.source })
        })
    }
}

// Calls the same real Binding.make path as the normal AppSession factory, with
// the concrete configuration provider rather than a fixture-only authorizer.
extension NativeChannelNotificationBindingTests {
    func testCancelled401BlocksNormalRemountUntilExplicitNewReceiptIssuance() async throws {
        let h = try NotificationBindingHarness(); let original = try h.seed(); let originalBytes = h.storage.rows
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let key = try NativeChannelNotificationConfigurationKey(operation: .receipt, scope: original.scope)
        let firstVersion = UUID()
        let first = try NativeChannelNotificationConfigurationSnapshot(context: h.context, viewerRevision: 2,
            authorizationVersion: firstVersion, expiresAt: now.addingTimeInterval(120), operations: [key: UUID()])
        var live: NativeChannelNotificationConfigurationSnapshot? = first
        let firstSource = try NativeChannelNotificationConfiguredSource(snapshot: first, current: { live }, now: { now })
        var selected: NativeChannelNotificationConfiguredSource? = firstSource
        func makeNormal() throws -> NativeChannelNotificationCoordinator {
            guard let source = selected?.source(for: h.context, viewerRevision: 2) else { throw NativeChannelNotificationError.accessClosed }
            return try NativeChannelNotificationBinding.make(context: h.context, storage: h.storage, scope: nil,
                makeDispatcher: { journal in
                    h.wire.journal = journal
                    return try NativeChannelNotificationFinalForward(context: h.context, viewerRevision: 2,
                        source: source, journal: journal, underlying: h.wire,
                        current: { h.context }, viewer: { 2 },
                        selected: { selected?.source(for: h.context, viewerRevision: 2) })
                })
        }
        let oldFlow = try makeNormal(); h.wire.status = 401
        h.wire.beforeResponse = { withUnsafeCurrentTask { $0?.cancel() } }
        let firstWork = Task { @MainActor in await oldFlow.activate() }
        await firstWork.value
        XCTAssertEqual(oldFlow.state, .accessClosed); XCTAssertNil(firstSource.authorizationVersion)
        XCTAssertThrowsError(try makeNormal()) // Closing/reopening cannot create another usable wrapper.
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.storage.rows, originalBytes)
        let next = try NativeChannelNotificationConfigurationSnapshot(context: h.context, viewerRevision: 2,
            authorizationVersion: UUID(), expiresAt: now.addingTimeInterval(120), operations: [key: UUID()])
        XCTAssertNotEqual(next.authorizationVersion, firstVersion)
        live = next
        selected = try NativeChannelNotificationConfiguredSource(snapshot: next, current: { live }, now: { now })
        h.wire.status = 200; h.wire.beforeResponse = nil
        let fresh = try makeNormal(); await fresh.activate()
        XCTAssertEqual(fresh.state, .appliedRedacted); XCTAssertFalse(fresh.canSave); XCTAssertFalse(fresh.canMute)
        XCTAssertNil(try h.seedJournal.restore()); XCTAssertNil(firstSource.authorizationVersion)
        XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.path == "/api/im/notification-requests/" + original.requestID })
    }
}

// Source-only delivery: these hosted localization regressions require XCTest on Apple platforms.
extension NativeChannelNotificationBindingTests {
    func testNotificationOriginalStateCopyRendersBothSelectedLocales() {
        let zh = Locale(identifier: "zh-Hans"), en = Locale(identifier: "en")
        let states: [(NativeChannelNotificationState, String)] = [
            (.loading, "正在读取通知设置"), (.saving, "正在保存原请求"), (.checkingReceipt, "正在核对原请求回执"),
            (.outcomeUnknown, "结果待确认。保留了原请求，请先核对回执。"),
            (.pending, "原请求仍在处理中，请稍后查询。"), (.applied, "原请求已保存，已重新读取当前设置。"),
            (.appliedRedacted, "原请求已完成；当前权限已变化，历史结果已隐藏。"),
            (.refreshFailed, "原请求已完成，但当前设置读取失败，请刷新。"),
            (.persistenceFailed, "原请求本地存储失败。结果尚未完成核对，请重试读取。"),
            (.accessClosed, "当前无法访问通知设置，请返回并重新进入。"),
            (.failed(.invalidInput), "请检查时间、时区与通知选项。")]
        for (state, chinese) in states {
            XCTAssertEqual(NativeChannelNotificationPresentation.state(state, locale: zh), chinese)
            let english = NativeChannelNotificationPresentation.state(state, locale: en)
            XCTAssertNotNil(english); XCTAssertNotEqual(english, chinese)
            XCTAssertFalse(english?.hasPrefix("notification.") == true)
        }
        XCTAssertNil(NativeChannelNotificationPresentation.state(.idle, locale: en))
        XCTAssertNil(NativeChannelNotificationPresentation.state(.ready, locale: zh))
    }
    func testNotificationConflictIsLocalizedWithoutEchoingPrivateServerText() {
        let conflict = NativeChannelNotificationError.server(httpStatus: 409, code: 409, errorCode: "PREFERENCE_VERSION_CONFLICT")
        let unknown = NativeChannelNotificationError.server(httpStatus: 500, code: 500, errorCode: "private server detail")
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            XCTAssertNil(NativeChannelNotificationPresentation.failureDetail(conflict, state: .failed(conflict), locale: locale))
            XCTAssertNotNil(NativeChannelNotificationPresentation.failureDetail(conflict, state: .outcomeUnknown, locale: locale))
            XCTAssertNil(NativeChannelNotificationPresentation.failureDetail(unknown, state: .outcomeUnknown, locale: locale))
            XCTAssertFalse(NativeChannelNotificationPresentation.state(.failed(unknown), locale: locale)?.contains("private server detail") == true)
        }
        XCTAssertEqual(NativeChannelNotificationPresentation.state(.failed(unknown), locale: Locale(identifier: "zh-Hans")), "读取失败，请重试。")
        XCTAssertEqual(NativeChannelNotificationPresentation.failureDetail(conflict, state: .outcomeUnknown, locale: Locale(identifier: "zh-Hans")), "设置已被另一端更新，请读取当前设置并先核对原请求。")
    }
    func testNotificationPermissionUnknownAndQuietAuthorizationStayDistinct() {
        let locale = Locale(identifier: "en")
        XCTAssertEqual(NativeChannelNotificationPresentation.authorization(.unknown(91), locale: locale), "System permission status is unknown")
        XCTAssertNotEqual(NativeChannelNotificationPresentation.authorization(.provisional, locale: locale), NativeChannelNotificationPresentation.authorization(.authorized, locale: locale))
        XCTAssertNotEqual(NativeChannelNotificationPresentation.authorization(.ephemeral, locale: locale), NativeChannelNotificationPresentation.authorization(.authorized, locale: locale))
        XCTAssertEqual(NativeChannelNotificationPresentation.setting(.unknown(91), locale: locale), "Unknown")
        XCTAssertEqual(NativeChannelNotificationPresentation.permissionIssue("无法读取系统通知权限，请重试。", locale: locale), "System notification permission could not be read. Try again.")
        XCTAssertFalse(NativeChannelNotificationPresentation.permissionIssue("private diagnostic", locale: locale).contains("private diagnostic"))
    }
    func testNotificationScopeIDAndRecoveryMeaningAreNotReinterpretedByLocale() {
        let exact = "9223372036854775807"
        for locale in [Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
            XCTAssertTrue(NativeChannelNotificationPresentation.format("notification.global.channelScope", locale: locale, exact).hasSuffix(exact))
            XCTAssertNotEqual(NativeChannelNotificationPresentation.level(.inherit, locale: locale), NativeChannelNotificationPresentation.level(.nothing, locale: locale))
        }
        let english = NativeChannelNotificationPresentation.localized("notification.recovery.confirm", locale: Locale(identifier: "en"))
        XCTAssertTrue(english.contains("original receipt")); XCTAssertTrue(english.contains("permission is still valid"))
    }
}
