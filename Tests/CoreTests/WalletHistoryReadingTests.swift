import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class WalletHistoryReadingTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", realm: String = "realm-a", token: String = "synthetic-7", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: base, role: role,
            session: try .init(accountID: account, epoch: epoch, namespace: realm, token: token))
    }
    func testLeaseBindsExactOwnerEpochRoleRealmTokenAndExpiry() throws {
        let context = try context(), lease = try WalletHistoryReadApproval(context: context, expiresAt: Date().addingTimeInterval(60))
        XCTAssertTrue(lease.matches(context)); XCTAssertEqual(lease.endpoints.paths, WalletHistoryReadRoute.paths)
        for other in [try self.context(account: 8), try self.context(epoch: 2), try self.context(role: "merchant"), try self.context(realm: "realm-b"), try self.context(token: "rotated")] { XCTAssertFalse(lease.matches(other)) }
        XCTAssertFalse(lease.matches(context, now: lease.expiresAt)); lease.expireIfNeeded(now: lease.expiresAt)
        XCTAssertTrue(lease.isRevoked); XCTAssertFalse(lease.matches(context, now: Date.distantPast))
        let other = try WalletHistoryReadApproval(context: context, expiresAt: Date().addingTimeInterval(60)); XCTAssertNotEqual(other.revision, lease.revision)
        other.revoke(); XCTAssertFalse(other.matches(context))
        XCTAssertThrowsError(try WalletHistoryReadApproval(context: context, expiresAt: Date().addingTimeInterval(86_401)))
        XCTAssertThrowsError(try WalletHistoryReadApproval(context: context, expiresAt: Date.distantPast))
    }
    private func form(_ path: String, _ fields: [String: String]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-7", boundary: "bounded")
    }
    func testCanonicalFormsAndClientPageBounds() throws {
        for fields in [["pageNum":"1","pageSize":"20"], ["pageNum":"10000","pageSize":"20","eventType":"1"], ["pageNum":"2","pageSize":"20","eventType":"2"]] {
            XCTAssertNotNil(WalletHistoryReadRoute(request: try form("api/user/balance/list", fields), baseURL: base, accountID: 7))
        }
        for fields in [["pageNum":"10001","pageSize":"20"], ["pageNum":"1","pageSize":"21"], ["pageNum":"1","pageSize":"020"], ["pageNum":"+1","pageSize":"20"], ["pageNum":"1","pageSize":"20","eventType":"3"], ["member_id":"7","pageNum":"1","pageSize":"20"]] {
            XCTAssertNil(WalletHistoryReadRoute(request: try form("api/user/balance/list", fields), baseURL: base, accountID: 7))
        }
        for fields in [[:], ["change_type":"1"], ["change_type":"2"]] { XCTAssertNotNil(WalletHistoryReadRoute(request: try form("api/balance/list", fields), baseURL: base, accountID: 7)) }
        XCTAssertNotNil(WalletHistoryReadRoute(request: try form("api/points/list", [:]), baseURL: base, accountID: 7))
        XCTAssertNil(WalletHistoryReadRoute(request: try form("api/points/list", ["change_type":"1"]), baseURL: base, accountID: 7))
        XCTAssertNotNil(WalletHistoryReadRoute(request: try form("api/user/info", ["member_id":"7"]), baseURL: base, accountID: 7))
        XCTAssertNil(WalletHistoryReadRoute(request: try form("api/user/info", ["member_id":"8"]), baseURL: base, accountID: 7))
    }
    func testAlternateMultipartAndBodylessShapesFailClosed() throws {
        let valid = try form("api/user/info", ["member_id":"7"])
        let text = String(data: try XCTUnwrap(valid.httpBody), encoding: .utf8)!
        let field = "--bounded\r\nContent-Disposition: form-data; name=\"member_id\"\r\n\r\n7\r\n"
        for body in [field + field + "--bounded--\r\n", text + "extra", text.replacingOccurrences(of: "\r\n", with: "\n"), text.replacingOccurrences(of: "member_id", with: "member%5Fid"), text.replacingOccurrences(of: "\r\n7\r\n", with: "\r\n07\r\n")] {
            var request = valid; request.httpBody = Data(body.utf8); XCTAssertNil(WalletHistoryReadRoute(request: request, baseURL: base, accountID: 7))
        }
        var withdrawal = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/withdrawal/list"), fields: [:], token: "synthetic-7", includesBody: false)
        XCTAssertNotNil(WalletHistoryReadRoute(request: withdrawal, baseURL: base, accountID: 7))
        withdrawal.httpBody = Data(); XCTAssertNil(WalletHistoryReadRoute(request: withdrawal, baseURL: base, accountID: 7))
        var stages = URLRequest(url: base.appendingPathComponent("api/wallet/stages")); stages.httpMethod = "POST"
        stages.setValue("application/json", forHTTPHeaderField: "Content-Type"); stages.setValue("application/json", forHTTPHeaderField: "Accept")
        stages.httpBody = Data("{}".utf8); XCTAssertNotNil(WalletHistoryReadRoute(request: stages, baseURL: base, accountID: 7))
        for body in ["{ }", "{\"member_id\":7}", "[]", "null"] { stages.httpBody = Data(body.utf8); XCTAssertNil(WalletHistoryReadRoute(request: stages, baseURL: base, accountID: 7)) }
    }
}
