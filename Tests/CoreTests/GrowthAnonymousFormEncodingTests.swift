import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GrowthAnonymousFormEncodingTests: XCTestCase {
    func testAnonymousUsesDedicatedEncodingWithoutChangingLegacyOrAuthority() async throws {
        for anonymous in [true, false] {
            let wire = Wire()
            let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
                transport: wire, leaderboardContract: anonymous ? .anonymous : .legacy)
            do {
                _ = try await service.leaderboard(query: .init(metric: .exp, period: .week), limit: 1, token: "synthetic-token")
                XCTFail("Rejected envelope must not become a successful board")
            } catch { }
            let requests = await wire.requests
            XCTAssertEqual(requests.count, 1, "Never retry through legacy")
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(GrowthNormalReadRoute(request: request, baseURL: URL(string: "https://example.test/native")!), "Encoding must not grant normal transport access")
            let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            if anonymous {
                XCTAssertEqual(request.url?.path, "/native/api/growth/leaderboard/anonymous")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
                XCTAssertEqual(body, "limit=1&metric=exp&period=week")
            } else {
                XCTAssertEqual(request.url?.path, "/native/api/growth/leaderboard")
                XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                XCTAssertTrue(body.contains("name=\"metric\"\r\n\r\nexp\r\n"))
            }
        }
    }
    func testAnonymousInvalidTokenDoesNotDispatch() async throws {
        let wire = Wire()
        let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
            transport: wire, leaderboardContract: .anonymous)
        do {
            _ = try await service.leaderboard(query: .init(), token: "invalid\nidentity")
            XCTFail("Invalid token must fail before dispatch")
        } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let count = await wire.requests.count
        XCTAssertEqual(count, 0)
    }
    private actor Wire: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data("{\"code\":500,\"msg\":\"synthetic\"}".utf8), 200)
        }
    }
}
