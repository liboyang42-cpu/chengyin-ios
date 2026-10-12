import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TicketWalletListReadRouteTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func request(_ fields: [String: String] = ["owner_type":"1"], path: String = "api/registration/list", boundary: String = "ticket-wallet-fixture") throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-7", boundary: boundary)
    }
    private func check(_ json: String, lane: TicketWalletListReadRoute = .route, owner: Int = 7, status: Int = 200) throws {
        try lane.validateResponse((Data(json.utf8), status), expectedAccountID: owner)
    }
    func testOnlyTwoExactExistingLaneRequestsMatch() throws {
        XCTAssertEqual(TicketWalletListReadRoute(request: try request(), baseURL: base), .route)
        XCTAssertEqual(TicketWalletListReadRoute(request: try request(["owner_type":"2"]), baseURL: base), .activity)
    }
    func testOtherOwnerTypesNoncanonicalNumbersAndMissingFieldsAreRejected() throws {
        for raw in ["0","3","4","-1","01","2.0"," 1","1 ","true",""] {
            XCTAssertNil(TicketWalletListReadRoute(request: try request(["owner_type":raw]), baseURL: base), raw)
        }
        XCTAssertNil(TicketWalletListReadRoute(request: try request([:]), baseURL: base))
    }
    func testExtraPaginationStatusMemberAndOnlineFieldsAreRejected() throws {
        for key in ["pageNum","pageSize","status","memberId","member_id","is_online","id","owner_id"] {
            XCTAssertNil(TicketWalletListReadRoute(request: try request(["owner_type":"1",key:"1"]), baseURL: base), key)
        }
    }
    func testOtherPathsDetailsWritesAndForeignOriginsAreRejected() throws {
        for path in ["api/registration/info","api/registration/create","api/registration/pay","api/registration/cancel","api/verify/dyncode/issue","api/team/my"] {
            XCTAssertNil(TicketWalletListReadRoute(request: try request(path: path), baseURL: base))
        }
        for url in ["https://other.test/native/api/registration/list","http://example.test/native/api/registration/list","https://example.test/else/api/registration/list","https://example.test/native/api/registration/list?owner_type=1","https://example.test/native/api/registration/list?","https://example.test/native/api/registration/list#x","https://example.test/native/api/registration/%6cist"] {
            var r = try request(); r.url = URL(string: url); XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base), url)
        }
    }
    func testMethodJSONFormEncodingAndBodyStreamsAreRejected() throws {
        var r = try request(); r.httpMethod = "GET"; XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.httpBody = Data(#"{"owner_type":1}"#.utf8); r.setValue("application/json", forHTTPHeaderField:"Content-Type")
        XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.httpBody = Data("owner_type=1".utf8); r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField:"Content-Type")
        XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.httpBodyStream = InputStream(data: Data("owner_type=1".utf8))
        XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
    }
    func testDuplicateFieldsExtraBytesAndBoundaryDriftAreRejected() throws {
        var r = try request(); let original = try XCTUnwrap(r.httpBody)
        r.httpBody = original + original; XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.httpBody?.append(0); XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.setValue("multipart/form-data; boundary=other",forHTTPHeaderField:"Content-Type")
        XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
        r = try request(); r.setValue("multipart/form-data; boundary=ticket-wallet-fixture; charset=utf-8",forHTTPHeaderField:"Content-Type")
        XCTAssertNil(TicketWalletListReadRoute(request: r, baseURL: base))
    }
    func testNoUnreviewedHTTPOrCredentialBearingBase() throws {
        for value in ["http://example.test/native","https://u:p@example.test/native","https://example.test/native?q=x"] {
            XCTAssertNil(TicketWalletListReadRoute(request: try request(), baseURL: URL(string:value)!))
        }
    }
    func testOwnedArrayAndActualTableEnvelopesPassBothLanes() throws {
        for lane in TicketWalletListReadRoute.allCases {
            let row = "{\"id\":41,\"memberId\":7,\"ownerType\":\(lane.rawValue)}"
            try check("{\"code\":200,\"data\":[\(row)]}",lane:lane)
            try check("{\"code\":200,\"data\":{\"rows\":[\(row)],\"total\":1}}",lane:lane)
        }
    }
    func testSameOwnerDuplicateIDsRemainSourceOrderedNotDeduplicated() throws {
        try check(#"{"code":200,"data":[{"id":41,"memberId":7,"ownerType":1},{"id":41,"memberId":7,"ownerType":1}]}"#)
    }
    func testExistingAbsentNullAndEmptyDataSemanticsRemain() throws {
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":[]}"#,#"{"code":200,"data":{"rows":[],"total":0}}"#] { try check(raw) }
    }
    func testForeignOrMixedOwnerRejectsEntireLane() {
        for raw in [#"{"code":200,"data":[{"id":41,"memberId":8,"ownerType":1}]}"#,#"{"code":200,"data":{"rows":[{"id":41,"memberId":7,"ownerType":1},{"id":42,"memberId":8,"ownerType":1}]}}"#] {
            XCTAssertThrowsError(try check(raw)) { XCTAssertEqual($0 as? APIError,.malformedResponse) }
        }
    }
    func testMissingNullStringBooleanAndZeroOwnerNeverBecomeCurrentOwner() {
        for raw in ["null","\"7\"","true","0","-7"] {
            XCTAssertThrowsError(try check("{\"code\":200,\"data\":[{\"id\":41,\"memberId\":\(raw),\"ownerType\":1}]}"))
        }
        XCTAssertThrowsError(try check(#"{"code":200,"data":[{"id":41,"ownerType":1}]}"#))
    }
    func testWrongOrMissingLaneAndInvalidIDRejectSuccess() {
        for row in [#"{"id":41,"memberId":7,"ownerType":2}"#,#"{"id":41,"memberId":7}"#,#"{"id":0,"memberId":7,"ownerType":1}"#,#"{"id":"41","memberId":7,"ownerType":1}"#,#"{"id":41,"memberId":7,"ownerType":"1"}"#] {
            XCTAssertThrowsError(try check("{\"code\":200,\"data\":[\(row)]}"))
        }
    }
    func testMalformedSuccessTableCannotMasqueradeAsEmpty() {
        for data in ["{}","{\"rows\":null}","{\"rows\":{}}","[null]","true","7","\"rows\""] {
            XCTAssertThrowsError(try check("{\"code\":200,\"data\":\(data)}"))
        }
    }
    func testCurrent401AndBusinessErrorsDoNotDecodeUntrustedPayload() throws {
        for status in [401,403,500] { try check("not JSON",status:status) }
        for code in [401,403,500] { try check("{\"code\":\(code),\"data\":false,\"msg\":[]}") }
    }
    func testInvalidOwnerAndMalformedStatusCannotPass() {
        XCTAssertThrowsError(try check(#"{"code":200,"data":[]}"#,owner:0))
        for raw in ["not JSON",#"{"code":"200","data":[]}"#,#"{"code":true,"data":[]}"#] { XCTAssertThrowsError(try check(raw)) }
    }
    private actor FixedResponse: HTTPTransport {
        let body: String
        init(_ body: String) { self.body = body }
        func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(body.utf8), 200) }
    }
    func testExistingActivityReaderAcceptsActualRowsAndRetainsLegacyArray() async throws {
        for data in ["[{\"id\":42,\"memberId\":7,\"ownerType\":2}]", "{\"rows\":[{\"id\":42,\"memberId\":7,\"ownerType\":2}],\"total\":1}"] {
            let service = try TicketWalletService(configuration: APIConfiguration(baseURL: base),
                transport: FixedResponse("{\"code\":200,\"data\":\(data)}"))
            let rows = try await service.list(lane: .activity, token: "synthetic-7")
            XCTAssertEqual(rows.map(\.id), [42])
        }
    }
    func testExistingActivityReaderRejectsObjectInsteadOfRowsArray() async throws {
        let service = try TicketWalletService(configuration: APIConfiguration(baseURL: base),
            transport: FixedResponse(#"{"code":200,"data":{"rows":{}}}"#))
        do { _ = try await service.list(lane: .activity, token: "synthetic-7"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

}
