import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor EditorCityNodeTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    var suspended = false
    var continuation: CheckedContinuation<(Data, Int), Error>?
    var pending: Bool { continuation != nil }
    func suspend() { suspended = true }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if suspended { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return (Data(#"{"code":200,"data":[{"poiId":7,"name":"POI","lat":31,"lng":121}]}"#.utf8), 200)
    }
    func finish() { continuation?.resume(returning: (Data(#"{"code":200,"data":[]}"#.utf8), 200)); continuation = nil }
}
@MainActor final class SearchMapCityNodeReadTests: XCTestCase {
    private func query() throws -> CityNodeSearchQuery { .init(filter: .init(keyword: "park"), area: try .manual(latitude: "31", longitude: "121")) }
    private func service(_ t: EditorCityNodeTransport) throws -> SearchMapService { .init(configuration: try .init(baseURL: URL(string: "https://example.com/test/")!), transport: t) }
    func testDedicatedReadUsesOnlyExistingGETCityNodesWithExactManualCenter() async throws {
        let t = EditorCityNodeTransport(), result = try await service(t).cityNodes(query(), token: "synthetic-token")
        XCTAssertEqual(result.map(\.id), [7]); let requests = await t.requests; XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/test/api/city/nodes"); XCTAssertNil(request.httpBody)
        let fields = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields, ["lat":"31.0", "lng":"121.0", "radius":"20000", "keyword":"park"])
    }
    func testGuestCannotDispatch() async throws {
        let t = EditorCityNodeTransport()
        do { _ = try await service(t).cityNodes(query()); XCTFail("guest dispatched") } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testUnapprovedSessionDoesNotDispatchOrActivateReader() async throws {
        let t = EditorCityNodeTransport(), context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic-token")
        let reader = SearchMapSessionReader(service: try service(t), currentContext: { context })
        do { _ = try await reader.cityNodes(query()); XCTFail("missing authority") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testApprovedSessionUsesManualAreaAndSingleRead() async throws {
        let t = EditorCityNodeTransport(), selection = ManualMapAreaSelection(), context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic-token", manualMapApprovalRevision: UUID())
        let reader = SearchMapSessionReader(service: try service(t), currentContext: { context }, manualAreaSelection: selection)
        _ = try await reader.cityNodes(query()); XCTAssertGreaterThan(reader.manualAreaRevision, 0)
        let requests = await t.requests; XCTAssertEqual(requests.count, 1)
    }
    func testLateOwnerApprovalAndAreaChangesRejectResults() async throws {
        for change in ["owner", "approval", "area"] {
            let t = EditorCityNodeTransport(); await t.suspend()
            var context = try SearchMapContext(accountID: 7, epoch: 1, token: "synthetic-token", manualMapApprovalRevision: UUID())
            let reader = SearchMapSessionReader(service: try service(t), currentContext: { context }, manualAreaSelection: ManualMapAreaSelection())
            let q = try query(), task = Task { try await reader.cityNodes(q) }
            for _ in 0..<100 { let pending = await t.pending; if pending { break }; await Task.yield() }
            if change == "area" { reader.selectManualArea(try .manual(latitude: "32", longitude: "122")) }
            else { context = try .init(accountID: change == "owner" ? 8 : 7, epoch: 2, token: "synthetic-token", manualMapApprovalRevision: change == "approval" ? nil : UUID()) }
            await t.finish(); do { _ = try await task.value; XCTFail("stale response") } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
}
