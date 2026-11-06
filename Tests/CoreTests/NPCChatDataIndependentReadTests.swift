import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class NPCIndependentWire: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200,"data":{"retentionDays":37,"retentionPolicy":" 原保存策略 ","records":[{"id":9007199254740993,"userId":7,"userMsg":" 原问题 ","npcReply":" 原答复 ","createTime":"2026-10-09 09:00:00","model":"internal","systemPrompt":"private"}]}}"#
    var status = 200
    var failure: Error?
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); after?(); if let failure { throw failure }; return (Data(body.utf8), status)
    }
}
@MainActor private final class NPCIndependentFixture {
    let context: RuntimeDependencyContext
    var current: RuntimeDependencyContext?
    let approval: NPCChatDataReadApproval
    var selected: NPCChatDataReadApproval?
    let wire = NPCIndependentWire()
    lazy var reader = makeReader()
    init() throws {
        context = .init(market: .china, baseURL: URL(string: "https://npc-read.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "npc-independent-synthetic", token: "synthetic-npc-read-token", role: "player"))
        current = context; approval = try .init(context: context, expiresAt: Date().addingTimeInterval(600)); selected = approval
    }
    func makeReader() -> NPCChatDataReader {
        .init(approval: approval, transport: wire, current: { [unowned self] in current }, selected: { [unowned self] _ in selected })
    }
    func request() -> URLRequest {
        var r = URLRequest(url: context.baseURL.appendingPathComponent(NPCChatData.path)); r.httpMethod = "GET"; r.httpShouldHandleCookies = false
        r.setValue("application/json", forHTTPHeaderField: "Accept"); r.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        r.setValue("no-store", forHTTPHeaderField: "Cache-Control"); r.setValue("no-cache", forHTTPHeaderField: "Pragma"); return r
    }
}
/// New source specimens only. Existing DTO/coordinator/view tests and deletion contracts are unchanged.
@MainActor final class NPCChatDataIndependentReadTests: XCTestCase {
    func testOriginalGETKeepsPreciseIDsTextPolicyAndSourceTime() async throws {
        let f = try NPCIndependentFixture(), value = try await f.reader.read(f.reader.session)
        XCTAssertEqual(value.records.first?.id, "9007199254740993"); XCTAssertEqual(value.records.first?.userMessage, " 原问题 ")
        XCTAssertEqual(value.records.first?.npcReply, " 原答复 "); XCTAssertEqual(value.retentionPolicy, " 原保存策略 ")
        XCTAssertEqual(value.retentionDays, 37); XCTAssertEqual(value.records.first?.sourceTime, "2026-10-09 09:00:00")
        let request = try XCTUnwrap(f.wire.requests.first); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertNil(request.url?.query); XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
    }
    func testCoordinatorNeedsNoConsentJournalOrDeletionService() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator()
        flow.appear(active: true)
        await flow.load(); XCTAssertNotNil(flow.data)
        XCTAssertFalse(flow.canRequestDeletion); flow.requestDeletion()
        await flow.confirmDeletion()
        XCTAssertEqual(flow.deletion, .idle); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testClosedCoordinatorAndBackgroundDoNotReadAutomatically() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator()
        await flow.load(); XCTAssertTrue(f.wire.requests.isEmpty)
        flow.appear(active: true)
        await flow.load(); XCTAssertNotNil(flow.data)
        flow.suspend(); flow.foreground(); XCTAssertNil(flow.data); XCTAssertEqual(f.wire.requests.count, 1)
        await flow.load(); XCTAssertEqual(f.wire.requests.count, 2)
        flow.invalidate()
        await flow.load(); XCTAssertEqual(f.wire.requests.count, 2)
    }
    func testLocalSearchUsesOnlyVisibleQuestionAndReplyWithoutNetwork() async throws {
        let f = try NPCIndependentFixture(), value = try await f.reader.read(f.reader.session), row = try XCTUnwrap(value.records.first)
        XCTAssertTrue(row.matches("问题")); XCTAssertTrue(row.matches("答复")); XCTAssertFalse(row.matches("private")); XCTAssertFalse(row.matches("internal"))
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testNoSelectedLeasePreventsDispatch() async throws {
        let f = try NPCIndependentFixture(); f.selected = nil
        XCTAssertFalse(f.reader.canRead(f.reader.session))
        do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .unavailable) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testWrongComplianceSessionCannotBorrowReader() async throws {
        let f = try NPCIndependentFixture(), other = ComplianceSession(accountID: 8, epoch: 1, market: "CN", namespace: "npc-independent-synthetic")
        do { _ = try await f.reader.read(other); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .unavailable) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testAnotherOwnersRecordsAndDuplicatesStillRejectWholeProjection() async throws {
        for body in [#"{"code":200,"data":{"records":[{"id":1,"userId":8}]}}"#, #"{"code":200,"data":{"records":[{"id":1,"userId":7},{"id":"1","userId":7}]}}"#] {
            let f = try NPCIndependentFixture(); f.wire.body = body
            do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .malformed) }
        }
    }
    func testMissingPolicyDoesNotInventDefaultRetention() async throws {
        let f = try NPCIndependentFixture(); f.wire.body = #"{"code":200,"data":{"records":[]}}"#
        let value = try await f.reader.read(f.reader.session); XCTAssertNil(value.retentionDays); XCTAssertNil(value.retentionPolicy); XCTAssertTrue(value.records.isEmpty)
    }
    func testStrictSingleRouteRejectsQueriesWritesAndOtherNPCFeatures() throws {
        let f = try NPCIndependentFixture(), good = f.request(); XCTAssertTrue(NPCChatDataReadRoute.accepts(good, baseURL: f.context.baseURL))
        for path in ["api/ai/npc/chat", "api/ai/npc/merchant-chat", "api/ai/npc/chat/data/delete", "api/ai/npc/chat/data/delete-request/result", "api/usage-consents/mine"] {
            var r = good; r.url = f.context.baseURL.appendingPathComponent(path); XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
        }
        for suffix in ["?userId=7", "?pageNum=1", "?requestId=old", "?", "#private"] {
            var r = good; r.url = URL(string: good.url!.absoluteString + suffix); XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
        }
        var r = good; r.httpMethod = "POST"; XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
        r = good; r.httpBody = Data(); XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
        r = good; r.httpShouldHandleCookies = true; XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
        r = good; r.setValue("x", forHTTPHeaderField: "Cookie"); XCTAssertFalse(NPCChatDataReadRoute.accepts(r, baseURL: f.context.baseURL))
    }
    func testScopedTransportRequiresExactCredentialAndNoStore() async throws {
        let f = try NPCIndependentFixture(), scoped = NPCChatDataReadScopedTransport(approval: f.approval, underlying: f.wire, current: { f.current }, stillSelected: { true })
        for header in ["Authorization", "Accept", "Cache-Control", "Pragma"] {
            var request = f.request(); request.setValue("wrong", forHTTPHeaderField: header)
            do { _ = try await scoped.send(request); XCTFail(header) } catch { }
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRoleCredentialEpochAndNamespaceChangeInvalidateImmediately() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator(); flow.appear(active: true); await flow.load()
        let variants: [(Int, UInt64, String, String, String)] = [(8,1,"npc-independent-synthetic","synthetic-npc-read-token","player"),(7,2,"npc-independent-synthetic","synthetic-npc-read-token","player"),(7,1,"other","synthetic-npc-read-token","player"),(7,1,"npc-independent-synthetic","new-token","player"),(7,1,"npc-independent-synthetic","synthetic-npc-read-token","merchant")]
        for (account, epoch, namespace, token, role) in variants {
            f.current = .init(market: .china, baseURL: f.context.baseURL, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role))
            XCTAssertNil(flow.data); XCTAssertFalse(flow.canLoad)
        }
    }
    func testRevocationRetiresAllReaderPresentations() async throws {
        let f = try NPCIndependentFixture(), a = f.reader.makeCoordinator(), b = f.reader.makeCoordinator()
        a.appear(active: true)
        await a.load(); b.appear(active: true)
        await b.load(); XCTAssertNotNil(a.data); XCTAssertNotNil(b.data)
        f.reader.retire(); XCTAssertNil(a.data); XCTAssertNil(b.data); XCTAssertFalse(a.canLoad); XCTAssertFalse(b.canLoad)
    }
    func testSourceReplacementCannotReuseOldReader() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator(); flow.appear(active: true); await flow.load()
        f.selected = try .init(context: f.context, expiresAt: Date().addingTimeInterval(600))
        XCTAssertNil(flow.data); XCTAssertFalse(f.reader.isCurrent); f.wire.requests = []
        await flow.load(); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testLateIdentityChangeCannotPublishPrivateText() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator(); flow.appear(active: true); f.wire.after = { f.current = nil }
        await flow.load(); XCTAssertNil(flow.data); XCTAssertNotEqual(flow.phase, .loaded)
    }
    func testCurrentHTTPAndBusinessDenialsInvalidateSharedLease() async throws {
        for status in [401,403] {
            for business in [false,true] {
                let f = try NPCIndependentFixture(), a = f.reader.makeCoordinator(), other = f.makeReader(), b = other.makeCoordinator()
                a.appear(active: true); await a.load(); b.appear(active: true); await b.load()
                if business { f.wire.body = "{\"code\":\(status),\"data\":\"wrong shape\"}" } else { f.wire.status = status; f.wire.body = "private invalid body" }
                do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, status == 401 ? .signedOut : .rejected) }
                XCTAssertTrue(f.approval.revoked); XCTAssertNil(a.data); XCTAssertNil(b.data)
            }
        }
    }
    func testLateDenialDoesNotRevokeNewIdentity() async throws {
        let f = try NPCIndependentFixture(); f.wire.status = 401; f.wire.after = { f.current = nil }
        do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .staleSession) }
        XCTAssertFalse(f.approval.revoked)
    }
    func testCancellationHasNoRequestOrLateRevokeEffects() async throws {
        let f = try NPCIndependentFixture()
        await Task { withUnsafeCurrentTask { $0?.cancel() }; do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertTrue(error is CancellationError) } }.value
        XCTAssertTrue(f.wire.requests.isEmpty)
        f.wire.failure = APIError.unauthorized; f.wire.after = { withUnsafeCurrentTask { $0?.cancel() } }
        await Task { do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertTrue(error is CancellationError) } }.value
        XCTAssertFalse(f.approval.revoked)
    }
    func testDuplicateJSONAndOversizedBodyFailRatherThanTruncate() async throws {
        let f = try NPCIndependentFixture(); f.wire.body = #"{"code":200,"code":200,"data":{"records":[]}}"#
        do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .malformed) }
        f.wire.body = String(repeating: "x", count: 8_388_609)
        do { _ = try await f.reader.read(f.reader.session); XCTFail() } catch { XCTAssertEqual(error as? NPCChatDataFailure, .tooLarge) }
    }
    func testFailedReloadDoesNotPresentNoRecordsSuccess() async throws {
        let f = try NPCIndependentFixture(), flow = f.reader.makeCoordinator(); flow.appear(active: true)
        await flow.load(); XCTAssertNotNil(flow.data)
        f.wire.status = 500
        await flow.load(); XCTAssertNil(flow.data); XCTAssertEqual(flow.phase, .unavailable); XCTAssertEqual(flow.failure, .failed)
    }
    func testExpiredAndPartialRoleLeaseCannotBeConstructed() throws {
        let f = try NPCIndependentFixture()
        XCTAssertThrowsError(try NPCChatDataReadApproval(context: f.context, expiresAt: .distantPast))
        let wrong = RuntimeDependencyContext(market: .china, baseURL: f.context.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "npc-independent-synthetic", token: "synthetic-npc-read-token", role: "merchant"))
        XCTAssertFalse(f.approval.matches(wrong)); XCTAssertThrowsError(try NPCChatDataReadApproval(context: wrong, expiresAt: Date().addingTimeInterval(600)))
    }
}
