import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileFavoriteTopicRouteTests: XCTestCase {
    private let base = URL(string: "https://favorite-topics.example/native")!
    private func request(_ fields: [String: String] = ["id":"201"]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(ProfileFavoriteTopicReadRoute.path), fields:fields, token:"synthetic", boundary:"TopicBoundary")
    }
    private func context(account:Int = 81, epoch:UInt64 = 1, role:String = "player", token:String = "synthetic", namespace:String = "synthetic") throws -> RuntimeDependencyContext {
        .init(market:.china,baseURL:base,role:role,session:try .init(accountID:account,epoch:epoch,namespace:namespace,token:token))
    }
    func testCanonicalPositiveSelectedIDOnly() throws {
        XCTAssertEqual(ProfileFavoriteTopicReadRoute(request:try request(),baseURL:base)?.topicID,201)
        for value in ["0","-1","01","+1","1.0","true"," 201","9223372036854775808"] {
            XCTAssertNil(ProfileFavoriteTopicReadRoute(request:try request(["id":value]),baseURL:base))
        }
        for fields in [[:],["topic_id":"201"],["id":"201","member_id":"81"],["id":"201","pageNum":"1"]] {
            XCTAssertNil(ProfileFavoriteTopicReadRoute(request:try request(fields),baseURL:base))
        }
    }
    func testExactURLMethodAndCanonicalMultipartNoSmuggling() throws {
        let original=try request();var invalid:[URLRequest]=[]
        for suffix in ["?id=201","#fragment","/"] {var r=original;r.url=URL(string:r.url!.absoluteString+suffix);invalid.append(r)}
        for path in ["api/topic/like","api/topic/list","api/creativesquare/info","api/comment/list"] {var r=original;r.url=base.appendingPathComponent(path);invalid.append(r)}
        var r=original;r.url=URL(string:"https://other.example/native/api/topic/info-to-user");invalid.append(r)
        for method in ["GET","PUT","DELETE"] {r=original;r.httpMethod=method;invalid.append(r)}
        r=original;r.setValue("application/json",forHTTPHeaderField:"Content-Type");invalid.append(r)
        r=original;r.setValue(nil,forHTTPHeaderField:"Accept");invalid.append(r)
        r=original;r.httpBodyStream=InputStream(data:original.httpBody!);invalid.append(r)
        r=original;r.httpBody!.append(0);invalid.append(r)
        r=original;r.httpBody=Data(("--TopicBoundary\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n202\r\n"+String(data:original.httpBody!,encoding:.utf8)!).utf8);invalid.append(r)
        for value in invalid {XCTAssertNil(ProfileFavoriteTopicReadRoute(request:value,baseURL:base))}
    }
    func testTopicPurposeCannotBorrowListPostOrExpandedApproval() throws {
        let c=try context()
        XCTAssertNoThrow(try ProfileFavoriteTopicReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:[ProfileFavoriteTopicReadRoute.path])))
        for paths in [ProfileFavoritesReadRoute.paths,ProfileFavoriteDetailRoute.paths,[ProfileFavoriteTopicReadRoute.path,"api/topic/like"],["api/coupon/myrecvlist"]] {
            XCTAssertThrowsError(try ProfileFavoriteTopicReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)))
        }
    }
    func testContextByteAndRevocationCannotRevive() throws {
        let c=try context(), access=try ProfileFavoriteTopicReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:[ProfileFavoriteTopicReadRoute.path]))
        for changed in [try context(account:82),try context(epoch:2),try context(role:"merchant"),try context(token:"other"),try context(namespace:"other")] {XCTAssertFalse(access.matches(changed))}
        XCTAssertTrue(access.matches(c));access.revoke();XCTAssertFalse(access.matches(c))
    }
    func testSuccessRequiresExactTargetAndActualNonemptyName() throws {
        let route=try XCTUnwrap(ProfileFavoriteTopicReadRoute(request:request(),baseURL:base))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"id":201,"name":"Topic","memberId":999}}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":{"id":202,"name":"Other"}}"#,#"{"code":200,"data":{"id":true,"name":"Topic"}}"#,#"{"code":200,"data":{"id":"201","name":"Topic"}}"#,#"{"code":200,"data":{"id":201}}"#,#"{"code":200,"data":{"id":201,"name":" "}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testDenialAndMissingAccessNeverBecomeFakeSuccess() throws {
        let route=try XCTUnwrap(ProfileFavoriteTopicReadRoute(request:request(),baseURL:base))
        for status in [401,403,404,503] {XCTAssertNoThrow(try route.validateResponse((Data(),status)))}
        for code in [401,403,404,500] {XCTAssertNoThrow(try route.validateResponse((Data("{\"code\":\(code)}".utf8),200)))}
        XCTAssertThrowsError(try route.validateResponse((Data(#"{"data":{}}"#.utf8),200)))
    }
}
