import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NearbyMapRecoveryTransport: HTTPTransport {
    var response: String
    private(set) var requests: [URLRequest] = []
    init(_ response: String) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), 200)
    }
}
final class NearbyMapDiscoveryProjectionTests: XCTestCase {
    func testOriginalPoisDisplayProjectionRetainsIdentityReadFactsAndExactGET() async throws {
        let transport = NearbyMapRecoveryTransport(#"{"code":200,"data":[{"id":7,"type":2,"name":"Source shop","tags":"coffee，walk|coffee;休闲","coverImg":" https://example.test/source.png ","found":true,"pendingRedeem":true}]}"#)
        let service = try RoamService(configuration: APIConfiguration(baseURL: URL(string: "https://example.test/fixture/")!), transport: transport)
        let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1.25, longitude: 2.5)!, label: "Explicit synthetic area")
        let rows = try await service.places(area: area, radiusM: 1000, token: "synthetic")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.id, 7); XCTAssertEqual(row.type, 2)
        XCTAssertEqual(row.tags, ["coffee", "walk", "coffee", "休闲"])
        XCTAssertEqual(row.coverImage, "https://example.test/source.png")
        XCTAssertEqual(row.found, true); XCTAssertEqual(row.pendingRedeem, true)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(transport.requests.count, 1); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.url?.path, "/fixture/api/roam/pois")
        let fields = Dictionary(uniqueKeysWithValues: (URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields, ["lat": "1.25", "lng": "2.5", "radius": "1000"])
    }
    func testMalformedOptionalDisplayFieldsDoNotInventCategoriesOrArtwork() throws {
        for fields in ["", #", "tags":null,"coverImg":null"#, #", "tags":7,"coverImg":true"#, #", "tags":"null","coverImg":"null"#, #", "tags":"  ","coverImg":"  \n ""#] {
            let row = try JSONDecoder().decode(RoamPlace.self, from: Data("{\"id\":7,\"type\":1\(fields)}".utf8))
            XCTAssertTrue(row.tags.isEmpty); XCTAssertNil(row.coverImage)
            XCTAssertEqual(row.id, 7); XCTAssertTrue(row.isSupported)
            XCTAssertNil(row.found); XCTAssertNil(row.pendingRedeem)
        }
    }
    func testDisplayFieldsDoNotCoerceUnknownReadFactsOrMerchantDescription() throws {
        let row = try JSONDecoder().decode(RoamPlace.self, from: Data(#"{"id":7,"type":2,"tags":"coffee","coverImg":"x","found":1,"pendingRedeem":"true","description":42}"#.utf8))
        XCTAssertEqual(row.tags, ["coffee"]); XCTAssertEqual(row.coverImage, "x")
        XCTAssertNil(row.found); XCTAssertNil(row.pendingRedeem); XCTAssertNil(row.merchantDescriptionText)
        XCTAssertEqual(row.readStatus.discovered, .unknown); XCTAssertEqual(row.readStatus.pendingRedemption, .unknown)
    }
}
