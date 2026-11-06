import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class UsageHistoryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var after: (() -> Void)?
    var payload: ((URLRequest) throws -> [String: Any])?
    var raw: Data?
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); defer { after?() }
        let bytes = try raw ?? JSONSerialization.data(withJSONObject: ["code": 200, "data": payload?(request) ?? UsageHistoryFixture.page([])], options: .sortedKeys)
        return (bytes, status)
    }
}
@MainActor private final class UsageHistoryFixture {
    let base = URL(string: "https://usage.example.test/native")!
    let wire = UsageHistoryWire()
    var current: RuntimeDependencyContext?
    let captured: RuntimeDependencyContext
    var approved = true
    let grant: UsageConsentReadApproval
    lazy var service = UsageConsentReadService(configuration: try! .init(baseURL: base), transport: wire,
        captured: captured, approval: grant, current: { self.current }, stillApproved: { self.approved })
    lazy var coordinator = UsageConsentReadCoordinator(service: service)
    init(paths: Set<String> = Set(UsageConsentReadRoute.paths)) throws {
        captured = .init(market: .china, baseURL: URL(string: "https://usage.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "usage-test", token: "synthetic-usage", role: "player"))
        current = captured
        grant = try .init(market: .china, endpoint: .init(baseURL: captured.baseURL, namespace: "usage-test", accountID: 7, paths: paths))
    }
    static func record(_ id: Int, key: String? = nil, time: Int? = 1) -> [String: Any] {
        ["id": id, "docType": "privacy_policy", "docVersion": "v1", "eventType": "AGREE", "requestId": key ?? "key-\(id)", "occurredAt": time.map { $0 as Any } ?? NSNull()]
    }
    static func page(_ ids: [Int], next: Int? = nil) -> [String: Any] {
        ["accountId": 7, "scene": "app_launch", "readOnly": true, "nativeMarketBinding": "UNPROVEN",
         "items": ids.map { record($0) }, "nextBeforeId": next.map { $0 as Any } ?? NSNull()]
    }
    static func original(key: String = "key-1", version: String = "v1", availability: String = "MISSING") -> [String: Any] {
        var row = record(1, key: key); row["docVersion"] = version
        return ["accountId": 7, "scene": "app_launch", "readOnly": true, "nativeMarketBinding": "UNPROVEN", "record": row,
            "latestRecordId": 2, "document": ["docType": "privacy_policy", "version": version, "availability": availability]]
    }
    func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var value = URLRequest(url: parts.url!); value.httpMethod = "GET"; value.httpShouldHandleCookies = false
        value.setValue("application/json", forHTTPHeaderField: "Accept"); value.setValue("synthetic-usage", forHTTPHeaderField: "Authorization")
        return value
    }
    func decode<T: Decodable>(_ object: [String: Any], as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }
}

@MainActor final class UsageConsentHistoryJourneyTests: XCTestCase {
    func testOnlyOriginalReadRoutesAndExactQueryShapeAreAccepted() throws {
        let f = try UsageHistoryFixture()
        XCTAssertNotNil(UsageConsentReadRoute(request: f.request(UsageConsentReadRoute.history), baseURL: f.base))
        for query in [[URLQueryItem(name: "accountId", value: "8")], [.init(name: "scene", value: "cancellation")], [.init(name: "beforeId", value: "01")], [.init(name: "beforeId", value: "-1")]] {
            XCTAssertNil(UsageConsentReadRoute(request: f.request(UsageConsentReadRoute.history, query: query), baseURL: f.base))
        }
        for path in ["api/compliance/consents", "api/agreement/consent", "api/user/deregister/status"] {
            XCTAssertNil(UsageConsentReadRoute(request: f.request(path), baseURL: f.base))
        }
        var body = f.request(UsageConsentReadRoute.history); body.httpBody = Data("{}".utf8); XCTAssertNil(UsageConsentReadRoute(request: body, baseURL: f.base))
        var cookies = f.request(UsageConsentReadRoute.history); cookies.httpShouldHandleCookies = true; XCTAssertNil(UsageConsentReadRoute(request: cookies, baseURL: f.base))
        var post = f.request(UsageConsentReadRoute.history); post.httpMethod = "POST"; XCTAssertNil(UsageConsentReadRoute(request: post, baseURL: f.base))
    }
    func testOriginalUnicodeKeyIsNotNormalizedTrimmedOrReplaced() async throws {
        let f = try UsageHistoryFixture(paths: [UsageConsentReadRoute.original]), key = " 原键 / + e\u{301} "
        f.wire.payload = { _ in UsageHistoryFixture.original(key: key) }
        let detail = try await f.service.original(requestId: key)
        XCTAssertEqual(Data(detail.record.requestId.utf8), Data(key.utf8))
        let request = try XCTUnwrap(f.wire.requests.first)
        let transmitted = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertEqual(transmitted.map { Data($0.utf8) }, Data(key.utf8))
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
    }
    func testOriginalOnlyApprovalDoesNotGrantHistoryOrConsentWrites() async throws {
        let f = try UsageHistoryFixture(paths: [UsageConsentReadRoute.original])
        do { _ = try await f.service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .unavailable) }
        XCTAssertEqual(f.wire.requests.count, 0)
        XCTAssertThrowsError(try UsageConsentReadApproval(market: .china, endpoint: .init(baseURL: f.base, namespace: "usage-test", accountID: 7, paths: ["api/compliance/consents"])))
    }
    func testMissingApprovalMakesNoRequest() async throws {
        let f = try UsageHistoryFixture()
        let service = UsageConsentReadService(configuration: try .init(baseURL: f.base), transport: f.wire, captured: f.captured, approval: nil, current: { f.current })
        do { _ = try await service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .unavailable) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testHistoryPaginatesWithOriginalCursorAndNoMutation() async throws {
        let f = try UsageHistoryFixture()
        f.wire.payload = { request in
            if URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == nil {
                return UsageHistoryFixture.page(Array((51...100).reversed()), next: 51)
            }
            return UsageHistoryFixture.page(Array((1...50).reversed()))
        }
        let owner = f.coordinator.beginPresentation()
        await f.coordinator.reload(intent: try XCTUnwrap(f.coordinator.captureRead(owner)))
        XCTAssertEqual(f.coordinator.items.count, 50)
        await f.coordinator.reload(more: true, intent: try XCTUnwrap(f.coordinator.captureRead(owner)))
        XCTAssertEqual(f.coordinator.items.map(\.id), Array((1...100).reversed())); XCTAssertNil(f.coordinator.nextBeforeId)
        XCTAssertEqual(URLComponents(url: f.wire.requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "51")
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    }
    func testDuplicateRequestAcrossPagesDoesNotMergeOrChangeOriginalCursor() async throws {
        let f = try UsageHistoryFixture(); f.wire.payload = { _ in UsageHistoryFixture.page(Array((51...100).reversed()), next: 51) }
        await f.coordinator.reload()
        f.wire.payload = { _ in var page = UsageHistoryFixture.page([50]); page["items"] = [UsageHistoryFixture.record(50, key: "key-100")]; return page }
        await f.coordinator.reload(more: true)
        XCTAssertEqual(f.coordinator.items.count, 50); XCTAssertEqual(f.coordinator.nextBeforeId, 51); XCTAssertEqual(f.coordinator.failure, .malformed)
    }
    func testWrongOwnerPurposeReadFlagAndNativeBindingAreRejected() async throws {
        let variants: [(String, Any)] = [("accountId", 8), ("scene", "object_photo"), ("readOnly", false), ("nativeMarketBinding", "APPROVED")]
        for (field, value) in variants {
            let f = try UsageHistoryFixture(); f.wire.payload = { _ in var page = UsageHistoryFixture.page([1]); page[field] = value; return page }
            do { _ = try await f.service.history(); XCTFail(field) } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .malformed) }
        }
    }
    func testWrongPageOrderCursorAndRepeatedIDsFailClosed() throws {
        let f = try UsageHistoryFixture()
        for data in [UsageHistoryFixture.page([1, 2]), UsageHistoryFixture.page([2, 2]), UsageHistoryFixture.page([2], next: 2)] {
            let page = try f.decode(data, as: UsageConsentEvidencePage.self)
            XCTAssertThrowsError(try page.validate(account: 7, before: nil))
        }
        let page = try f.decode(UsageHistoryFixture.page([10]), as: UsageConsentEvidencePage.self)
        XCTAssertThrowsError(try page.validate(account: 7, before: 10))
    }
    func testCanonicalEquivalentOriginalKeyDoesNotMatchDifferentBytes() throws {
        let f = try UsageHistoryFixture(), supplied = "e\u{301}", received = "\u{e9}"
        let original = try f.decode(UsageHistoryFixture.original(key: received), as: UsageConsentOriginalEvidence.self)
        XCTAssertThrowsError(try original.validate(account: 7, requestId: supplied))
    }
    func testDocumentExactVersionAndUnavailableStatesCannotExposeText() throws {
        let f = try UsageHistoryFixture()
        for availability in ["MISSING", "MISMATCH", "UNPUBLISHED", "INCOMPLETE"] {
            var data = UsageHistoryFixture.original(availability: availability)
            var doc = data["document"] as! [String: Any]; doc["content"] = "must remain hidden"; data["document"] = doc
            XCTAssertThrowsError(try f.decode(data, as: UsageConsentOriginalEvidence.self).validate(account: 7, requestId: "key-1"))
        }
        var data = UsageHistoryFixture.original(version: "e\u{301}")
        data["document"] = ["docType": "privacy_policy", "version": "\u{e9}", "availability": "MISSING"]
        XCTAssertThrowsError(try f.decode(data, as: UsageConsentOriginalEvidence.self).validate(account: 7, requestId: "key-1"))
    }
    func testAvailableStoredSourceIsSeparatedFromHistoricalEventAndCurrentConsent() async throws {
        let f = try UsageHistoryFixture(); f.wire.payload = { _ in
            var data = UsageHistoryFixture.original(availability: "SOURCE_AVAILABLE")
            data["document"] = ["docType": "privacy_policy", "version": "v1", "availability": "SOURCE_AVAILABLE", "title": "Stored version", "content": "Original source text", "publishedAt": 1]
            return data
        }
        let value = try await f.service.original(requestId: "key-1")
        XCTAssertNotEqual(value.record.id, value.latestRecordId); XCTAssertEqual(value.nativeMarketBinding, "UNPROVEN")
        XCTAssertTrue(value.readOnly); XCTAssertEqual(value.document.content, "Original source text")
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
    func testUnknownOrMissingRecordNeverBecomesEmptyHistorySuccess() async throws {
        let f = try UsageHistoryFixture(); f.wire.raw = Data(#"{"code":404}"#.utf8)
        await f.coordinator.read("missing")
        XCTAssertEqual(f.coordinator.failure, .missing); XCTAssertNil(f.coordinator.detail); XCTAssertFalse(f.coordinator.loaded)
    }
    func testCancelledBeforeQueuedReadCannotDispatch() async throws {
        let f = try UsageHistoryFixture(), owner = f.coordinator.beginPresentation(), intent = try XCTUnwrap(f.coordinator.captureRead(owner))
        let task = Task { await f.coordinator.reload(intent: intent) }; task.cancel(); await task.value
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(f.coordinator.busy)
    }
    func testQueuedOriginalAfterPageCloseCannotReadOrMutateNewPresentation() async throws {
        let f = try UsageHistoryFixture(), old = f.coordinator.beginPresentation(), intent = try XCTUnwrap(f.coordinator.captureRead(old))
        f.coordinator.endPresentation(old); let new = f.coordinator.beginPresentation()
        await f.coordinator.read("old-key", intent: intent)
        f.coordinator.endPresentation(old)
        XCTAssertNotNil(f.coordinator.captureRead(new)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testBackgroundRetiresQueuedReadButForegroundAllowsFreshReadOnlyIntent() async throws {
        let f = try UsageHistoryFixture(), owner = f.coordinator.beginPresentation(), old = try XCTUnwrap(f.coordinator.captureRead(owner))
        f.coordinator.suspend(owner); await f.coordinator.reload(intent: old); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertTrue(f.coordinator.resume(owner)); await f.coordinator.reload(intent: try XCTUnwrap(f.coordinator.captureRead(owner)))
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(f.coordinator.loaded)
    }
    func testClearAllowsSameOwnerFreshRetryButNotOldCapturedIntent() async throws {
        let f = try UsageHistoryFixture(), owner = f.coordinator.beginPresentation(), old = try XCTUnwrap(f.coordinator.captureRead(owner))
        f.coordinator.clear(); await f.coordinator.reload(intent: old); XCTAssertTrue(f.wire.requests.isEmpty)
        await f.coordinator.reload(intent: try XCTUnwrap(f.coordinator.captureRead(owner))); XCTAssertTrue(f.coordinator.loaded)
    }
    func testSameQueuedIntentCannotDispatchAgainAfterFirstCompletion() async throws {
        let f = try UsageHistoryFixture(), owner = f.coordinator.beginPresentation(), intent = try XCTUnwrap(f.coordinator.captureRead(owner))
        await f.coordinator.reload(intent: intent); await f.coordinator.reload(intent: intent)
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testCloseDuringReadDiscardsLatePrivatePayload() async throws {
        let f = try UsageHistoryFixture(), owner = f.coordinator.beginPresentation(), intent = try XCTUnwrap(f.coordinator.captureRead(owner))
        f.wire.payload = { _ in UsageHistoryFixture.page([1]) }; f.wire.after = { f.coordinator.endPresentation(owner) }
        await f.coordinator.reload(intent: intent)
        XCTAssertFalse(f.coordinator.loaded); XCTAssertTrue(f.coordinator.items.isEmpty); XCTAssertFalse(f.coordinator.busy)
    }
    func testReadAfterSourceRevocationOrLateRevocationCannotDisplay() async throws {
        let f = try UsageHistoryFixture(); f.approved = false
        do { _ = try await f.service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .stale) }
        XCTAssertTrue(f.wire.requests.isEmpty); f.approved = true; f.wire.after = { f.approved = false }
        await f.coordinator.reload(); XCTAssertFalse(f.coordinator.loaded); XCTAssertTrue(f.coordinator.items.isEmpty)
    }
    func testCompleteSessionRoleAndCredentialChangesRetireService() async throws {
        let f = try UsageHistoryFixture()
        f.current = .init(market: .china, baseURL: f.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "usage-test", token: "synthetic-usage", role: "merchant"))
        do { _ = try await f.service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .stale) }
        f.current = .init(market: .china, baseURL: f.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "usage-test", token: "synthetic-other", role: "player"))
        do { _ = try await f.service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .stale) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testScopedTransportRejectsWrongTokenWriteAndIndependentPath() async throws {
        let f = try UsageHistoryFixture(paths: [UsageConsentReadRoute.original])
        let transport = UsageConsentReadScopedTransport(context: f.captured, approval: f.grant, underlying: f.wire, current: { f.current }, stillApproved: { f.approved })
        var wrong = f.request(UsageConsentReadRoute.original, query: [.init(name: "requestId", value: "key")]); wrong.setValue("other-token", forHTTPHeaderField: "Authorization")
        var post = f.request(UsageConsentReadRoute.original, query: [.init(name: "requestId", value: "key")]); post.httpMethod = "POST"
        for request in [wrong, post, f.request(UsageConsentReadRoute.history)] {
            do { _ = try await transport.send(request); XCTFail() } catch {}
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testApprovalNamespaceAndRevisionHaveExactIdentity() throws {
        let f = try UsageHistoryFixture(), id = UUID()
        let one = try UsageConsentReadApproval(market: .china, endpoint: .init(baseURL: f.base, namespace: "e\u{301}", accountID: 7, paths: [UsageConsentReadRoute.history]), revision: id)
        let two = try UsageConsentReadApproval(market: .china, endpoint: .init(baseURL: f.base, namespace: "\u{e9}", accountID: 7, paths: [UsageConsentReadRoute.history]), revision: id)
        XCTAssertNotEqual(one, two)
        let renewed = try UsageConsentReadApproval(market: one.market, endpoint: one.endpoint)
        XCTAssertNotEqual(one, renewed)
    }
    func testInvalidTimestampIsNotClampedOrPresentedAsARealDate() throws {
        let f = try UsageHistoryFixture()
        for time in [Int.max, 1_000_000_000_000_000] {
            let value = try f.decode(UsageHistoryFixture.record(1, time: time), as: UsageConsentEvidence.self)
            XCTAssertNoThrow(try value.validate()); XCTAssertNil(value.displayDate); XCTAssertEqual(value.occurredAt, time)
        }
        let zero = try f.decode(UsageHistoryFixture.record(1, time: 0), as: UsageConsentEvidence.self)
        XCTAssertEqual(zero.displayDate, Date(timeIntervalSince1970: 0))
        let negative = try f.decode(UsageHistoryFixture.record(1, time: -1), as: UsageConsentEvidence.self)
        XCTAssertThrowsError(try negative.validate()); XCTAssertNil(negative.displayDate)
    }
    func testMalformedDuplicateJSONAndOversizedResponseFailClosed() async throws {
        let f = try UsageHistoryFixture()
        for bytes in [Data(#"{"code":200,"code":200,"data":{}}"#.utf8), Data(repeating: 32, count: 8_388_609)] {
            f.wire.raw = bytes
            do { _ = try await f.service.history(); XCTFail() } catch { XCTAssertEqual(error as? UsageConsentReadFailure, .malformed) }
        }
    }
}
