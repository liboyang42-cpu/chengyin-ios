import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor OwnMediaWire: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), status) }
}

@MainActor final class OwnMediaReviewTests: XCTestCase {
    private let base = URL(string: "https://media.example/native")!
    private func page(_ rows: String, before: Int64? = nil) throws -> OwnMediaPage {
        try OwnMediaPage.decode(Data("{\"code\":200,\"data\":[\(rows)]}".utf8), before: before)
    }
    func testRowsMapStatesTypesAndReasons() throws {
        let value = try page(#"{"assetId":9,"reviewState":"HOLD","mediaType":"IMAGE"},{"assetId":"7","reviewState":"REJECTED","reviewReason":" 画面模糊 ","mediaType":"AUDIO"},{"assetId":3,"reviewState":"UNAVAILABLE","mediaType":"VIDEO"}"#)
        XCTAssertEqual(value.rows.map(\.id), [9, 7, 3])
        XCTAssertEqual(value.rows.map(\.reviewState), [.hold, .rejected, .unavailable])
        XCTAssertEqual(value.rows.map(\.mediaType), [.image, .audio, .other])
        XCTAssertEqual(value.rows[1].reviewReason, "画面模糊")
        XCTAssertFalse(value.hasMore); XCTAssertNil(value.nextCursor)
    }
    func testFullPageOffersCursorAndOlderPageMustBeOlder() throws {
        let rows = (1...50).reversed().map { "{\"assetId\":\($0 + 100),\"reviewState\":\"APPROVED\"}" }.joined(separator: ",")
        let full = try page(rows)
        XCTAssertTrue(full.hasMore); XCTAssertEqual(full.nextCursor, 101)
        XCTAssertNoThrow(try page(#"{"assetId":100,"reviewState":"HOLD"}"#, before: 101))
        XCTAssertThrowsError(try page(#"{"assetId":101,"reviewState":"HOLD"}"#, before: 101))
    }
    func testInvalidRowsFailInsteadOfShowingPartialLists() {
        for rows in [#"{"assetId":0,"reviewState":"HOLD"}"#, #"{"assetId":1.5,"reviewState":"HOLD"}"#, #"{"assetId":true,"reviewState":"HOLD"}"#,
                     #"{"assetId":"01","reviewState":"HOLD"}"#, #"{"assetId":2,"reviewState":"PENDING"}"#,
                     #"{"assetId":2,"reviewState":"HOLD"},{"assetId":3,"reviewState":"HOLD"}"#] {
            XCTAssertThrowsError(try page(rows), rows)
        }
        let tooMany = (1...51).reversed().map { "{\"assetId\":\($0),\"reviewState\":\"HOLD\"}" }.joined(separator: ",")
        XCTAssertThrowsError(try page(tooMany))
        XCTAssertThrowsError(try OwnMediaPage.decode(Data(#"{"code":401}"#.utf8), before: nil)) { XCTAssertEqual($0 as? APIError, .unauthorized) }
        XCTAssertThrowsError(try OwnMediaPage.decode(Data(#"{"code":200,"data":null}"#.utf8), before: nil))
    }
    func testRequestsAreExactGetsAndRouteRejectsVariants() async throws {
        let wire = OwnMediaWire(#"{"code":200,"data":[]}"#)
        let service = OwnMediaService(configuration: try APIConfiguration(baseURL: base), transport: wire)
        _ = try await service.page(before: nil, token: "synthetic-media")
        _ = try await service.page(before: 42, token: "synthetic-media")
        let requests = await wire.requests
        XCTAssertEqual(requests.map(\.url?.absoluteString), [base.appendingPathComponent(OwnMediaReadRoute.path).absoluteString,
                                                            base.appendingPathComponent(OwnMediaReadRoute.path).absoluteString + "?beforeId=42"])
        for request in requests {
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
            XCTAssertTrue(OwnMediaReadRoute.accepts(request, baseURL: base))
        }
        var post = requests[0]; post.httpMethod = "POST"
        var retry = requests[0]; retry.url = base.appendingPathComponent("api/media/asset/7/retry")
        var extra = requests[1]; extra.url = URL(string: requests[1].url!.absoluteString + "&owner=9")
        var zero = requests[1]; zero.url = URL(string: base.appendingPathComponent(OwnMediaReadRoute.path).absoluteString + "?beforeId=0")
        var anonymous = requests[0]; anonymous.setValue(nil, forHTTPHeaderField: "Authorization")
        for candidate in [post, retry, extra, zero, anonymous] { XCTAssertFalse(OwnMediaReadRoute.accepts(candidate, baseURL: base)) }
        do { _ = try await service.page(before: 0, token: "synthetic-media"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
    }
    func testForbiddenIsDistinctFromExpiredLogin() async throws {
        let forbidden = OwnMediaService(configuration: try APIConfiguration(baseURL: base), transport: OwnMediaWire("{}", status: 403))
        do { _ = try await forbidden.page(before: nil, token: "synthetic-media"); XCTFail() }
        catch { XCTAssertEqual(error as? OwnMediaReadFailure, .rejected(code: 403)) }
        let expired = OwnMediaService(configuration: try APIConfiguration(baseURL: base), transport: OwnMediaWire(#"{"code":2}"#))
        do { _ = try await expired.page(before: nil, token: "synthetic-media"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testReaderWithoutLeaseNeverDispatches() async throws {
        let wire = OwnMediaWire(#"{"code":200,"data":[]}"#)
        let service = OwnMediaService(configuration: try APIConfiguration(baseURL: base), transport: wire)
        var session = try OwnMediaSession(accountID: 5, epoch: 1, token: "synthetic-media", approval: nil)
        let reader = OwnMediaSessionReader(service: service, currentSession: { session })
        XCTAssertFalse(reader.isAvailable)
        do { _ = try await reader.page(before: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let count = await wire.requests.count; XCTAssertEqual(count, 0)
        session = try OwnMediaSession(accountID: 5, epoch: 1, token: "synthetic-media", approval: UUID())
        XCTAssertTrue(reader.isAvailable)
        _ = try await reader.page(before: nil)
        let after = await wire.requests.count; XCTAssertEqual(after, 1)
    }
}
