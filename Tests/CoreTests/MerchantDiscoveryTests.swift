import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor MerchantDiscoveryTransport: HTTPTransport {
    var response = #"{"code":200,"data":[]}"#
    var status = 200
    private(set) var requests: [URLRequest] = []
    func set(_ response: String, status: Int = 200) { self.response = response; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(response.utf8), status)
    }
}
private actor MerchantDiscoverySuspendedTransport: HTTPTransport {
    var pending: Bool { continuation != nil }
    var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { continuation = $0 } }
    func finish() { continuation?.resume(returning: (Data(#"{"code":200,"data":[]}"#.utf8), 200)); continuation = nil }
}
final class MerchantDiscoveryTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> SearchMapService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func row(_ json: String) throws -> MerchantDiscoveryRow { try JSONDecoder().decode(MerchantDiscoveryRow.self, from: Data(json.utf8)) }
    func testExactSixWireTagsAndAllUsesEmptyName() async throws {
        XCTAssertEqual(MerchantDiscoveryTag.allCases.map(\.rawValue), ["", "夜间友好", "可拍照", "适合组队", "宠物友好", "安静", "适合亲子"])
        let t = MerchantDiscoveryTransport()
        for tag in MerchantDiscoveryTag.allCases { _ = try await service(t).merchantDiscovery(tag: tag) }
        let requests = await t.requests
        XCTAssertEqual(requests.count, 7)
        for (request, tag) in zip(requests, MerchantDiscoveryTag.allCases) {
            XCTAssertEqual(request.url?.path, "/test/api/merchant/list")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
            XCTAssertEqual(body, tag.fields)
            XCTAssertNil(body["status"]); XCTAssertNil(body["delFlag"])
        }
    }
    func testSignedInRequestUsesRawAuthorizationAndBareDataList() async throws {
        let t = MerchantDiscoveryTransport()
        await t.set(#"{"code":200,"data":[{"id":71,"memberId":92,"name":"Example"}]}"#)
        let value = try await service(t).merchantDiscovery(tag: .teams, token: "synthetic-token")
        XCTAssertEqual(value.first?.target, .ownerMemberID(PublicMerchantOwnerID(92)!))
        let requests = await t.requests
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testChipsUseRoleFirstUnicodeSeparatorsAndThreeMaximum() throws {
        let value = try row(#"{"id":1,"cityRole":"  Gathering spot  ","tags":" ;夜间友好， 可拍照；适合组队、安静,ignored"}"#)
        XCTAssertEqual(value.chips, ["Gathering spot", "夜间友好", "可拍照"])
        XCTAssertEqual(try row(#"{"id":1,"tags":"one;two,three，four"}"#).chips, ["one", "two", "three"])
    }
    func testMissingOwnerNeverFallsBackToMerchantRowIDAndSummaryFallback() throws {
        for json in [#"{"id":71}"#, #"{"id":71,"memberId":0}"#, #"{"id":71,"memberId":-1}"#] {
            XCTAssertNil(try row(json).target)
        }
        let value = try row(#"{"id":71,"name":"  ","slogan":" \n ","description":" readable ","coverImage":"cover"}"#)
        XCTAssertNil(value.displayName); XCTAssertEqual(value.summary, "readable"); XCTAssertEqual(value.image, "cover")
    }
    func testMalformedAndBusinessFailureNeverBecomeEmptySuccess() async throws {
        let t = MerchantDiscoveryTransport()
        for json in [#"{"code":200,"data":{"rows":[]}}"#, #"{"code":403,"data":[]}"#, #"{"data":[]}"#] {
            await t.set(json)
            do { _ = try await service(t).merchantDiscovery(tag: .all); XCTFail("Must fail") } catch {}
        }
    }
    @MainActor func testLogoutDuringReadDiscardsResponseWithoutUnauthorizedCallback() async throws {
        let t = MerchantDiscoverySuspendedTransport()
        var context = try SearchMapContext(accountID: 8, epoch: 1, token: "synthetic")
        var expired = false
        let reader = SearchMapSessionReader(service: try service(t), currentContext: { context }, onUnauthorized: { _ in expired = true })
        let task = Task { try await reader.merchantDiscovery(tag: .quiet) }
        while !(await t.pending) { await Task.yield() }
        context = .init(guestEpoch: 2); await t.finish()
        do { _ = try await task.value; XCTFail("Stale result must be discarded") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(expired)
    }
    @MainActor func testNewTagAndDismissInvalidateOlderQuery() {
        let gate = SearchMapQueryGate(), scope = UUID()
        let first = gate.begin(scope: scope), second = gate.begin(scope: scope)
        XCTAssertFalse(gate.accepts(first, scope: scope)); XCTAssertTrue(gate.accepts(second, scope: scope))
        gate.invalidate(); XCTAssertFalse(gate.accepts(second, scope: scope))
    }
}
