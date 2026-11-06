import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
final class CityMerchantValueRouteTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func scope() throws -> CityMerchantValueScope {
        try .init(fields: ["regionId":"r", "boardId":"b", "seasonId":"s", "rulesReleaseId":"v"])
    }
    private func window() throws -> CityMerchantValueWindow {
        try .init(from: "2026-11-01T00:00:00Z", to: "2026-11-02T00:00:00Z")
    }
    func testFourOriginalGETsRoundTrip() throws {
        let s = try scope(), w = try window()
        let routes: [CityMerchantValueRoute] = [.report(s,w,requestID:"request-a"), .events(s,w,cursor:""), .result(s,7), .benefit(s,w,snapshotID:7,eventID:8)]
        for route in routes {
            let request = try route.request(baseURL: base, token: "synthetic-token")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(CityMerchantValueRoute(request: request, baseURL: base, scope: s), route)
        }
    }
    func testVisitWriterAndForeignOriginAreRejected() throws {
        let s = try scope()
        var request = try CityMerchantValueRoute.report(s,try window(),requestID:"request-a").request(baseURL:base,token:"synthetic-token")
        request.url = URL(string:"https://other.test/native/api/merchant/city-value/report")
        XCTAssertNil(CityMerchantValueRoute(request:request,baseURL:base,scope:s))
        request.url = base.appendingPathComponent("api/city-value/visits")
        request.httpMethod = "POST"
        XCTAssertNil(CityMerchantValueRoute(request:request,baseURL:base,scope:s))
    }
    func testDuplicateQueryAndCookieAreRejected() throws {
        let s = try scope()
        var request = try CityMerchantValueRoute.events(s,try window(),cursor:"").request(baseURL:base,token:"synthetic-token")
        let original = request
        request.url = URL(string:request.url!.absoluteString + "&regionId=r")
        XCTAssertNil(CityMerchantValueRoute(request:request,baseURL:base,scope:s))
        request = original; request.setValue("session=synthetic",forHTTPHeaderField:"Cookie")
        XCTAssertNil(CityMerchantValueRoute(request:request,baseURL:base,scope:s))
    }
}
