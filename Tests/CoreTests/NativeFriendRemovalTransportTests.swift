import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeFriendRemovalTransportTests: XCTestCase {
    private func context(account: Int = 2, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://removal.test/")!, role: "player", session: try .init(accountID: account, epoch: epoch, namespace: "removal-test", token: "synthetic-token", role: "player"))
    }
    private func approval(_ context: RuntimeDependencyContext, remove: Bool = true, settle: Bool = true) throws -> NativeFriendRemovalApproval {
        var paths = NativeFriendRemovalApproval.readPaths
        if remove { paths.insert(NativeFriendRemovalApproval.removePath) }; if settle { paths.insert(NativeFriendRemovalApproval.settlePath) }
        return try .init(endpoint: .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, paths: paths), expiresAt: Date().addingTimeInterval(600))
    }
    private func request(_ context: RuntimeDependencyContext, path: String = NativeFriendRemovalApproval.removePath, fields: [String: Any]? = nil) throws -> URLRequest {
        var value = URLRequest(url: context.baseURL.appendingPathComponent(path)); value.httpShouldHandleCookies = false; value.httpMethod = "POST"
        value.setValue(context.session.token, forHTTPHeaderField: "Authorization"); value.setValue("application/json", forHTTPHeaderField: "Content-Type")
        value.httpBody = try JSONSerialization.data(withJSONObject: fields ?? ["peer_id": 9, "expected_version": 3, "request_id": UUID().uuidString]); return value
    }
    func testRemoveAndSettleAreIndependentlyGrantedAndNeverReadOperations() throws {
        let c = try context(), remove = try request(c), settle = try request(c, path: NativeFriendRemovalApproval.settlePath)
        XCTAssertTrue(NativeFriendRemovalTransportPolicy.accepts(remove, context: c, approval: try approval(c, settle: false)))
        XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(settle, context: c, approval: try approval(c, settle: false)))
        XCTAssertTrue(NativeFriendRemovalTransportPolicy.accepts(settle, context: c, approval: try approval(c, remove: false)))
        XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(remove, context: c, approval: try approval(c, remove: false)))
        var wrong = settle; wrong.httpMethod = "GET"; XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(wrong, context: c, approval: try approval(c)))
    }
    func testOriginalReadRequiresVersionAndUuidAndRejectsSmuggledIdentity() throws {
        let c = try context(), a = try approval(c, remove: false, settle: false), id = UUID().uuidString
        var value = try request(c); value.httpMethod = "GET"; value.httpBody = nil
        value.url = URL(string: "https://removal.test/api/friend/removal/receipt?peer_id=9&expected_version=3&request_id=\(id)")
        XCTAssertTrue(NativeFriendRemovalTransportPolicy.accepts(value, context: c, approval: a))
        for query in ["peer_id=9&request_id=\(id)", "peer_id=9&expected_version=3&request_id=\(id)&viewer_id=2", "peer_id=9&expected_version=3&request_id=\(id)&peer_id=8"] {
            value.url = URL(string: "https://removal.test/api/friend/removal/receipt?" + query); XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(value, context: c, approval: a))
        }
    }
    func testBooleanFloatOverflowOrSelfCannotBecomeRemovalVersionOrPeer() throws {
        let c = try context(), a = try approval(c), id = UUID().uuidString
        for version: Any in [true, "3", 3.5, 0, -1, Int64.max] {
            XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(try request(c, fields: ["peer_id": 9, "expected_version": version, "request_id": id]), context: c, approval: a))
        }
        for peer: Any in [true, "9", 9.5, 0, -1, 2] {
            XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(try request(c, fields: ["peer_id": peer, "expected_version": 3, "request_id": id]), context: c, approval: a))
        }
    }
    func testOriginCookiesProxyMethodAndCrossAccountAreClosed() throws {
        let c = try context(), a = try approval(c), good = try request(c)
        for url in ["https://other.invalid/api/friend/remove", "https://removal.test/api/im/start", "https://removal.test/api/friend/remove?peer_id=8", "https://u:p@removal.test/api/friend/remove", "https://removal.test/api/friend/remove#other"] {
            var bad = good; bad.url = URL(string: url); XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(bad, context: c, approval: a))
        }
        var bad = good; bad.httpShouldHandleCookies = true; XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good; bad.setValue("wrong", forHTTPHeaderField: "Proxy-Authorization"); XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good; bad.setValue("wrong", forHTTPHeaderField: "Cookie"); XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(bad, context: c, approval: a))
        XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(good, context: try context(account: 8), approval: a))
        XCTAssertFalse(NativeFriendRemovalTransportPolicy.accepts(good, context: c, approval: a, now: a.expiresAt))
    }
    private final class Transport: HTTPTransport {
        var requests: [URLRequest] = []; var bytes = Data(); var duringSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); duringSend?(); return (bytes, 200) }
    }
    func testLateReplacement401CannotExpireNewOwnerAndGrantCannotReviveCapturedService() async throws {
        let c = try context(), replacement = try context(account: 8), a = try approval(c), transport = Transport()
        var current: RuntimeDependencyContext? = c; var grant: NativeFriendRemovalApproval? = a; var expired = false
        let service = try NativeFriendRemovalService(context: c, approval: a, currentApproval: { grant }, transport: transport, current: { current }, onUnauthorized: { _ in expired = true })
        transport.bytes = Data(#"{"code":401}"#.utf8); transport.duringSend = { current = replacement }
        do { _ = try await service.remove(.init(peerID: 9, expectedVersion: 3)); XCTFail("late account response accepted") } catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) }
        XCTAssertFalse(expired); current = c; grant = nil; XCTAssertFalse(service.isCurrent); grant = a; XCTAssertFalse(service.isCurrent)
    }
    func testMalformedOrWrongPayloadResponseRemainsUnknown() async throws {
        let c = try context(), a = try approval(c), transport = Transport(), command = NativeFriendRemovalCommand(peerID: 9, expectedVersion: 3)
        let service = try NativeFriendRemovalService(context: c, approval: a, currentApproval: { a }, transport: transport, current: { c })
        let wrong = NativeFriendRemovalReceipt(viewerID: 2, command: .init(requestID: command.requestID, peerID: 9, expectedVersion: 4), outcome: "APPLIED", reason: "REMOVED", removedVersion: 5)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wrong)); transport.bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
        do { _ = try await service.remove(command); XCTFail("wrong version accepted") } catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
