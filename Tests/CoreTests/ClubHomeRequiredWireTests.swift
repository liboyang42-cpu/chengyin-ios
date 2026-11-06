import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class ClubHomeRequiredWireTests: XCTestCase {
    private func service(_ t: HomeRequiredWireTransport) throws -> ClubService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/fixture/")!), transport: t)
    }
    func testEachAggregateSectionMustBeAnActualArray() async throws {
        for key in ["owned", "joined", "nearby", "events"] {
            for invalid in [nil, NSNull(), false, [String: Any]()] as [Any?] {
                var body: [String: Any] = ["owned": [], "joined": [], "nearby": [], "events": []]
                body[key] = invalid
                let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
                let t = HomeRequiredWireTransport(bytes)
                do { _ = try await service(t).home(); XCTFail("Missing or invalid \(key) cannot be empty success") }
                catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
                XCTAssertEqual(t.calls, 1)
            }
        }
    }
    func testExplicitEmptyAggregateAndLegacyLocalDTORemainSupported() async throws {
        let bytes = Data(#"{"code":200,"data":{"owned":[],"joined":[],"nearby":[],"events":[]}}"#.utf8)
        let home = try await service(HomeRequiredWireTransport(bytes)).home()
        XCTAssertTrue(home.isEmpty)
        let local = try JSONDecoder().decode(ClubHome.self, from: Data("{}".utf8))
        XCTAssertTrue(local.isEmpty)
    }
    func testGuestRejectionAndAuthorityErrorsAreNotReinterpretedAsShapeErrors() async throws {
        for code in [401, 403, 500] {
            let t = HomeRequiredWireTransport(Data("{\"code\":\(code),\"msg\":\"请先登录\"}".utf8))
            do { _ = try await service(t).home(); XCTFail("Server rejection must remain rejection") }
            catch {
                let expected: ClubReadFailure = code == 401 ? .unauthorized(message: "请先登录") :
                    code == 403 ? .forbidden(message: "请先登录") : .rejected(code: code, message: "请先登录")
                XCTAssertEqual(error as? ClubReadFailure, expected)
            }
            XCTAssertNil(t.last?.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(t.calls, 1)
        }
    }
}
private final class HomeRequiredWireTransport: HTTPTransport {
    let bytes: Data
    var calls = 0
    var last: URLRequest?
    init(_ bytes: Data) { self.bytes = bytes }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; last = request; return (bytes, 200)
    }
}
