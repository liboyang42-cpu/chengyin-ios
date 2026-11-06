import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ScoreC6Wire: HTTPTransport {
    var requests: [URLRequest] = []
    var after: (() -> Void)?
    var payload: (URLRequest) -> [String: Any] = { request in
        if request.url?.lastPathComponent == "mine" { return ["rows": [ScoreC6Fixture.row()], "total": 1] }
        if request.url?.lastPathComponent == "reputation" { return ["status": "normal"] }
        return ScoreC6Fixture.detail()
    }
    var raw: Data?
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let body = try raw ?? JSONSerialization.data(withJSONObject: ["code": 200, "data": payload(request)])
        after?(); return (body, status)
    }
}
@MainActor private final class ScoreC6Fixture {
    let context: RuntimeDependencyContext
    var current: RuntimeDependencyContext?
    let approval: MemberScoreListApproval
    let wire = ScoreC6Wire()
    lazy var client = MemberScoreAppealListClient(approval: approval, transport: wire, current: { [unowned self] in current }, selected: { [unowned self] _ in approval })
    init(capabilities: Set<MemberScoreReadCapability> = [.list, .sessionDetail, .reputation]) throws {
        context = .init(market: .china, baseURL: URL(string: "https://score-read.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "score-synthetic", token: "score-synthetic-token", role: "player"))
        current = context
        approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600), capabilities: capabilities)
    }
    static func row(id: Int64 = 1, kind: String = "appeal", status: String = "open") -> [String: Any] {
        ["id": id, "sessionId": 2, "topicId": 3, "kind": kind, "status": status, "topicName": "Synthetic", "nodeId": NSNull(), "createTime": "2026-10-28 21:10:00"]
    }
    static func detail() -> [String: Any] {
        ["sessionId": "2", "topicId": "3", "totalCenti": "-9007199254740993", "appeals": [["id": "1", "sessionId": "2", "memberId": "7", "status": 1, "resolutionNote": " 原来源理由 " ]], "disputes": []]
    }
    func request(_ route: MemberScoreReadRoute) -> URLRequest {
        var parts = URLComponents(url: context.baseURL.appendingPathComponent(route.path), resolvingAgainstBaseURL: false)!
        parts.queryItems = route.query.isEmpty ? nil : route.query
        var r = URLRequest(url: parts.url!); r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Accept"); r.setValue(context.session.token, forHTTPHeaderField: "Authorization"); return r
    }
    func decodeRow(_ row: [String: Any]) throws -> MemberScoreAppealRow { try JSONDecoder().decode(MemberScoreAppealRow.self, from: JSONSerialization.data(withJSONObject: row)) }
}

/// Source-only specimens for c6. No original fixture or assertion is changed.
@MainActor final class MemberScoreAppealC6ReadJourneyTests: XCTestCase {
    func testRealC6PageNumLowercaseAndStringDetailPreserveExactInteger() async throws {
        let f = try ScoreC6Fixture(); f.wire.payload = { r in r.url?.lastPathComponent == "mine" ? ["rows": [ScoreC6Fixture.row(status: "accepted")], "total": 51] : ScoreC6Fixture.detail() }; let page = try await f.client.list(page: 2, filter: .decided)
        XCTAssertEqual(page.total, 51); XCTAssertEqual(page.rows[0].status, .accepted)
        let query = URLComponents(url: try XCTUnwrap(f.wire.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.map(\.name), ["pageNum", "pageSize", "status"])
        XCTAssertEqual(query?.map(\.value), ["2", "50", "closed"])
        let detail = try await f.client.detail(page.rows[0]); XCTAssertEqual(detail.totalCenti, -9007199254740993)
        XCTAssertEqual(detail.status, .accepted); XCTAssertEqual(detail.resolutionNote, " 原来源理由 ")
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET", "GET"])
    }
    func testNullableLeftJoinContextDoesNotDestroyListOrInventNavigation() async throws {
        let f = try ScoreC6Fixture(); var row = ScoreC6Fixture.row(); row["sessionId"] = NSNull(); row["topicId"] = NSNull(); row["topicName"] = NSNull()
        f.wire.payload = { _ in ["rows": [row], "total": 1] }
        let value = try await f.client.list().rows[0]; XCTAssertFalse(value.canReadSession)
        do { _ = try await f.client.detail(value); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .unavailable) }
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testOldUnappliedProducerShapeIsRejected() async throws {
        let f = try ScoreC6Fixture(); f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row(kind: "APPEAL", status: "OPEN")], "page": 1, "hasMore": false] }
        do { _ = try await f.client.list(); XCTFail() } catch { }
    }
    func testDuplicateRecordKeyRejectedButTwoKindsWithSameIdRemainDistinct() async throws {
        let f = try ScoreC6Fixture(); f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row(), ScoreC6Fixture.row(kind: "dispute")], "total": 2] }
        let page = try await f.client.list(); XCTAssertEqual(Set(page.rows.map(\.id)).count, 2)
        f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row(), ScoreC6Fixture.row()], "total": 2] }
        do { _ = try await f.client.list(); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .malformed) }
    }
    func testPageBoundsAndNoInventedAtomicTotalConstraint() async throws {
        let f = try ScoreC6Fixture(); f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row()], "total": 0] }
        let page = try await f.client.list(); XCTAssertEqual(page.rows.count, 1)
        f.wire.requests = []; do { _ = try await f.client.list(page: MemberScoreReadRoute.maximumPage + 1); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testServerFilterMismatchCannotBePresentedAsResolved() async throws {
        let f = try ScoreC6Fixture()
        do { _ = try await f.client.list(filter: .decided); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .malformed) }
    }
    func testDetailRejectsWrongOwnerSessionTopicAndDuplicateOriginal() async throws {
        let f = try ScoreC6Fixture(), row = try f.decodeRow(ScoreC6Fixture.row())
        for key in ["memberId", "sessionId"] {
            var raw = ScoreC6Fixture.detail(); var record = (raw["appeals"] as! [[String: Any]])[0]; record[key] = "999"; raw["appeals"] = [record]
            f.wire.payload = { _ in raw }; do { _ = try await f.client.detail(row); XCTFail(key) } catch { }
        }
        var raw = ScoreC6Fixture.detail(); raw["topicId"] = "9"; f.wire.payload = { _ in raw }
        do { _ = try await f.client.detail(row); XCTFail() } catch { }
        raw = ScoreC6Fixture.detail(); raw["appeals"] = (raw["appeals"] as! [[String: Any]]) + (raw["appeals"] as! [[String: Any]])
        f.wire.payload = { _ in raw }; do { _ = try await f.client.detail(row); XCTFail() } catch { }
    }
    func testWireStringIntegersRejectRoundingOverflowAndNonCanonicalText() async throws {
        let f = try ScoreC6Fixture(), row = try f.decodeRow(ScoreC6Fixture.row())
        let bad: [Any] = [9007199254740992, "9007199254740993.0", "1e3", "01", "+1", "-0", "9223372036854775808"]
        for value in bad { var raw = ScoreC6Fixture.detail(); raw["totalCenti"] = value; f.wire.payload = { _ in raw }; do { _ = try await f.client.detail(row); XCTFail(String(describing: value)) } catch { } }
    }
    func testStrictReadRouteRejectsOldPageOwnerInjectionAndWrites() throws {
        let f = try ScoreC6Fixture(); let good = f.request(.list(page: 1, filter: .all))
        XCTAssertNotNil(MemberScoreReadRoute(request: good, baseURL: f.context.baseURL))
        for query in ["page=1&pageSize=50", "pageNum=01&pageSize=50", "pageNum=1&pageSize=50&memberId=9", "pageNum=1&pageSize=50&status=all", "pageNum=1&pageNum=2&pageSize=50"] {
            var r = good; r.url = URL(string: f.context.baseURL.appendingPathComponent("api/orient/scoring/mine").absoluteString + "?" + query)
            XCTAssertNil(MemberScoreReadRoute(request: r, baseURL: f.context.baseURL))
        }
        for path in ["api/orient/scoring/appeal", "api/orient/scoring/dispute", "api/orient/scoring/session/2/sync", "api/orient/scoring/receipt", "api/orient/scoring/original-request"] {
            var r = good; r.url = f.context.baseURL.appendingPathComponent(path); XCTAssertNil(MemberScoreReadRoute(request: r, baseURL: f.context.baseURL))
        }
        var r = good; r.httpBody = Data("{}".utf8); XCTAssertNil(MemberScoreReadRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpMethod = "POST"; XCTAssertNil(MemberScoreReadRoute(request: r, baseURL: f.context.baseURL))
        r = good; r.httpShouldHandleCookies = true; XCTAssertNil(MemberScoreReadRoute(request: r, baseURL: f.context.baseURL))
    }
    func testDefaultListLeaseDoesNotIncludeReputationOrWrites() async throws {
        let f = try ScoreC6Fixture(capabilities: [.list, .sessionDetail])
        do { _ = try await f.client.reputation(); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .disabled) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReputationFailureNeverBecomesNormalAndDoesNotEraseList() async throws {
        let f = try ScoreC6Fixture(); f.wire.payload = { request in request.url?.lastPathComponent == "reputation" ? ["status": "UNKNOWN"] : ["rows": [ScoreC6Fixture.row()], "total": 1] }
        let flow = f.client.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(flow.rows.count, 1); XCTAssertNil(flow.reputation); XCTAssertTrue(flow.reputationUnavailable)
    }
    func testAllKnownReputationValuesRemainExplicit() async throws {
        let f = try ScoreC6Fixture()
        for state in [MemberScoreReputation.normal, .restricted] { f.wire.payload = { _ in ["status": state.rawValue] }; let actual = try await f.client.reputation(); XCTAssertEqual(actual, state) }
    }
    func testCancelledQueuedReadHasNoEffects() async throws {
        let f = try ScoreC6Fixture(), flow = f.client.makeCoordinator(), owner = flow.beginList(), intent = try XCTUnwrap(flow.capture(owner))
        await Task { withUnsafeCurrentTask { $0?.cancel() }; await flow.loadList(intent: intent) }.value
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(flow.loaded); XCTAssertFalse(flow.busy)
    }
    func testDepartureAndOldOwnerCannotStartOrRetireReplacement() async throws {
        let f = try ScoreC6Fixture(), flow = f.client.makeCoordinator(), old = flow.beginList(), intent = try XCTUnwrap(flow.capture(old))
        flow.end(old); let new = flow.beginList(filter: .active); flow.end(old)
        await flow.loadList(intent: intent); XCTAssertTrue(f.wire.requests.isEmpty)
        await flow.loadList(intent: try XCTUnwrap(flow.capture(new))); XCTAssertTrue(flow.loaded)
    }
    func testReadIntentConsumedOnceEvenAfterCompletion() async throws {
        let f = try ScoreC6Fixture(capabilities: [.list]), flow = f.client.makeCoordinator(), owner = flow.beginList(), intent = try XCTUnwrap(flow.capture(owner))
        await flow.loadList(intent: intent); await flow.loadList(intent: intent); XCTAssertEqual(f.wire.requests.count, 1)
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(f.wire.requests.count, 2)
    }
    func testLatePageAfterCloseCannotReviveDisplay() async throws {
        let f = try ScoreC6Fixture(), flow = f.client.makeCoordinator(), owner = flow.beginList()
        f.wire.after = { flow.end(owner) }; await flow.loadList(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertTrue(flow.rows.isEmpty); XCTAssertNil(flow.reputation); XCTAssertFalse(flow.loaded)
    }
    func testClientRetirementClearsBothListAndIndependentDetailOwner() async throws {
        let f = try ScoreC6Fixture(), list = f.client.makeCoordinator(), listOwner = list.beginList()
        await list.loadList(intent: try XCTUnwrap(list.capture(listOwner)))
        let row = try XCTUnwrap(list.rows.first), selected = try XCTUnwrap(list.select(row, intent: try XCTUnwrap(list.capture(listOwner))))
        let detail = selected.client.makeCoordinator(), detailOwner = detail.beginDetail(row)
        list.end(listOwner); await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner))); XCTAssertNotNil(detail.detail)
        f.client.retire(); XCTAssertNil(detail.detail); XCTAssertNil(detail.detailRow); XCTAssertTrue(list.rows.isEmpty)
    }
    func testContextChangeImmediatelyHidesCacheWithoutUICallback() async throws {
        let f = try ScoreC6Fixture(), flow = f.client.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertFalse(flow.rows.isEmpty)
        f.current = nil; XCTAssertTrue(flow.rows.isEmpty); XCTAssertNil(flow.reputation); XCTAssertFalse(flow.loaded)
    }
    func testFullSessionRoleAndCredentialScopeIsRequired() throws {
        let f = try ScoreC6Fixture()
        let wrongRole = RuntimeDependencyContext(market: .china, baseURL: f.context.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "score-synthetic", token: "score-synthetic-token", role: "merchant"))
        XCTAssertFalse(f.approval.matches(wrongRole))
        XCTAssertThrowsError(try MemberScoreListApproval(context: wrongRole, expiresAt: Date().addingTimeInterval(100)))
        XCTAssertThrowsError(try MemberScoreListApproval(context: f.context, expiresAt: .distantPast))
    }
    func testScopedTransportRejectsUnapprovedReadsAndWrongToken() async throws {
        let f = try ScoreC6Fixture(capabilities: [.list]), transport = MemberScoreAppealScopedTransport(approval: f.approval, underlying: f.wire, current: { f.current }, stillSelected: { true })
        do { _ = try await transport.send(f.request(.reputation)); XCTFail() } catch { }
        var r = f.request(.list(page: 1, filter: .all)); r.setValue("other", forHTTPHeaderField: "Authorization")
        do { _ = try await transport.send(r); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRevocationDuringResponseRejectsLateEvidence() async throws {
        let f = try ScoreC6Fixture(); f.wire.after = { f.approval.revoke() }
        do { _ = try await f.client.list(); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .stale) }
    }
    func testMalformedJSONAndOversizeAreNotEmptySuccess() async throws {
        let f = try ScoreC6Fixture()
        for raw in [Data(#"{"code":200,"code":200,"data":{"rows":[],"total":0}}"#.utf8), Data(repeating: 32, count: 8_388_609)] {
            f.wire.raw = raw; do { _ = try await f.client.list(); XCTFail() } catch { XCTAssertEqual(error as? MemberScoreListFailure, .malformed) }
        }
    }
    func testOffsetRepeatUpdatesSameRecordAndUsesRealTotal() async throws {
        let f = try ScoreC6Fixture(capabilities: [.list]), flow = f.client.makeCoordinator(), owner = flow.beginList()
        f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row()], "total": 51] }
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertTrue(flow.hasMore)
        f.wire.payload = { _ in ["rows": [ScoreC6Fixture.row(status: "accepted"), ScoreC6Fixture.row(id: 2)], "total": 2] }
        await flow.loadList(more: true, intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(flow.rows.count, 2); XCTAssertEqual(flow.rows.first?.status, .accepted); XCTAssertFalse(flow.hasMore)
    }
}
