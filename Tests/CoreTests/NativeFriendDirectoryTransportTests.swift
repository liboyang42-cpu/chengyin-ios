import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeFriendDirectoryTransportTests: XCTestCase {
    private func context(account: Int = 2, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://directory.invalid/")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "directory-test", token: "synthetic-token", role: "player"))
    }
    private func approval(_ context: RuntimeDependencyContext) throws -> NativeFriendDirectoryApproval {
        try .init(endpoint: .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
              paths: NativeFriendDirectoryApproval.paths), expiresAt: Date().addingTimeInterval(600))
    }
    private func request(_ context: RuntimeDependencyContext, suffix: String = "?section=all&starred=false&limit=50") -> URLRequest {
        var value = URLRequest(url: URL(string: context.baseURL.absoluteString + "api/friend/directory" + suffix)!)
        value.httpMethod = "GET"; value.httpShouldHandleCookies = false
        value.setValue(context.session.token, forHTTPHeaderField: "Authorization"); value.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return value
    }
    func testValidDirectoryDetailAndExactOwnerScope() throws {
        let c = try context(), a = try approval(c)
        for suffix in ["?section=all&starred=false&limit=50", "?section=recent&starred=true&limit=50&group_id=0", "/detail?peer_id=9"] {
            XCTAssertTrue(NativeFriendDirectoryTransportPolicy.accepts(request(c, suffix: suffix), context: c, approval: a))
        }
        XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(request(c), context: try context(account: 3), approval: a))
        XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(request(c), context: c, approval: a, now: a.expiresAt))
    }
    func testUnknownFiltersDuplicateScopeAndViewerInjectionRejected() throws {
        let c = try context(), a = try approval(c)
        for suffix in ["?section=online&starred=false&limit=50", "?section=all&starred=true&limit=51", "?section=all&starred=true&limit=50&viewer_id=3", "?section=all&section=recent&starred=false&limit=50", "?section=all&starred=true&limit=50&group_id=-1", "/detail?peer_id=2", "/detail?peer_id=9&viewer_id=3"] {
            XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(request(c, suffix: suffix), context: c, approval: a))
        }
    }
    func testNoWritesCookiesAlternateOriginOrPermissionExpansion() throws {
        let c = try context(), a = try approval(c); let good = request(c)
        var bad = good; bad.httpMethod = "POST"; XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good; bad.httpShouldHandleCookies = true; XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(bad, context: c, approval: a))
        bad = good; bad.httpBody = Data(); XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(bad, context: c, approval: a))
        for target in ["https://other.invalid/api/friend/directory?section=all&starred=false&limit=50", "https://directory.invalid/api/im/start", "https://directory.invalid/api/friend/directory/detail?peer_id=9#x"] {
            bad = good; bad.url = URL(string: target); XCTAssertFalse(NativeFriendDirectoryTransportPolicy.accepts(bad, context: c, approval: a))
        }
        XCTAssertThrowsError(try NativeFriendDirectoryApproval(endpoint: .init(baseURL: c.baseURL, namespace: c.session.namespace, accountID: c.session.accountID,
            paths: NativeFriendDirectoryApproval.paths.union(["api/friend/remark"])), expiresAt: Date().addingTimeInterval(60)))
    }
    private final class Wire: HTTPTransport {
        var status = 200
        var bytes = Data()
        var held: CheckedContinuation<(Data, Int), Error>?
        var hold = false
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if hold { return try await withCheckedThrowingContinuation { held = $0 } }
            return (bytes, status)
        }
        func error(_ code: Int, _ message: String, http: Int = 200) {
            status = http
            bytes = try! JSONSerialization.data(withJSONObject: ["code": code, "msg": message])
        }
    }
    func testCanonicalDirectoryDenialsClearScopeWhilePeerMissingRemainsPeerOnly() async throws {
        let c = try context(), a = try approval(c), wire = Wire()
        let service = try NativeFriendDirectoryService(context: c, approval: a, currentApproval: { a }, transport: wire, current: { c })
        for (code, message) in [(404, "FRIEND_NOT_FOUND"), (403, "FORBIDDEN"), (503, "FRIEND_DIRECTORY_UNAVAILABLE"),
                                (503, "FRIEND_METADATA_UNAVAILABLE"), (503, "FRIEND_UNAVAILABLE"), (503, "FRIEND_DIRECTORY_BOUND_EXCEEDED")] {
            for status in [200, code] {
                wire.error(code, message, http: status)
                do { _ = try await service.page(filter: .init(), cursor: "cursor"); XCTFail("denial accepted") }
                catch { XCTAssertEqual(error as? NativeFriendDirectoryFailure, .readUnavailable) }
                XCTAssertTrue(service.isCurrent, "Unavailability is not a permanent local-grant revocation or a relationship deletion")
            }
        }
        wire.error(404, "FRIEND_NOT_FOUND")
        do { _ = try await service.detail(peerID: 9); XCTFail("missing peer accepted") }
        catch { XCTAssertEqual(error as? NativeFriendDirectoryFailure, .unavailablePeer) }
        wire.error(404, "DIRECTORY_GROUP_NOT_FOUND")
        do { _ = try await service.page(filter: .init(groupID: 4), cursor: "cursor"); XCTFail("missing group accepted") }
        catch { XCTAssertEqual(error as? NativeFriendDirectoryFailure, .missingGroup) }
    }
    func testUnknownGatewayFailureIsNotMisreportedAsDirectoryWithdrawal() async throws {
        let c = try context(), a = try approval(c), wire = Wire()
        let service = try NativeFriendDirectoryService(context: c, approval: a, currentApproval: { a }, transport: wire, current: { c })
        for status in [404, 500, 503] {
            wire.status = status; wire.bytes = Data("gateway unavailable".utf8)
            do { _ = try await service.page(filter: .init(), cursor: "cursor"); XCTFail("gateway error accepted") }
            catch { XCTAssertEqual(error as? NativeFriendFailure, .unknown) }
            XCTAssertTrue(service.isCurrent)
        }
    }
    func testLate401AfterDirectoryOrDetailDisappearanceCannotExpireCurrentAccount() async throws {
        for detailRoute in [false, true] {
            for status in [200, 401] {
                let c = try context(), a = try approval(c), wire = Wire(); wire.hold = true
                var expired = false
                let service = try NativeFriendDirectoryService(context: c, approval: a, currentApproval: { a }, transport: wire,
                    current: { c }, onUnauthorized: { _ in expired = true })
                let directory = NativeFriendDirectoryFlow(service: service)
                let detail = NativeFriendDirectoryDetailFlow(peerID: 9, service: service)
                let pending = Task { if detailRoute { await detail.load() } else { await directory.load() } }
                for _ in 0..<100 where wire.held == nil { await Task.yield() }
                XCTAssertNotNil(wire.held)
                if detailRoute { detail.invalidate() } else { directory.invalidate() }
                wire.held?.resume(returning: (Data(#"{"code":401}"#.utf8), status)); await pending.value
                XCTAssertFalse(expired); XCTAssertTrue(service.isCurrent)
                XCTAssertNil(detail.detail); XCTAssertTrue(directory.items.isEmpty)
            }
        }
    }
    func testCurrent401StillExpiresButReplacementAccountLate401DoesNot() async throws {
        for replace in [false, true] {
            let c = try context(), a = try approval(c), wire = Wire(); wire.hold = true
            var current: RuntimeDependencyContext? = c, expired = false
            let service = try NativeFriendDirectoryService(context: c, approval: a, currentApproval: { a }, transport: wire,
                current: { current }, onUnauthorized: { _ in expired = true })
            let pending = Task { try? await service.detail(peerID: 9) }
            for _ in 0..<100 where wire.held == nil { await Task.yield() }
            if replace { current = try context(account: 3, epoch: 2) }
            wire.held?.resume(returning: (Data(#"{"code":401}"#.utf8), 200)); _ = await pending.value
            XCTAssertEqual(expired, !replace); XCTAssertFalse(service.isCurrent)
        }
    }

}
