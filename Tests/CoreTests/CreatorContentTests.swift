import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
private actor CreatorContentTransport: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), status) }
}
private actor CreatorContentSuspendedTransport: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { continuation = $0 } }
    func wait() async { while continuation == nil { await Task.yield() } }
    func finish(_ json: String, status: Int = 200) { continuation?.resume(returning: (Data(json.utf8), status)); continuation = nil }
}
final class CreatorContentTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> CreatorContentService {
        try CreatorContentService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func testProjectExactContract() async throws {
        let transport = CreatorContentTransport(CreatorContentSyntheticFixtures.projectsJSON)
        let page = try await service(transport).projects(query: .init(type: "topic", state: "draft", ownerType: "club"), token: "synthetic-token")
        XCTAssertEqual(page.rows.count, 3); XCTAssertEqual(page.total, 208); XCTAssertTrue(page.isTruncated)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/project/my"); XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        for (key, value) in [("type", "topic"), ("state", "draft"), ("ownerType", "club"), ("pageNum", "1"), ("pageSize", "200")] {
            XCTAssertTrue(body.contains("name=\"\(key)\"\r\n\r\n\(value)\r\n"))
        }
        XCTAssertFalse(body.contains("scope")); XCTAssertFalse(body.contains("memberId"))
    }
    func testCenterExactContract() async throws {
        let transport = CreatorContentTransport(CreatorContentSyntheticFixtures.centerJSON)
        let center = try await service(transport).center(token: "synthetic-token")
        XCTAssertEqual(center.status, .approved); XCTAssertEqual(center.recentIncome.first?.amount, "001.2300")
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.url?.path, "/test/api/creator/center")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
    }
    func testBusinessIdentityDoesNotCollide() throws {
        let page = try decode(CreatorContentProjectPage.self, #"{"rows":[{"id":1,"bizType":"topic"},{"id":1,"bizType":"activity"},{"id":1,"bizType":"topic"}]}"#)
        XCTAssertEqual(page.rows.map(\.id), ["topic:1", "activity:1"])
        XCTAssertEqual(page.rows.map(\.destination), [.topic(1), .activity(1)])
    }
    func testUnknownBusinessNeverGuessesDestination() throws {
        let row = try decode(CreatorContentProject.self, #"{"id":1,"bizType":"future"}"#)
        XCTAssertNil(row.destination)
    }
    func testInvalidSourceIDRejected() { XCTAssertThrowsError(try decode(CreatorContentProject.self, #"{"id":0,"bizType":"topic"}"#)) }
    func testTemplateRoutesExactly() throws { XCTAssertEqual(try decode(CreatorContentProject.self, #"{"id":7,"bizType":"template"}"#).destination, .playTemplate(7)) }
    func testAllCreatorStatusesDistinct() throws {
        for status in ["not_applied", "pending", "approved", "rejected"] {
            XCTAssertEqual(try decode(CreatorContentCenter.self, "{\"applyStatus\":\"\(status)\"}").status.rawValue, status)
        }
    }
    func testUnknownCreatorStateFailsClosed() throws { XCTAssertEqual(try decode(CreatorContentCenter.self, #"{"applyStatus":"future"}"#).status, .unknown) }
    func testMissingMetricIsNotZero() throws { XCTAssertNil(try decode(CreatorContentCenter.self, #"{"applyStatus":"approved"}"#).metric) }
    func testPartialMetricKeepsMissingValues() throws {
        let value = try decode(CreatorContentCenter.self, #"{"metric":{"contentCount":0}}"#)
        XCTAssertEqual(value.metric?.contentCount, 0); XCTAssertNil(value.metric?.viewCount)
    }
    func testRejectReasonProfilePrecedence() throws {
        XCTAssertEqual(try decode(CreatorContentCenter.self, #"{"profile":{"rejectReason":"profile"},"rejectReason":"top"}"#).rejectReason, "profile")
    }
    func testTotalFallbackAndString() throws {
        for total in ["null", "-1", "\"bad\""] {
            XCTAssertEqual(try decode(CreatorContentProjectPage.self, "{\"rows\":[{\"id\":1,\"bizType\":\"topic\"}],\"total\":\(total)}").total, 1)
        }
    }
    func testInvalidFilterDoesNotDispatch() async throws {
        let transport = CreatorContentTransport("{}")
        do { _ = try await service(transport).projects(query: .init(type: "guessed"), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testInvalidTokenDoesNotDispatch() async throws {
        let transport = CreatorContentTransport("{}")
        do { _ = try await service(transport).center(token: ""); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
    func testUnauthorizedEnvelopes() async throws {
        for (json, status) in [("{}", 401), (#"{"code":401}"#, 200)] {
            do { _ = try await service(CreatorContentTransport(json, status: status)).center(token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testMalformedSuccessRejected() async throws {
        do { _ = try await service(CreatorContentTransport(#"{"code":200,"data":7}"#)).center(token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    @MainActor func testCurrentUnauthorizedInvalidates() async throws {
        let session = try CreatorContentReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        var invalidations = 0
        let reader = CreatorContentSessionReader(service: try service(CreatorContentTransport("{}", status: 401)), currentSession: { session }, onUnauthorized: { _ in invalidations += 1 })
        do { _ = try await reader.center(); XCTFail() } catch {}
        XCTAssertEqual(invalidations, 1)
    }
    @MainActor func testStaleUnauthorizedCannotInvalidateNewEpoch() async throws {
        let transport = CreatorContentSuspendedTransport()
        var session: CreatorContentReadSession? = try .init(accountID: 1, epoch: 1, token: "synthetic-token")
        var invalidations = 0
        let reader = CreatorContentSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in invalidations += 1 })
        let task = Task { try await reader.center() }
        await transport.wait()
        session = try .init(accountID: 1, epoch: 2, token: "synthetic-token")
        await transport.finish("{}", status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(invalidations, 0)
    }
    @MainActor func testCancellationDiscardsSuccess() async throws {
        let transport = CreatorContentSuspendedTransport()
        let session = try CreatorContentReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let reader = CreatorContentSessionReader(service: try service(transport), currentSession: { session })
        let task = Task { try await reader.center() }; await transport.wait(); task.cancel()
        await transport.finish(CreatorContentSyntheticFixtures.centerJSON)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testModelHidesForeignScope() async {
        let model = CreatorContentReadModel<Int>(); let scope = UUID()
        await model.load(scope: scope, currentScope: { scope }) { 7 }
        XCTAssertEqual(model.visibleValue(scope: scope), 7); XCTAssertNil(model.visibleValue(scope: UUID()))
        model.invalidate(); XCTAssertNil(model.visibleValue(scope: scope))
    }
    @MainActor func testMissingSessionFailsBeforeDispatch() async throws {
        let transport = CreatorContentTransport("{}")
        let reader = CreatorContentSessionReader(service: try service(transport), currentSession: { nil })
        do { _ = try await reader.center(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let count = await transport.requests.count; XCTAssertEqual(count, 0)
    }
}
