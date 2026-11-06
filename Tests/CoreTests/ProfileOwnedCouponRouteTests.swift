import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileOwnedCouponRouteTests: XCTestCase {
    private let base = URL(string: "https://coupon.example/native")!
    private func request(_ fields: [String: String] = [:]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfileOwnedCouponReadRoute.path), fields: fields, token: "synthetic-coupon", boundary: "CouponBoundary")
    }
    private func context(account: Int = 81, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-coupon", origin: String = "https://coupon.example/native", namespace: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: origin)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func testExactlyEmptyOrNonemptyKeywordPreservesUnicodeAndWhitespace() throws {
        let empty = try XCTUnwrap(ProfileOwnedCouponReadRoute(request: request(), baseURL: base)); XCTAssertNil(empty.keyword)
        for value in ["咖啡", " a b ", "line\nnext"] {
            let route = try XCTUnwrap(ProfileOwnedCouponReadRoute(request: request(["keyword": value]), baseURL: base))
            XCTAssertEqual(route.keyword, value)
        }
        XCTAssertNil(ProfileOwnedCouponReadRoute(request: try request(["keyword": ""]), baseURL: base))
    }
    func testMemberOverridePaginationExtraAndDuplicatePartsReject() throws {
        for fields in [["member_id":"81"], ["pageNum":"1"], ["pageSize":"100"], ["keyword":"coffee", "id":"1"], ["memberId":"81"]] {
            XCTAssertNil(ProfileOwnedCouponReadRoute(request: try request(fields), baseURL: base))
        }
        var duplicate = try request(["keyword":"x"])
        duplicate.httpBody = Data(("--CouponBoundary\r\nContent-Disposition: form-data; name=\"keyword\"\r\n\r\ny\r\n" + String(data: duplicate.httpBody!, encoding: .utf8)!).utf8)
        XCTAssertNil(ProfileOwnedCouponReadRoute(request: duplicate, baseURL: base))
    }
    func testWrongPathOriginQueryFragmentMethodAndStreamReject() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for path in ["api/coupon/qr-token", "api/coupon/receive", "api/coupon/mypublishlist", "api/topic/like_list", "api/coupon/myrecvlist/"] {
            var r = original; r.url = base.appendingPathComponent(path); invalid.append(r)
        }
        for suffix in ["?keyword=x", "?member_id=81", "#fragment"] { var r = original; r.url = URL(string: r.url!.absoluteString + suffix); invalid.append(r) }
        var r = original; r.url = URL(string: "https://other.example/native/api/coupon/myrecvlist"); invalid.append(r)
        for method in ["GET", "PUT", "DELETE"] { var r = original; r.httpMethod = method; invalid.append(r) }
        r = original; r.httpBodyStream = InputStream(data: original.httpBody!); invalid.append(r)
        for r in invalid { XCTAssertNil(ProfileOwnedCouponReadRoute(request: r, baseURL: base)) }
    }
    func testWrongContentTypeAcceptBoundaryAndTrailingBytesReject() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for type in [nil, "application/json", "multipart/form-data; boundary=bad boundary"] as [String?] {
            var r = original; r.setValue(type, forHTTPHeaderField: "Content-Type"); invalid.append(r)
        }
        var r = original; r.setValue(nil, forHTTPHeaderField: "Accept"); invalid.append(r)
        r = original; r.httpBody!.append(0); invalid.append(r)
        r = original; r.httpBody = Data(); invalid.append(r)
        r = original; r.httpBody = nil; invalid.append(r)
        for r in invalid { XCTAssertNil(ProfileOwnedCouponReadRoute(request: r, baseURL: base)) }
        XCTAssertNil(ProfileOwnedCouponReadRoute(request: try request(["keyword": String(repeating: "x", count: 32_768)]), baseURL: base))
    }
    func testOnlyExistingExactPurposeApprovalIsConsumed() throws {
        let c = try context()
        for paths in [Set<String>(), ["api/coupon/qr-token"], ["api/coupon/mypublishlist"], ProfileOwnedCouponReadRoute.paths.union(["api/coupon/receive"])] {
            let grant = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: paths)
            XCTAssertThrowsError(try ProfileOwnedCouponReadAccess(context: c, approval: grant))
        }
        let wrong = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 82, paths: ProfileOwnedCouponReadRoute.paths)
        XCTAssertThrowsError(try ProfileOwnedCouponReadAccess(context: c, approval: wrong))
    }
    func testAccessBindsAccountEpochRoleTokenOriginNamespaceAndRevokesIrreversibly() throws {
        let c = try context(), grant = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: ProfileOwnedCouponReadRoute.paths)
        let access = try ProfileOwnedCouponReadAccess(context: c, approval: grant)
        XCTAssertTrue(access.matches(c)); XCTAssertEqual(access.endpoints, grant)
        for changed in [try context(account: 82), try context(epoch: 2), try context(role: "merchant"), try context(token: "other"), try context(origin: "https://other.example/native"), try context(namespace: "other")] { XCTAssertFalse(access.matches(changed)) }
        access.revoke(); XCTAssertFalse(access.matches(c)); access.revoke(); XCTAssertFalse(access.matches(c))
    }
    func testSuccessfulArrayMustBeCurrentOwnerAndPositiveUniqueHistoryIdentity() throws {
        let route = try XCTUnwrap(ProfileOwnedCouponReadRoute(request: request(), baseURL: base))
        for data in [#"{"code":200,"data":[]}"#, #"{"code":200,"data":[{"id":1,"memberId":81,"couponCode":"ignored","qrcodeUrl":"ignored"}]}"#] {
            XCTAssertNoThrow(try route.validateResponse((Data(data.utf8), 200), accountID: 81))
        }
        for data in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":[{"id":1}]}"#, #"{"code":200,"data":[{"id":1,"memberId":82}]}"#, #"{"code":200,"data":[{"id":0,"memberId":81}]}"#, #"{"code":200,"data":[{"id":1,"memberId":true}]}"#, #"{"code":200,"data":[{"id":1,"memberId":"81"}]}"#, #"{"code":200,"data":[{"id":1,"memberId":81},{"id":1,"memberId":81}]}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(data.utf8), 200), accountID: 81)) { XCTAssertEqual($0 as? APIError, .malformedResponse) }
        }
    }
    func testTransportAndBusinessErrorsRetainOriginalServiceHandling() throws {
        let route = try XCTUnwrap(ProfileOwnedCouponReadRoute(request: request(), baseURL: base))
        XCTAssertNoThrow(try route.validateResponse((Data(), 401), accountID: 81))
        XCTAssertNoThrow(try route.validateResponse((Data(), 503), accountID: 81))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":401}"#.utf8), 200), accountID: 81))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":500}"#.utf8), 200), accountID: 81))
        XCTAssertThrowsError(try route.validateResponse((Data(), 200), accountID: 81))
    }
}
