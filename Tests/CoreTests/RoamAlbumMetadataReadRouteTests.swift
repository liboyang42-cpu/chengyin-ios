import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamAlbumMetadataReadRouteTests: XCTestCase {
    private let base=URL(string:"https://album.example/native")!
    private func request(_ page:String="1",_ size:String="20",extra:[String:String]=[:]) throws -> URLRequest {
        var fields=["pageNum":page,"pageSize":size];fields.merge(extra){_,v in v}
        return try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(RoamAlbumMetadataReadRoute.path),fields:fields,token:"synthetic-album",boundary:"synthetic")
    }
    func testExactCanonicalPaginationAndNoServerOffsetWrap() throws {
        for (page,size) in [(1,1),(1,20),(1,50),(20001,50),(1_000_001,1)] {
            let value=try XCTUnwrap(RoamAlbumMetadataReadRoute(request:request(String(page),String(size)),baseURL:base))
            XCTAssertEqual(value.page,page);XCTAssertEqual(value.pageSize,size)
        }
        for (page,size) in [(0,20),(-1,20),(1,0),(1,51),(20002,50),(1_000_002,1),(Int.max,50),(Int.min,20)] {
            XCTAssertFalse(RoamAlbumMetadataReadRoute.valid(page:page,pageSize:size))
            XCTAssertNil(RoamAlbumMetadataReadRoute(request:try request(String(page),String(size)),baseURL:base))
        }
        for value in ["01","+1","1.0","1e0","true"] {XCTAssertNil(RoamAlbumMetadataReadRoute(request:try request(value),baseURL:base))}
    }
    func testExactPathMethodBodyAndDuplicateFieldsOnly() throws {
        var values:[URLRequest]=[]
        for path in ["api/roam/stamp/create","api/roam/stamp/exchange","api/roam/stamp/received","api/roam/stamp/list/"] {var r=try request();r.url=base.appendingPathComponent(path);values.append(r)}
        for method in ["GET","PUT","DELETE"] {var r=try request();r.httpMethod=method;values.append(r)}
        for extra in [["memberId":"81"],["givenStampId":"7"],["picUrl":"https://unapproved.invalid/img"]] {values.append(try request(extra:extra))}
        var r=try request();r.url=URL(string:r.url!.absoluteString+"?pageNum=1");values.append(r)
        r=try request();r.url=URL(string:r.url!.absoluteString+"#part");values.append(r)
        r=try request();r.url=URL(string:"https://other.invalid/native/api/roam/stamp/list");values.append(r)
        r=try request();r.httpBodyStream=InputStream(data:Data());values.append(r)
        r=try request();r.httpBody=Data("{}".utf8);values.append(r)
        r=try request();r.setValue(nil,forHTTPHeaderField:"Accept");values.append(r)
        r=try request();let body=String(data:r.httpBody!,encoding:.utf8)!
        r.httpBody=Data(body.replacingOccurrences(of:"--synthetic--\r\n",with:"--synthetic\r\nContent-Disposition: form-data; name=\"pageNum\"\r\n\r\n1\r\n--synthetic--\r\n").utf8);values.append(r)
        for r in values {XCTAssertNil(RoamAlbumMetadataReadRoute(request:r,baseURL:base))}
    }
    func testIndependentReadApprovalExcludesImagesWritesAndOtherReads() throws {
        let c=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:81,epoch:1,namespace:"synthetic",token:"synthetic-album"))
        let grant=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:[RoamAlbumMetadataReadRoute.path])
        let access=try RoamAlbumMetadataReadAccess(context:c,approval:grant);XCTAssertTrue(access.matches(c))
        for paths in [Set<String>(),["api/roam/tiles/page"],["api/roam/stamp/create"],[RoamAlbumMetadataReadRoute.path,"api/roam/stamp/received"]] {
            let other=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try RoamAlbumMetadataReadAccess(context:c,approval:other))
        }
        access.revoke();XCTAssertFalse(access.matches(c))
    }
    func testRealEmptyPageAcceptedMissingNullWrongPagesRejected() throws {
        let route=try XCTUnwrap(RoamAlbumMetadataReadRoute(request:request(),baseURL:base))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"list":[],"total":0,"pageNum":1,"pageSize":20}}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":{"total":0,"pageNum":1,"pageSize":20}}"#,#"{"code":200,"data":{"list":null,"total":0,"pageNum":1,"pageSize":20}}"#,#"{"code":200,"data":{"list":[],"total":0,"pageNum":2,"pageSize":20}}"#,#"{"code":200,"data":{"list":[],"total":0,"pageNum":1,"pageSize":50}}"#,#"{"code":200,"data":{"list":[],"total":-1,"pageNum":1,"pageSize":20}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testDuplicateIDsInvalidIDsAndOversizedRowsFail() throws {
        let route=try XCTUnwrap(RoamAlbumMetadataReadRoute(request:request(),baseURL:base)),row:[String:Any]=["id":1,"picUrl":"https://unapproved.invalid/img"]
        let cases: [[[String:Any]]] = [[row,row],[["id":0]],(1...21).map{["id":$0]}]
        for list in cases {
            XCTAssertThrowsError(try route.validateResponse((JSONSerialization.data(withJSONObject:["code":200,"data":["list":list,"total":100,"pageNum":1,"pageSize":20]]),200)))
        }
    }
    func testSourceCaptionURLAndModerationValuesAreNotRewrittenOrClaimedOwnedByMemberField() throws {
        let raw=#"{"list":[{"id":7,"picUrl":"https://unapproved.invalid/private.jpg","caption":"  original  ","checkState":0},{"id":8,"picUrl":"","checkState":2}],"total":2,"pageNum":1,"pageSize":20}"#
        let route=try XCTUnwrap(RoamAlbumMetadataReadRoute(request:request(),baseURL:base));try route.validateResponse((Data(("{\"code\":200,\"data\":"+raw+"}").utf8),200))
        let page=try JSONDecoder().decode(RoamAlbumPage.self,from:Data(raw.utf8))
        XCTAssertEqual(page.list[0].caption,"  original  ");XCTAssertEqual(page.list[0].picUrl,"https://unapproved.invalid/private.jpg")
        XCTAssertTrue(page.list[0].isVisible);XCTAssertFalse(page.list[1].isVisible)
    }
}
