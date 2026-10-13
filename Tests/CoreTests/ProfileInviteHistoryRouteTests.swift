import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileInviteHistoryRouteTests: XCTestCase {
    private let base = URL(string: "https://invite.example/native")!
    private func request(_ path: String = ProfileInviteHistoryReadRoute.invitations, page: String = "1", size: String = "100") throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: ["pageNum": page, "pageSize": size], token: "synthetic-invite", boundary: "InvitationBoundary")
    }
    private func context(account: Int = 81, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-invite") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: token))
    }
    func testOnlyExactTwoCanonicalExistingRequestsMatch() throws {
        for page in [1, 2, 100, Int.max] {
            let value = try XCTUnwrap(ProfileInviteHistoryReadRoute(request: request(page: String(page)), baseURL: base))
            XCTAssertEqual(value.path, ProfileInviteHistoryReadRoute.invitations); XCTAssertEqual(value.page, page)
        }
        let reward = try request(ProfileInviteHistoryReadRoute.rewards, size: "200")
        XCTAssertEqual(ProfileInviteHistoryReadRoute(request: reward, baseURL: base)?.page, 1)
    }
    func testNoOtherEndpointQueryFragmentMethodOrStreamMatches() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for path in ["api/user/public-info", "api/points/list", "api/user/points/statistics", "api/user/update", "api/user/invite_list/"] {
            var r = original; r.url = base.appendingPathComponent(path); invalid.append(r)
        }
        for suffix in ["?pageNum=1", "?member_id=82", "#x"] { var r = original; r.url = URL(string: r.url!.absoluteString + suffix); invalid.append(r) }
        for method in ["GET", "PUT", "DELETE"] { var r = original; r.httpMethod = method; invalid.append(r) }
        var streamed = original; streamed.httpBodyStream = InputStream(data: original.httpBody!); invalid.append(streamed)
        for r in invalid { XCTAssertNil(ProfileInviteHistoryReadRoute(request: r, baseURL: base)) }
    }
    func testPagesMustBeCanonicalPositiveIntegersAndRewardsStayFirstPage() throws {
        for page in ["0", "-1", "01", "+1", "1.0", " 1", "999999999999999999999999999"] {
            XCTAssertNil(ProfileInviteHistoryReadRoute(request: try request(page: page), baseURL: base))
        }
        XCTAssertNil(ProfileInviteHistoryReadRoute(request: try request(ProfileInviteHistoryReadRoute.rewards, page: "2", size: "200"), baseURL: base))
    }
    func testPageSizesCannotBorrowOtherHistoryShapes() throws {
        for size in ["20", "99", "101", "200"] { XCTAssertNil(ProfileInviteHistoryReadRoute(request: try request(size: size), baseURL: base)) }
        XCTAssertNil(ProfileInviteHistoryReadRoute(request: try request(ProfileInviteHistoryReadRoute.rewards, size: "100"), baseURL: base))
    }
    func testMemberOverrideExtraAndDuplicateFieldsAreRejected() throws {
        var r = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfileInviteHistoryReadRoute.invitations), fields: ["pageNum":"1", "pageSize":"100", "member_id":"82"], token: "synthetic-invite", boundary: "InvitationBoundary")
        XCTAssertNil(ProfileInviteHistoryReadRoute(request: r, baseURL: base))
        r = try request(); let part = "--InvitationBoundary\r\nContent-Disposition: form-data; name=\"pageNum\"\r\n\r\n1\r\n"
        r.httpBody = Data((part + String(data: r.httpBody!, encoding: .utf8)!).utf8)
        XCTAssertNil(ProfileInviteHistoryReadRoute(request: r, baseURL: base))
    }
    func testHeaderBoundaryAlternateEncodingAndTrailingBytesAreRejected() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for type in [nil, "application/json", "multipart/form-data; boundary=bad boundary"] as [String?] {
            var r = original; r.setValue(type, forHTTPHeaderField: "Content-Type"); invalid.append(r)
        }
        var r = original; r.setValue(nil, forHTTPHeaderField: "Accept"); invalid.append(r)
        r = original; r.httpBody!.append(0); invalid.append(r)
        r = original; r.httpBody = Data(); invalid.append(r)
        for r in invalid { XCTAssertNil(ProfileInviteHistoryReadRoute(request: r, baseURL: base)) }
    }
    func testApprovalMustAlreadyContainExactlyThisPurposeAndOwner() throws {
        let c = try context()
        for paths in [Set<String>(), [ProfileInviteHistoryReadRoute.invitations], ProfileInviteHistoryReadRoute.paths.union(["api/user/update"]), ["api/user/info", "api/points/list"]] {
            let grant = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: paths)
            XCTAssertThrowsError(try ProfileInviteHistoryReadAccess(context: c, approval: grant))
        }
        let wrong = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 82, paths: ProfileInviteHistoryReadRoute.paths)
        XCTAssertThrowsError(try ProfileInviteHistoryReadAccess(context: c, approval: wrong))
    }
    func testContextChangesAndIrreversibleRevocationRejectOldAccess() throws {
        let c = try context(), grant = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: ProfileInviteHistoryReadRoute.paths)
        let access = try ProfileInviteHistoryReadAccess(context: c, approval: grant)
        XCTAssertTrue(access.matches(c)); XCTAssertEqual(access.endpoints, grant)
        for changed in [try context(account: 82), try context(epoch: 2), try context(role: "merchant"), try context(token: "other-synthetic")] { XCTAssertFalse(access.matches(changed)) }
        access.revoke(); XCTAssertFalse(access.matches(c)); access.revoke(); XCTAssertFalse(access.matches(c))
    }
    func testOriginAndNamespaceAreBoundWithoutIssuingAnyReplacementGrant() throws {
        let c = try context()
        for grant in [try OperationEndpointApproval(baseURL: URL(string: "https://other.example/native")!, namespace: "synthetic", accountID: 81, paths: ProfileInviteHistoryReadRoute.paths), try OperationEndpointApproval(baseURL: base, namespace: "other", accountID: 81, paths: ProfileInviteHistoryReadRoute.paths)] {
            XCTAssertThrowsError(try ProfileInviteHistoryReadAccess(context: c, approval: grant))
        }
    }
}
