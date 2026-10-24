import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ProfileGuideReadRouteTests: XCTestCase {
    private let base=URL(string:"https://guide.example/native")!
    private func request(id:Int?=nil)throws->URLRequest {
        try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(id==nil ? ProfileGuideReadRoute.listPath:ProfileGuideReadRoute.detailPath),fields:id.map{["id":String($0)]} ?? [:],token:"synthetic-guide",includesBody:id != nil,boundary:"GuideBoundary")
    }
    func testOriginalListNoBodyAndDetailOnlyCanonicalPositiveID()throws {
        XCTAssertEqual(ProfileGuideReadRoute(request:try request(),baseURL:base),.list)
        XCTAssertEqual(ProfileGuideReadRoute(request:try request(id:21),baseURL:base),.detail(21))
        var list=try request();list.httpBody=Data();XCTAssertNil(ProfileGuideReadRoute(request:list,baseURL:base))
        for fields in [["id":"0"],["id":"01"],["id":"-1"],["id":"21","member_id":"81"],["pageNum":"1"]] {
            let detail=try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(ProfileGuideReadRoute.detailPath),fields:fields,token:"synthetic-guide")
            XCTAssertNil(ProfileGuideReadRoute(request:detail,baseURL:base))
        }
    }
    func testExtraURLMethodBodyStreamAndPrivateTargetsFailClosed()throws {
        for original in [try request(),try request(id:21)] {
            var values:[URLRequest]=[]
            for suffix in ["?id=21","#fragment","/"] {var r=original;r.url=URL(string:r.url!.absoluteString+suffix);values.append(r)}
            var r=original;r.httpMethod="GET";values.append(r)
            r=original;r.setValue(nil,forHTTPHeaderField:"Accept");values.append(r)
            r=original;r.httpBodyStream=InputStream(data:Data());values.append(r)
            for path in ["api/user/info","api/common/upload","api/common/infomation_delete"] {r=original;r.url=base.appendingPathComponent(path);values.append(r)}
            r=original;r.url=URL(string:r.url!.absoluteString.replacingOccurrences(of:"guide.example",with:"other.example"));values.append(r)
            for value in values {XCTAssertNil(ProfileGuideReadRoute(request:value,baseURL:base))}
        }
    }
    func testPurposeCannotBorrowAnyOtherApprovedPath()throws {
        let c=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:81,epoch:1,namespace:"synthetic",token:"synthetic-guide"))
        let correct=try ProfileGuideReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:ProfileGuideReadRoute.paths))
        XCTAssertTrue(correct.matches(c));correct.revoke();XCTAssertFalse(correct.matches(c))
        for paths in [Set<String>(),ProfileFavoritesReadRoute.paths,[ProfileGuideReadRoute.listPath],[ProfileGuideReadRoute.detailPath],[ProfileGuideReadRoute.listPath,ProfileGuideReadRoute.detailPath,"api/common/upload"]] {
            XCTAssertThrowsError(try ProfileGuideReadAccess(context:c,approval:.init(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)))
        }
    }
    func testListEmptyIsValidButMissingMalformedDuplicateRowsFail()throws {
        let route=ProfileGuideReadRoute.list
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":[]}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":{}}"#,#"{"code":200,"data":[{}]}"#,#"{"code":200,"data":[{"id":1},{"id":1}]}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testDetailExplicitNullAndEmptyObjectAreRemovedButNotMissingWrongOrMalformedData()throws {
        let route=ProfileGuideReadRoute.detail(21)
        for raw in [#"{"code":200,"data":null}"#,#"{"code":200,"data":{}}"#,#"{"code":200,"data":{"id":21,"title":"Guide","contents":"Safe text"}}"#] {
            XCTAssertNoThrow(try route.validateResponse((Data(raw.utf8),200)))
        }
        for raw in [#"{"code":200}"#,#"{"code":200,"data":[]}"#,#"{"code":200,"data":{"title":"Missing ID"}}"#,#"{"code":200,"data":{"id":22}}"#,#"{"code":200,"data":{"id":"21"}}"#,#"{"code":200,"data":{"id":true}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
    }
    func testOriginalServiceOnlyInformationDetailRecognizesExplicitRemoval()async throws {
        let wire=Wire(),service=SocialAccountService(configuration:try .init(baseURL:base),transport:wire)
        for body in [#"{"code":200,"data":null}"#,#"{"code":200,"data":{}}"#] {
            wire.body=body;let value=try await service.information(id:21,token:"synthetic-guide")
            XCTAssertTrue(value.isRemoved);XCTAssertEqual(value.id,0);XCTAssertTrue(value.title.isEmpty);XCTAssertNil(value.contents)
            do {_ = try await service.profile(memberID:21,token:"synthetic-guide");XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        }
        for body in [#"{"code":200}"#,#"{"code":200,"data":[]}"#,#"{"code":200,"data":{"id":22}}"#,#"{"code":200,"data":{"title":"No ID"}}"#] {
            wire.body=body;do {_ = try await service.information(id:21,token:"synthetic-guide");XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        }
    }
    func testExistingErrorHandlingAndSafeArticleProjectionRemainExact()async throws {
        let wire=Wire(),service=SocialAccountService(configuration:try .init(baseURL:base),transport:wire)
        wire.status=404;do {_ = try await service.information(id:21,token:"synthetic-guide");XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(404))}
        wire.status=200;wire.body=#"{"code":401}"#
        do {_ = try await service.information(id:21,token:"synthetic-guide");XCTFail()}catch{XCTAssertEqual(error as? APIError,.unauthorized)}
        let article=SocialArticleContent("<h1>Title</h1><script>alert(1)</script><p>Text</p>")
        XCTAssertFalse(article.blocks.isEmpty)
    }
    @MainActor private final class Wire:HTTPTransport {
        var body=#"{"code":200,"data":null}"#,status=200
        func send(_ request:URLRequest)async throws->(Data,Int){(Data(body.utf8),status)}
    }
}
