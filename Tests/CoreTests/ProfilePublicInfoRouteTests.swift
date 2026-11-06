import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfilePublicInfoRouteTests: XCTestCase {
    private let base = URL(string: "https://public-profile.example/native")!
    private func request(_ fields: [String: String] = ["member_id":"82"]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfilePublicInfoReadRoute.path), fields: fields, token: "synthetic", boundary: "PublicProfileBoundary")
    }
    private func context(account: Int = 81, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic", namespace: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func testExactPositiveTargetNotClientViewerField() throws {
        XCTAssertEqual(ProfilePublicInfoReadRoute(request: try request(), baseURL: base)?.memberID, 82)
        for id in ["0","-1","01","+1","1.0","true"," 82","9223372036854775808"] {
            XCTAssertNil(ProfilePublicInfoReadRoute(request: try request(["member_id":id]), baseURL: base))
        }
        for fields in [[:],["id":"82"],["member_id":"82","viewer_id":"81"],["member_id":"82","pageNum":"1"]] {
            XCTAssertNil(ProfilePublicInfoReadRoute(request: try request(fields), baseURL: base))
        }
    }
    func testExactURLAndMultipartRejectPrivateAliasesAndSmuggling() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for suffix in ["?member_id=82", "#fragment", "/"] { var r=original;r.url=URL(string:r.url!.absoluteString+suffix);invalid.append(r) }
        for path in ["api/user/info","api/userInfo","api/user/action","api/user/public-info-other"] { var r=original;r.url=base.appendingPathComponent(path);invalid.append(r) }
        var r=original;r.url=URL(string:"https://other.example/native/api/user/public-info");invalid.append(r)
        for method in ["GET","PUT","DELETE"] { r=original;r.httpMethod=method;invalid.append(r) }
        r=original;r.setValue("application/json",forHTTPHeaderField:"Content-Type");invalid.append(r)
        r=original;r.setValue(nil,forHTTPHeaderField:"Accept");invalid.append(r)
        r=original;r.httpBodyStream=InputStream(data:original.httpBody!);invalid.append(r)
        r=original;r.httpBody!.append(0);invalid.append(r)
        r=original;r.httpBody=Data(("--PublicProfileBoundary\r\nContent-Disposition: form-data; name=\"member_id\"\r\n\r\n83\r\n"+String(data:original.httpBody!,encoding:.utf8)!).utf8);invalid.append(r)
        for value in invalid { XCTAssertNil(ProfilePublicInfoReadRoute(request:value,baseURL:base)) }
    }
    func testIndependentPurposeCannotBorrowListCouponOrExpandedApproval() throws {
        let c=try context()
        XCTAssertNoThrow(try ProfilePublicInfoReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:[ProfilePublicInfoReadRoute.path])))
        for paths in [ProfileFavoritesReadRoute.paths,ProfileFavoriteDetailRoute.paths,[ProfilePublicInfoReadRoute.path,"api/user/info"],["api/coupon/myrecvlist"]] {
            XCTAssertThrowsError(try ProfilePublicInfoReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)))
        }
    }
    func testFullContextAndRevocationAndIrreversibleTarget() throws {
        let c=try context(), access=try ProfilePublicInfoReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:[ProfilePublicInfoReadRoute.path]))
        for changed in [try context(account:82),try context(epoch:2),try context(role:"merchant"),try context(token:"other"),try context(namespace:"other")] { XCTAssertFalse(access.matches(changed)) }
        XCTAssertTrue(access.matches(c));access.revoke();XCTAssertFalse(access.matches(c))
        var current=true
        let target=try ProfilePublicInfoTarget(memberID:82,context:c,viewerRevision:1,current:{current})
        XCTAssertTrue(target.isCurrent);current=false;XCTAssertFalse(target.isCurrent);current=true;XCTAssertFalse(target.isCurrent)
        XCTAssertThrowsError(try ProfilePublicInfoTarget(memberID:0,context:c,viewerRevision:1,current:{true}))
    }
    func testExactResponseIDAllowsMissingOptionalPublicDataButNeverMissingObject() throws {
        let route=try XCTUnwrap(ProfilePublicInfoReadRoute(request:request(),baseURL:base))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"id":82}}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":{"id":81}}"#,#"{"code":200,"data":{"id":true}}"#,#"{"code":200,"data":{"id":"82"}}"#,#"{"code":200,"data":{}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testOptionalUnknownAndPrivateExtraFieldsAreNotPublicProjection() throws {
        let minimal=try JSONDecoder().decode(SocialPublicProfile.self,from:Data(#"{"id":82}"#.utf8))
        let extra=try JSONDecoder().decode(SocialPublicProfile.self,from:Data(#"{"id":82,"phone":"synthetic-private","token":"synthetic-private","balance":9999,"createTime":"2020-01-01"}"#.utf8))
        XCTAssertEqual(minimal,extra);XCTAssertNil(extra.nickname);XCTAssertNil(extra.level);XCTAssertNil(extra.following);XCTAssertNil(extra.isFollowed)
        XCTAssertTrue(extra.workImages.isEmpty);XCTAssertTrue(extra.interests.isEmpty)
    }
    func testDenialRemainsServiceErrorNotEmptySuccess() throws {
        let route=try XCTUnwrap(ProfilePublicInfoReadRoute(request:request(),baseURL:base))
        for status in [401,403,404,503] { XCTAssertNoThrow(try route.validateResponse((Data(),status))) }
        for code in [401,403,404,500] { XCTAssertNoThrow(try route.validateResponse((Data("{\"code\":\(code)}".utf8),200))) }
        XCTAssertThrowsError(try route.validateResponse((Data(#"{"data":{}}"#.utf8),200)))
    }
}
