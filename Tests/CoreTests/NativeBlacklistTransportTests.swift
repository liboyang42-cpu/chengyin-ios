import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// AUTHORED, NOT_RUN. Synthetic .invalid transport records only; never uses URLSession.
@MainActor final class NativeBlacklistTransportTests: XCTestCase {
    private func context(account: Int = 2, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://blacklist.invalid/")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "blacklist-test", token: "synthetic-token", role: "player"))
    }
    private func approval(_ c: RuntimeDependencyContext, write: Bool = true, settle: Bool = true) throws -> NativeBlacklistApproval {
        var paths = NativeBlacklistApproval.readPaths
        if write { paths.insert(NativeBlacklistApproval.unblockPath) }; if settle { paths.insert(NativeBlacklistApproval.settlePath) }
        return try .init(endpoint: .init(baseURL: c.baseURL, namespace: c.session.namespace, accountID: c.session.accountID, paths: paths), expiresAt: Date().addingTimeInterval(600))
    }
    private func request(_ c: RuntimeDependencyContext, path: String = NativeBlacklistApproval.unblockPath) throws -> URLRequest {
        var r = URLRequest(url: c.baseURL.appendingPathComponent(path)); r.httpMethod = "POST"; r.httpShouldHandleCookies = false
        r.setValue(c.session.token, forHTTPHeaderField: "Authorization"); r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(path == NativeBlacklistApproval.settlePath ? "SELF_CONFIRMED_SETTLE" : "SELF_CONFIRMED_UNBLOCK", forHTTPHeaderField: "X-Audit-Log-Reason")
        r.httpBody = try NativeBlacklistCommand(peerID: 9, expectedBlockID: 30).body(); return r
    }
    func testDistinctWriteAndSettleGrantAndNoLegacyImFallback() throws {
        let c = try context(), read = try approval(c, write: false, settle: false), all = try approval(c), write = try request(c), settle = try request(c, path: NativeBlacklistApproval.settlePath)
        XCTAssertTrue(NativeBlacklistTransportPolicy.accepts(write, context: c, approval: all))
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(write, context: c, approval: read))
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(settle, context: c, approval: try approval(c, settle: false)))
        XCTAssertTrue(NativeBlacklistTransportPolicy.accepts(settle, context: c, approval: try approval(c, write: false)))
        var wrong = write; wrong.url = c.baseURL.appendingPathComponent("api/im/unblock")
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(wrong, context: c, approval: all))
    }
    func testExactOwnerReadFieldsRejectSmuggledOwnerRepeatedQueryAndMethod() throws {
        let c = try context(), a = try approval(c), id = UUID().uuidString.lowercased()
        var r = try request(c); r.httpMethod = "GET"; r.httpBody = nil; r.setValue(nil, forHTTPHeaderField: "X-Audit-Log-Reason")
        r.url = URL(string: "https://blacklist.invalid/api/native/blacklist/list?cursor=0")
        XCTAssertTrue(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
        for query in ["cursor=0&owner=8", "cursor=0&cursor=3", "cursor=-1", ""] {
            r.url = URL(string: "https://blacklist.invalid/api/native/blacklist/list?" + query)
            XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
        }
        r.url = URL(string: "https://blacklist.invalid/api/native/blacklist/receipt?peer_id=9&expected_block_id=30&request_id=\(id)")
        XCTAssertTrue(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a)); r.httpMethod = "POST"
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
    }
    func testCanonicalBodyRejectsBooleanFloatDuplicateOverflowAndUnknownFields() throws {
        let c = try context(), a = try approval(c), id = UUID().uuidString.lowercased()
        for raw in [
            "{\"expected_block_id\":true,\"peer_id\":9,\"request_id\":\"\(id)\"}",
            "{\"expected_block_id\":30.0,\"peer_id\":9,\"request_id\":\"\(id)\"}",
            "{\"expected_block_id\":30,\"peer_id\":8,\"peer_id\":9,\"request_id\":\"\(id)\"}",
            "{\"expected_block_id\":18446744073709551615,\"peer_id\":9,\"request_id\":\"\(id)\"}",
            "{\"expected_block_id\":30,\"peer_id\":9,\"request_id\":\"\(id)\",\"owner\":8}"
        ] {
            var r = try request(c); r.httpBody = Data(raw.utf8); XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
        }
    }
    func testOriginAccountCookieProxyExpiryAndAuditReasonClosed() throws {
        let c = try context(), a = try approval(c), good = try request(c)
        for url in ["https://other.invalid/api/native/blacklist/unblock", "https://u:p@blacklist.invalid/api/native/blacklist/unblock", "https://blacklist.invalid/api/native/blacklist/unblock?q=1", "https://blacklist.invalid/api/native/blacklist/unblock#f"] {
            var r = good; r.url = URL(string: url); XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
        }
        for header in ["Cookie", "Proxy-Authorization", "X-Audit-Log-Reason"] {
            var r = good; r.setValue("bad", forHTTPHeaderField: header); XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(r, context: c, approval: a))
        }
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(good, context: try context(account: 8), approval: a))
        XCTAssertFalse(NativeBlacklistTransportPolicy.accepts(good, context: c, approval: a, now: a.expiresAt))
    }
    final class Transport: HTTPTransport {
        var bytes = Data(); var requests: [URLRequest] = []; var duringSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); duringSend?(); return (bytes, 200) }
    }
    func testLate401FromOldOwnerCannotExpireReplacementAndRetiredGrantCannotRevive() async throws {
        let c = try context(), next = try context(account: 8), a = try approval(c), transport = Transport()
        var current: RuntimeDependencyContext? = c, grant: NativeBlacklistApproval? = a
        var expired = false
        let service = try NativeBlacklistService(context: c, approval: a, currentApproval: { grant }, transport: transport, current: { current }, onUnauthorized: { _ in expired = true })
        transport.bytes = Data(#"{"code":401}"#.utf8); transport.duringSend = { current = next }
        do { _ = try await service.unblock(.init(peerID: 9, expectedBlockID: 30)); XCTFail("late result accepted") }
        catch { XCTAssertEqual(error as? NativeBlacklistFailure, .unknown) }
        XCTAssertFalse(expired); current = c; grant = nil; XCTAssertFalse(service.isCurrent); grant = a; XCTAssertFalse(service.isCurrent)
    }
    func testReceiptMustMatchAllFrozenProofAndUnknownStaysUnknown() throws {
        let original = NativeBlacklistCommand(peerID: 9, expectedBlockID: 30)
        let wrong = NativeBlacklistReceipt(viewerID: 2, command: .init(requestID: original.requestID, peerID: 9, expectedBlockID: 31), outcome: "APPLIED", reason: "UNBLOCKED")
        XCTAssertFalse(wrong.matches(original, viewer: 2))
        XCTAssertTrue(NativeBlacklistReceipt(viewerID: 2, command: original, outcome: "UNKNOWN").matches(original, viewer: 2))
        XCTAssertFalse(NativeBlacklistReceipt(viewerID: 2, command: original, outcome: "APPLIED", reason: nil).matches(original, viewer: 2))
    }
    func testPageBoundariesDuplicatePeersAndCursorAreValidated() {
        let items = (1...50).reversed().map { NativeBlacklistItem(blockID: Int64($0), peerID: Int64($0 + 100), nickname: "") }
        XCTAssertTrue(NativeBlacklistPage(viewerID: 2, items: items, hasMore: true, nextCursor: 1).valid(viewer: 2, cursor: 0))
        XCTAssertFalse(NativeBlacklistPage(viewerID: 2, items: items, hasMore: true, nextCursor: 2).valid(viewer: 2, cursor: 0))
        XCTAssertFalse(NativeBlacklistPage(viewerID: 2, items: [items[0], items[0]]).valid(viewer: 2, cursor: 0))
        XCTAssertTrue(NativeBlacklistPage(viewerID: 2, items: []).valid(viewer: 2, cursor: 1))
        XCTAssertFalse(NativeBlacklistCurrent(viewerID: 2, peerID: 9, blocked: false, blockID: 3).valid(viewer: 2, peer: 9))
    }
}
