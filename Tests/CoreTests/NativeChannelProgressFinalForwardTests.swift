import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class ProgressFinalQueue {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; entry?.resume(); entry = nil; await withCheckedContinuation { release = $0 } }
    func waitUntilEntered() async { if !entered { await withCheckedContinuation { entry = $0 } } }
    func open() { release?.resume(); release = nil }
}
@MainActor private final class ProgressFinalWire: NativeChannelProgressDispatching {
    var requests: [URLRequest] = []
    var queued: (() async -> Void)?
    var beforeReturn: (() -> Void)?
    var failure: Error?
    var result = (Data("opaque-response-bytes".utf8), 200)
    func send(_ request: URLRequest, fence: NativeChannelProgressDispatchFence) async throws -> (Data, Int) {
        await queued?()
        // This is the synthetic physical forward, after the queue, not the wrapper call.
        guard fence.isCurrent else { throw NativeChannelProgressError.closed }
        requests.append(request); beforeReturn?()
        if let failure { throw failure }
        return result
    }
}
@MainActor private final class ProgressFinalStore: NativeChannelProgressJournalStorage {
    var rows: [String: Data] = [:]
    var reads = 0
    var failReads = false
    func read(_ key: String) throws -> Data? { reads += 1; if failReads { throw NativeChannelProgressError.persistence }; return rows[key] }
    func write(_ data: Data, key: String) throws { rows[key] = data }
    func remove(_ key: String) throws { rows[key] = nil }
}
@MainActor private final class ProgressFinalHarness {
    static let allOperations: Set<NativeChannelProgressOperation> = [.definitions, .overview, .top, .detail, .best, .recent, .version, .meter, .privacy, .savePrivacy, .receipt]
    static let allPaths: Set<String> = ["api/channel/5/board", "api/channel/5/progress/overview", "api/channel/5/board/completion/top",
        "api/channel/5/board/completion/detail", "api/channel/5/board/completion/me/best", "api/channel/5/board/completion/me/recent",
        "api/channel/5/board/completion/version", "api/progress/meter", "api/privacy/progress"]
    let context: RuntimeDependencyContext
    let selection: NativeChannelProgressRuntimeSelection
    let store = ProgressFinalStore()
    let wire = ProgressFinalWire()
    let journal: NativeChannelProgressPrivacyJournal
    var runtime: RuntimeDependencyContext?
    var selected: NativeChannelProgressRuntimeSelection?
    var presented = true
    var receiptLease: OperationEndpointApproval?
    var receiptSelector: ((NativeChannelProgressPrivacyCommand) -> OperationEndpointApproval?)?
    var forward: NativeChannelProgressFinalForward!
    init(operations: Set<NativeChannelProgressOperation> = allOperations, paths: Set<String> = allPaths) throws {
        let base = URL(string: "https://progress.example.org/tenant/cn")!
        context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 101, epoch: 7, namespace: "CN", token: "fixture-token"))
        let identity = try NativeChannelProgressIdentity(actorID: 101, namespace: "CN", origin: base, sessionEpoch: "7")
        let revision = UUID()
        let authority = try NativeChannelProgressAuthoritySnapshot(identity: identity, channelID: 5, authorizationVersion: "independent-fixture-policy",
            metadataVersion: 2, permissionVersion: 3, endpointApprovalRevision: revision, viewerRevision: 4, operations: operations)
        let endpoints = try OperationEndpointApproval(baseURL: base, namespace: "CN", accountID: 101, paths: paths)
        selection = try .init(authority: authority, endpoints: endpoints, endpointRevision: revision)
        journal = try .init(identity: identity, storage: store); runtime = context; selected = selection
        forward = try .init(context: context, selection: selection, journal: journal, underlying: wire,
            current: { [weak self] in self?.runtime }, selected: { [weak self] in self?.selected }, presentation: { [weak self] in self?.presented == true },
            receiptApproval: { [weak self] command in guard let self else { return nil }; return self.receiptSelector?(command) ?? self.receiptLease })
    }
    func approveReceipt(_ command: NativeChannelProgressPrivacyCommand, account: Int = 101, path: String? = nil) throws {
        receiptLease = try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: account,
            paths: [path ?? "api/progress/requests/" + command.requestId])
    }
    func request(_ operation: NativeChannelProgressOperation, command: NativeChannelProgressPrivacyCommand? = nil) async throws -> URLRequest {
        let transport = NativeChannelProgressRecordingTransport()
        let row = #"{"visible":true,"rank":null,"rank_known":false,"state":"NO_COMPLETED_EFFORT"}"#
        let page = #"{"visible":true,"revision":"r","list":[],"has_more":false}"#
        let privacy = #"{"aggregate_scope":"PUBLIC","detail_scope":"TEAM","photo_scope":"TEAM","leaderboard_scope":"IN","revision":0,"applies_to":"CHANNEL_PROGRESS","effective":{"aggregate_scope":"CHANNEL","detail_scope":"TEAM"}}"#
        let payload: String
        switch operation {
        case .definitions: payload = #"{"visible":true,"list":[]}"#
        case .overview, .meter: payload = #"{"visible":false}"#
        case .top, .detail, .recent: payload = page
        case .best: payload = row
        case .version: payload = #"{"visible":true,"revision":"r"}"#
        case .privacy: payload = privacy
        case .savePrivacy, .receipt:
            let original = try XCTUnwrap(command)
            payload = "{\"aggregate_scope\":\"SELF\",\"detail_scope\":\"SELF\",\"photo_scope\":\"SELF\",\"leaderboard_scope\":\"OUT\",\"revision\":1,\"updated_at\":\"2026-10-23T16:00:00Z\",\"applies_to\":\"CHANNEL_PROGRESS\",\"request_id\":\"\(original.requestId)\",\"status\":\"APPLIED\"}"
        }
        transport.responses = [(Data("{\"code\":200,\"data\":\(payload)}".utf8), 200)]
        let service = NativeChannelProgressService(configuration: try APIConfiguration(baseURL: context.baseURL), transport: transport)
        let board = try NativeChannelProgressFixtures.board(), query = try NativeChannelProgressQuery(board: board, period: "ALL")
        let token = context.session.token
        switch operation {
        case .definitions: _ = try await service.definitions(channelID: 5, token: token)
        case .overview: _ = try await service.overview(channelID: 5, token: token)
        case .top: _ = try await service.page(channelID: 5, query: query, detail: false, cursor: nil, token: token)
        case .detail: _ = try await service.page(channelID: 5, query: query, detail: true, cursor: nil, token: token)
        case .best: _ = try await service.best(channelID: 5, query: query, token: token)
        case .recent: _ = try await service.recent(channelID: 5, query: query, cursor: nil, token: token)
        case .version: _ = try await service.version(channelID: 5, boardKey: board.boardKey, token: token)
        case .meter: _ = try await service.meter(channelID: 5, board: board, actorID: 101, token: token)
        case .privacy: _ = try await service.privacy(channelID: 5, token: token)
        case .savePrivacy: _ = try await service.save(XCTUnwrap(command), token: token)
        case .receipt: _ = try await service.receipt(XCTUnwrap(command), token: token)
        }
        return try XCTUnwrap(transport.requests.first)
    }
}

@MainActor final class NativeChannelProgressFinalForwardTests: XCTestCase {
    private func blocked(_ h: ProgressFinalHarness, _ request: URLRequest, fence: NativeChannelProgressDispatchFence? = nil,
                         file: StaticString = #filePath, line: UInt = #line) async {
        let count = h.wire.requests.count
        do { _ = try await h.forward.send(request, fence: fence ?? .init { true }); XCTFail("Unapproved request forwarded", file: file, line: line) }
        catch { /* Closed, unknown journal, and invalid original are all fail-closed here. */ }
        XCTAssertEqual(h.wire.requests.count, count, file: file, line: line)
    }
    func testRealServiceWireBytesPassUnchangedForEveryApprovedOperation() async throws {
        let h = try ProgressFinalHarness(), command = try NativeChannelProgressFixtures.command()
        try h.journal.saveBeforeDispatch(command); try h.approveReceipt(command)
        for operation in [NativeChannelProgressOperation.definitions, .overview, .top, .detail, .best, .recent, .version, .meter, .privacy, .savePrivacy, .receipt] {
            let request = try await h.request(operation, command: command)
            let result = try await h.forward.send(request, fence: .init { true })
            let forwarded = try XCTUnwrap(h.wire.requests.last)
            XCTAssertEqual(forwarded.url.map { Data($0.absoluteString.utf8) }, request.url.map { Data($0.absoluteString.utf8) })
            XCTAssertEqual(forwarded.httpMethod, request.httpMethod); XCTAssertEqual(forwarded.httpBody, request.httpBody)
            XCTAssertEqual(forwarded.allHTTPHeaderFields, request.allHTTPHeaderFields)
            XCTAssertEqual(result.0, h.wire.result.0); XCTAssertEqual(result.1, 200)
        }
        XCTAssertEqual(h.wire.requests.count, 11); XCTAssertEqual(try h.journal.restore(), command)
    }
    func testReceiptNeedsOriginalAndSeparateExactApprovalEvenWhenGeneralPathIsListed() async throws {
        let command = try NativeChannelProgressFixtures.command(), path = "api/progress/requests/" + command.requestId
        let h = try ProgressFinalHarness(paths: ProgressFinalHarness.allPaths.union([path]))
        let request = try await h.request(.receipt, command: command)
        await blocked(h, request)
        try h.journal.saveBeforeDispatch(command); await blocked(h, request)
        try h.approveReceipt(command, account: 102); await blocked(h, request)
        try h.approveReceipt(command, path: "api/progress/requests/another_request_0002"); await blocked(h, request)
        try h.approveReceipt(command); _ = try await h.forward.send(request, fence: .init { true })
        try h.journal.settle(command); await blocked(h, request)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testIndependentOperationAndEndpointCannotGrantEachOther() async throws {
        let readOnly = try ProgressFinalHarness(operations: [.definitions]), command = try NativeChannelProgressFixtures.command()
        try readOnly.journal.saveBeforeDispatch(command)
        await blocked(readOnly, try await readOnly.request(.savePrivacy, command: command))
        let wrongPath = try ProgressFinalHarness(operations: [.savePrivacy], paths: ["api/channel/5/board"])
        try wrongPath.journal.saveBeforeDispatch(command)
        await blocked(wrongPath, try await wrongPath.request(.savePrivacy, command: command))
        let mixed = try ProgressFinalHarness(paths: ["api/channel/6/board"])
        var request = try await mixed.request(.definitions)
        request.url = mixed.context.baseURL.appendingPathComponent("api/channel/6/board")
        await blocked(mixed, request)
    }
    func testExtraHeadersBodyQueriesCookiesAndOriginPrefixAreRejected() async throws {
        let h = try ProgressFinalHarness(), original = try await h.request(.definitions)
        var requests: [URLRequest] = []
        func change(_ edit: (inout URLRequest) -> Void) { var copy = original; edit(&copy); requests.append(copy) }
        change { $0.setValue("wrong-token", forHTTPHeaderField: "Authorization") }
        change { $0.setValue("text/html", forHTTPHeaderField: "Accept") }
        change { $0.setValue("x", forHTTPHeaderField: "X-Extra") }
        change { $0.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        change { $0.httpShouldHandleCookies = true }
        change { $0.httpBody = Data("{}".utf8) }
        change { $0.httpBodyStream = InputStream(data: Data("{}".utf8)) }
        change { $0.httpMethod = "POST" }
        change { $0.cachePolicy = .returnCacheDataElseLoad }
        change { $0.url = URL(string: "https://other.example.org/tenant/cn/api/channel/5/board") }
        change { $0.url = URL(string: "https://progress.example.org/api/channel/5/board") }
        change { $0.url = URL(string: original.url!.absoluteString + "?channel_id=5") }
        change { $0.url = URL(string: original.url!.absoluteString + "#fragment") }
        change { $0.url = URL(string: original.url!.absoluteString + "/") }
        for request in requests { await blocked(h, request) }
    }
    func testFilterAndSubjectQueriesCannotCrossReadKindsOrOwners() async throws {
        let h = try ProgressFinalHarness()
        for (kind, extra) in [(NativeChannelProgressOperation.top, "filter%5Bteam_id%5D=8"), (.best, "limit=20"), (.recent, "filter%5Bcompleted%5D=true"), (.meter, "subject_id=102")] {
            var request = try await h.request(kind)
            request.url = URL(string: request.url!.absoluteString + "&" + extra)
            await blocked(h, request)
        }
        var meter = try await h.request(.meter)
        meter.url = URL(string: meter.url!.absoluteString.replacingOccurrences(of: "subject_id=101", with: "subject_id=102"))
        await blocked(h, meter)
        var top = try await h.request(.top)
        top.url = URL(string: top.url!.absoluteString + "&limit=30")
        await blocked(h, top)
    }
    func testPrivacyPOSTRequiresOriginalScopesCASAndExactSerializedBytes() async throws {
        let h = try ProgressFinalHarness(), command = try NativeChannelProgressFixtures.command()
        try h.journal.saveBeforeDispatch(command); let original = try await h.request(.savePrivacy, command: command)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(original.httpBody)) as? [String: Any])
        for (field, value) in [("aggregate_scope", "PUBLIC"), ("detail_scope", "PUBLIC"), ("photo_scope", "TEAM"), ("leaderboard_scope", "IN"), ("request_id", "another_request_0002")] {
            var changed = object; changed[field] = value; var request = original
            request.httpBody = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]); await blocked(h, request)
        }
        for field in ["expected_revision", "channel_id"] {
            var changed = object; changed[field] = 9; var request = original
            request.httpBody = try JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys]); await blocked(h, request)
        }
        var whitespace = original; whitespace.httpBody?.append(Data("\n".utf8)); await blocked(h, whitespace)
        _ = try await h.forward.send(original, fence: .init { true })
        XCTAssertEqual(h.wire.requests.last?.httpBody, try command.wireBody()); XCTAssertEqual(try h.journal.restore(), command)
    }
    func testQueuedDelegateConsumesComposedFenceBeforePhysicalForward() async throws {
        for mode in ["visit", "owner", "ancestor", "selection", "token", "cancel", "journal", "receipt"] {
            let h = try ProgressFinalHarness(), queue = ProgressFinalQueue(), command = try NativeChannelProgressFixtures.command()
            let kind: NativeChannelProgressOperation = mode == "journal" ? .savePrivacy : (mode == "receipt" ? .receipt : .definitions)
            if kind == .savePrivacy || kind == .receipt { try h.journal.saveBeforeDispatch(command); try h.approveReceipt(command) }
            let request = try await h.request(kind, command: command); var visit = true
            h.wire.queued = { await queue.wait() }
            let operation = Task { try await h.forward.send(request, fence: .init { visit }) }
            await queue.waitUntilEntered()
            switch mode {
            case "visit": visit = false
            case "owner": h.runtime = nil
            case "ancestor": h.presented = false
            case "selection": h.selected = nil
            case "token": h.runtime = RuntimeDependencyContext(market: .china, baseURL: h.context.baseURL, role: "player", session: try .init(accountID: 101, epoch: 7, namespace: "CN", token: "replaced-token"))
            case "cancel": operation.cancel()
            case "journal": h.store.rows = h.store.rows.mapValues { _ in Data("unknown-journal".utf8) }
            default: h.receiptLease = nil
            }
            queue.open()
            do { _ = try await operation.value; XCTFail("Queued retired operation forwarded: \(mode)") }
            catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed, mode) }
            XCTAssertTrue(h.wire.requests.isEmpty, mode)
        }
    }
    func testQueuedOriginalJournalMustPreserveWireBytesNotUnicodeEquality() async throws {
        let h = try ProgressFinalHarness(), queue = ProgressFinalQueue()
        let original = try NativeChannelProgressPrivacyCommand(values: NativeChannelProgressFixtures.values(), revision: nil,
            updatedAt: "caf\u{00e9}", requestID: "original_request_0001")
        let changed = try NativeChannelProgressPrivacyCommand(values: NativeChannelProgressFixtures.values(), revision: nil,
            updatedAt: "cafe\u{0301}", requestID: original.requestId)
        XCTAssertEqual(original, changed); XCTAssertNotEqual(try original.wireBody(), try changed.wireBody())
        try h.journal.saveBeforeDispatch(original)
        let request = try await h.request(.savePrivacy, command: original)
        h.wire.queued = { await queue.wait() }
        let operation = Task { try await h.forward.send(request, fence: .init { true }) }
        await queue.waitUntilEntered()
        let key = try XCTUnwrap(h.store.rows.keys.first)
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.store.rows[key])) as? [String: Any])
        record["command"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed))
        record["wireBody"] = try changed.wireBody().base64EncodedString()
        h.store.rows[key] = try JSONSerialization.data(withJSONObject: record)
        XCTAssertEqual(try h.journal.restore(), original, "String equality alone would not detect these changed bytes")
        queue.open()
        do { _ = try await operation.value; XCTFail("Changed original bytes forwarded") }
        catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLate401ResponseOrErrorCannotLogOutNewVisit() async throws {
        for throwsError in [false, true] {
            let h = try ProgressFinalHarness(); var logout = 0
            let client = try NativeChannelProgressClient(captured: h.selection.authority, dispatcher: h.forward,
                current: { h.selected?.authority }, token: { h.runtime?.session.token }, onUnauthorized: { logout += 1 })
            h.wire.result = (Data(), 401)
            if throwsError { h.wire.failure = NativeChannelProgressError.server(status: 401, code: nil) }
            h.wire.beforeReturn = { h.presented = false }
            do { _ = try await client.definitions(); XCTFail("A stale 401 escaped") }
            catch { XCTAssertEqual(error as? NativeChannelProgressError, .closed) }
            XCTAssertEqual(logout, 0); XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testObservedOwnerOrAncestorRetirementDoesNotReviveByABA() async throws {
        for ancestor in [false, true] {
            let h = try ProgressFinalHarness(), request = try await h.request(.definitions)
            if ancestor { h.presented = false } else { h.runtime = nil }
            XCTAssertFalse(h.forward.isCurrent); h.presented = true; h.runtime = h.context
            XCTAssertFalse(h.forward.isCurrent); await blocked(h, request)
        }
    }
    func testUnknownJournalDoesNotBlockNonRecoveryReadsOrRewriteBytes() async throws {
        let h = try ProgressFinalHarness(), command = try NativeChannelProgressFixtures.command()
        try h.journal.saveBeforeDispatch(command)
        h.store.rows = h.store.rows.mapValues { _ in Data("unknown-journal-original-bytes".utf8) }
        let original = h.store.rows; h.store.reads = 0
        for kind in [NativeChannelProgressOperation.definitions, .overview, .privacy] {
            let request = try await h.request(kind)
            _ = try await h.forward.send(request, fence: .init { true })
        }
        XCTAssertEqual(h.store.reads, 0); XCTAssertEqual(h.store.rows, original)
        await blocked(h, try await h.request(.savePrivacy, command: command))
        try h.approveReceipt(command); await blocked(h, try await h.request(.receipt, command: command))
        XCTAssertEqual(h.store.rows, original); XCTAssertEqual(h.wire.requests.count, 3)
    }
    func testReceiptApprovalRevokedBetweenValidationAndForwardIsNotSent() async throws {
        let h = try ProgressFinalHarness(), command = try NativeChannelProgressFixtures.command()
        try h.journal.saveBeforeDispatch(command); try h.approveReceipt(command)
        let lease = h.receiptLease; h.receiptLease = nil; var selections = 0
        h.receiptSelector = { _ in selections += 1; return selections == 1 ? lease : nil }
        await blocked(h, try await h.request(.receipt, command: command)); XCTAssertEqual(selections, 2)
    }
}
