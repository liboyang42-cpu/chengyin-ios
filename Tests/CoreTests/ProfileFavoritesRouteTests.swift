import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileFavoritesRouteTests: XCTestCase {
    private let base = URL(string: "https://favorites.example/native")!
    private func request(_ path: String = "api/creativesquare/list", _ fields: [String: String] = ["favorite_only":"1","pageNum":"1","pageSize":"10"]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-favorites", boundary: "FavoritesBoundary")
    }
    private func context(account: Int = 81, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-favorites", namespace: String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func testOnlyTwoCurrentUserListShapes() throws {
        let posts = try XCTUnwrap(ProfileFavoritesReadRoute(request: request(), baseURL: base))
        XCTAssertEqual(posts.pageNumber, 1); XCTAssertEqual(posts.pageSize, 10)
        let topics = try XCTUnwrap(ProfileFavoritesReadRoute(request: request("api/topic/like_list", ["pageNum":"2","pageSize":"100"]), baseURL: base))
        XCTAssertEqual(topics.pageNumber, 2); XCTAssertEqual(topics.path, "api/topic/like_list")
        for fields in [["favorite_only":"0","pageNum":"1","pageSize":"10"], ["pageNum":"1","pageSize":"10"], ["favorite_only":"1","pageNum":"1","pageSize":"10","member_id":"81"], ["favorite_only":"1","pageNum":"01","pageSize":"10"], ["favorite_only":"1","pageNum":"0","pageSize":"10"], ["favorite_only":"1","pageNum":"1","pageSize":"101"]] {
            XCTAssertNil(ProfileFavoritesReadRoute(request: try request("api/creativesquare/list", fields), baseURL: base))
        }
        XCTAssertNil(ProfileFavoritesReadRoute(request: try request("api/topic/like_list"), baseURL: base))
    }
    func testExactOriginMethodPathQueryAndMultipartAreRequired() throws {
        let original = try request(); var invalid: [URLRequest] = []
        for path in ["api/topic/like", "api/creativesquare/info", "api/creativesquare/list/", "api/v1/community/feeds/SAVED"] {
            var r = original; r.url = base.appendingPathComponent(path); invalid.append(r)
        }
        for suffix in ["?pageNum=1", "#fragment"] { var r = original; r.url = URL(string:r.url!.absoluteString + suffix); invalid.append(r) }
        var r = original; r.url = URL(string:"https://other.example/native/api/creativesquare/list"); invalid.append(r)
        for method in ["GET","PUT","DELETE"] { var r = original; r.httpMethod = method; invalid.append(r) }
        r = original; r.setValue("application/json", forHTTPHeaderField:"Content-Type"); invalid.append(r)
        r = original; r.setValue(nil, forHTTPHeaderField:"Accept"); invalid.append(r)
        r = original; r.httpBodyStream = InputStream(data: original.httpBody!); invalid.append(r)
        r = original; r.httpBody!.append(0); invalid.append(r)
        for r in invalid { XCTAssertNil(ProfileFavoritesReadRoute(request:r,baseURL:base)) }
    }
    func testDuplicateFieldsAndNoncanonicalNumbersCannotSmuggleAViewer() throws {
        var r = try request()
        r.httpBody = Data(("--FavoritesBoundary\r\nContent-Disposition: form-data; name=\"pageNum\"\r\n\r\n2\r\n" + String(data:r.httpBody!,encoding:.utf8)!).utf8)
        XCTAssertNil(ProfileFavoritesReadRoute(request:r,baseURL:base))
        for value in ["-1","+1","1.0","true"," 1","9223372036854775808"] {
            XCTAssertNil(ProfileFavoritesReadRoute(request:try request("api/topic/like_list",["pageNum":value,"pageSize":"10"]),baseURL:base))
        }
    }
    func testListAndDetailPurposesCannotSubstituteOrExpandEachOther() throws {
        let c = try context()
        let list = try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:ProfileFavoritesReadRoute.paths)
        let detail = try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:ProfileFavoriteDetailRoute.paths)
        XCTAssertNoThrow(try ProfileFavoritesReadAccess(context:c,approval:list))
        XCTAssertNoThrow(try ProfileFavoriteDetailAccess(context:c,approval:detail))
        XCTAssertThrowsError(try ProfileFavoritesReadAccess(context:c,approval:detail))
        XCTAssertThrowsError(try ProfileFavoriteDetailAccess(context:c,approval:list))
        for paths in [ProfileFavoritesReadRoute.paths.union(ProfileFavoriteDetailRoute.paths), ["api/coupon/myrecvlist"], ["api/topic/like_list"]] {
            let approval = try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try ProfileFavoritesReadAccess(context:c,approval:approval))
        }
    }
    func testContextAndIrreversibleRevocationFenceBothPurposes() throws {
        let c = try context()
        let list = try ProfileFavoritesReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:ProfileFavoritesReadRoute.paths))
        let detail = try ProfileFavoriteDetailAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:ProfileFavoriteDetailRoute.paths))
        for changed in [try context(account:82),try context(epoch:2),try context(role:"merchant"),try context(token:"other"),try context(namespace:"other")] {
            XCTAssertFalse(list.matches(changed)); XCTAssertFalse(detail.matches(changed))
        }
        list.revoke();detail.revoke();XCTAssertFalse(list.matches(c));XCTAssertFalse(detail.matches(c))
    }
    func testListSuccessMustContainRealRowsAndAuthorsAreNotTheViewer() throws {
        let route = try XCTUnwrap(ProfileFavoritesReadRoute(request:request(),baseURL:base))
        for raw in [#"{"code":200,"data":{"rows":[]}}"#,#"{"code":200,"data":{"rows":[{"id":1,"memberId":999}]}}"#] {
            XCTAssertNoThrow(try route.validateResponse((Data(raw.utf8),200)))
        }
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":[]}"#,#"{"code":200,"data":{"rows":{}}}"#,#"{"code":200,"data":{"rows":[{"id":true}]}}"#,#"{"code":200,"data":{"rows":[{"id":0}]}}"#,#"{"code":200,"data":{"rows":[{"id":1},{"id":1}]}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testSelectedDetailAndCommentsExactTargetsAndPageShape() throws {
        let detail = try XCTUnwrap(ProfileFavoriteDetailRoute(request:request("api/creativesquare/info",["id":"101"]),baseURL:base))
        XCTAssertEqual(detail.postID,101);XCTAssertNil(detail.pageNumber)
        let comments = try XCTUnwrap(ProfileFavoriteDetailRoute(request:request("api/comment/list",["owner_type":"3","owner_id":"101","pageNum":"2","pageSize":"50"]),baseURL:base))
        XCTAssertEqual(comments.postID,101);XCTAssertEqual(comments.pageNumber,2)
        for fields in [["owner_type":"1","owner_id":"101","pageNum":"1","pageSize":"50"],["owner_type":"3","owner_id":"101","pageNum":"1","pageSize":"100"],["owner_type":"3","owner_id":"101","pageNum":"1","pageSize":"50","member_id":"81"]] {
            XCTAssertNil(ProfileFavoriteDetailRoute(request:try request("api/comment/list",fields),baseURL:base))
        }
        XCTAssertThrowsError(try detail.validateResponse((Data(#"{"code":200,"data":{"id":102}}"#.utf8),200)))
        XCTAssertNoThrow(try detail.validateResponse((Data(#"{"code":200,"data":{"id":101,"memberId":999}}"#.utf8),200)))
    }
    func testCommentMissingRowsOrWrongOwnerAreNeverSuccessfulEmpty() throws {
        let route = try XCTUnwrap(ProfileFavoriteDetailRoute(request:request("api/comment/list",["owner_type":"3","owner_id":"101","pageNum":"1","pageSize":"50"]),baseURL:base))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"rows":[]}}"#.utf8),200)))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"rows":[{"id":7,"ownerType":3,"ownerId":101,"memberId":999}]}}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":{"rows":null}}"#,#"{"code":200,"data":{"rows":[{"id":7}]}}"#,#"{"code":200,"data":{"rows":[{"id":7,"ownerType":1,"ownerId":101}]}}"#,#"{"code":200,"data":{"rows":[{"id":7,"ownerType":3,"ownerId":102}]}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
        for status in [401,404,503] { XCTAssertNoThrow(try route.validateResponse((Data(),status))) }
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":401}"#.utf8),200)))
    }
}
