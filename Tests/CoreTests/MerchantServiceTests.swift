import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic only: never creates a URLSession or opens a socket.
private final class MerchantFixtureTransport: HTTPTransport {
    var json = #"{"code":200,"data":{}}"#
    var status = 200
    var error: Error?
    private(set) var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let error { throw error }
        return (Data(json.utf8), status)
    }
}
final class MerchantServiceTests: XCTestCase {
    private func service(_ transport: MerchantFixtureTransport) throws -> MerchantService {
        try MerchantService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prod-api")!), transport: transport)
    }
    private func access(role: String = "MERCHANT_OWNER", permissions: [String] = ["merchant:finance:read", "merchant:order:read", "merchant:project:manage"], active: Bool = true) throws -> MerchantAccess {
        let data = try JSONSerialization.data(withJSONObject: ["active": active, "merchant": ["id": 31], "roleCode": role, "permissions": permissions])
        return try JSONDecoder().decode(MerchantAccess.self, from: data)
    }
    private func assertRequest(_ request: URLRequest, path: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/prod-api/" + path, file: file, line: line)
        XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "fixture-token", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json", file: file, line: line)
        XCTAssertEqual(request.timeoutInterval, 20, file: file, line: line)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, file: file, line: line)
        XCTAssertNil(request.url?.query, file: file, line: line)
    }
    func testAccessUsesBodylessPOSTAndRawToken() async throws {
        let t = MerchantFixtureTransport()
        t.json = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}}"#
        let value = try await service(t).access(token: "fixture-token")
        XCTAssertTrue(value.isOwner)
        let request = try XCTUnwrap(t.requests.first)
        assertRequest(request, path: "api/merchant/access/me")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }
    func testDashboardTodoAndEventsUseExactReadContracts() async throws {
        let t = MerchantFixtureTransport(), a = try access()
        _ = try await service(t).dashboard(access: a, token: "fixture-token")
        assertRequest(t.requests[0], path: "api/merchant/dashboard")
        XCTAssertNil(t.requests[0].httpBody)
        _ = try await service(t).todo(access: a, token: "fixture-token")
        assertRequest(t.requests[1], path: "api/merchant/todo-summary")
        XCTAssertNil(t.requests[1].httpBody)
        t.json = #"{"code":200,"data":[{"content":"Fixture","time":"12-31 23:59"}]}"#
        let events = try await service(t).events(access: a, token: "fixture-token")
        assertRequest(t.requests[2], path: "api/merchant/events")
        XCTAssertEqual(t.requests[2].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: t.requests[2].httpBody!, encoding: .utf8), "{}")
        XCTAssertEqual(events.first?.time, "12-31 23:59")
    }
    func testOrdersUseExactJSONFiltersAndNeverSendMerchantID() async throws {
        let t = MerchantFixtureTransport()
        t.json = #"{"code":200,"data":[{"id":7,"status":1,"payAmount":"9.00"}]}"#
        let rows = try await service(t).orders(access: access(), filter: .init(status: .awaitingShipment, aftersaleStatus: .processing), token: "fixture-token")
        XCTAssertEqual(rows.first?.id, 7)
        let request = try XCTUnwrap(t.requests.first)
        assertRequest(request, path: "api/merchant/orders")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Int])
        XCTAssertEqual(fields, ["status": 1, "aftersaleStatus": 2])
        XCTAssertNil(fields["afterSaleStatus"])
        XCTAssertNil(fields["mmsMerchantId"])
    }
    func testAllOrdersSendsEmptyJSONAndAcceptsRowsContainer() async throws {
        let t = MerchantFixtureTransport()
        t.json = #"{"code":200,"data":{"rows":[{"id":8}]}}"#
        let rows = try await service(t).orders(access: access(), token: "fixture-token")
        XCTAssertEqual(rows.first?.id, 8)
        XCTAssertEqual(String(data: t.requests[0].httpBody!, encoding: .utf8), "{}")
    }
    func testHostedProjectsSendMerchantScopeAndSourceFirstPage() async throws {
        let t = MerchantFixtureTransport()
        t.json = #"{"code":200,"data":{"rows":[{"id":7,"bizType":"activity","title":"Fixture"}],"total":1}}"#
        let page = try await service(t).projects(access: access(), token: "fixture-token")
        XCTAssertEqual(page.rows.first?.title, "Fixture")
        let request = try XCTUnwrap(t.requests.first)
        assertRequest(request, path: "api/project/my")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = try XCTUnwrap(String(data: request.httpBody!, encoding: .utf8))
        for (field, value) in ["type":"all", "state":"all", "ownerType":"all", "scope":"MERCHANT", "pageNum":"1", "pageSize":"200"] {
            XCTAssertTrue(body.contains("name=\"\(field)\"\r\n\r\n\(value)\r\n"))
        }
        XCTAssertFalse(body.contains("mmsMerchantId"))
    }
    func testPermissionDenialsMakeZeroRequests() async throws {
        let t = MerchantFixtureTransport(), s = try service(t)
        let finance = try access(role: "MERCHANT_FINANCE")
        let noFinance = try access(permissions: [])
        let inactive = try access(active: false)
        do { _ = try await s.dashboard(access: finance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.dashboard(access: noFinance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.todo(access: finance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.events(access: finance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.orders(access: noFinance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.projects(access: noFinance, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        do { _ = try await s.todo(access: inactive, token: "fixture-token"); XCTFail() } catch { XCTAssertEqual(error as? MerchantReadError, .accessDenied) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testDeniedOrExpiredResponsesDoNotBecomeEmptyData() async throws {
        for (status, json, expectedAPI, expectedMerchant) in [
            (401, "{}", APIError.unauthorized as APIError?, nil as MerchantReadError?),
            (200, #"{"code":401}"#, .unauthorized, nil),
            (403, "{}", nil, .accessDenied),
            (200, #"{"code":403}"#, nil, .accessDenied),
            (503, "{}", .httpStatus(503), nil),
            (200, #"{"code":500,"msg":"fixture failure"}"#, .businessCode(500), nil)
        ] {
            let t = MerchantFixtureTransport(); t.status = status; t.json = json
            do { _ = try await service(t).orders(access: access(), token: "fixture-token"); XCTFail() }
            catch {
                if let expectedAPI { XCTAssertEqual(error as? APIError, expectedAPI) }
                if let expectedMerchant { XCTAssertEqual(error as? MerchantReadError, expectedMerchant) }
            }
            XCTAssertEqual(t.requests.count, 1)
        }
    }
    func testMalformedResponsesDoNotClaimAnEmptyList() async throws {
        for json in ["not json", "{}", #"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":[true]}"#] {
            let t = MerchantFixtureTransport(); t.json = json
            do { _ = try await service(t).orders(access: access(), token: "fixture-token"); XCTFail(json) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse, json) }
        }
    }
    func testBlankOrUnsafeTokenMakesZeroRequests() async throws {
        let t = MerchantFixtureTransport()
        for token in ["", " ", "fixture\r\nheader", "fixture\tvalue"] {
            do { _ = try await service(t).access(token: token); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testTransportFailureIsNotRetried() async throws {
        let t = MerchantFixtureTransport(); t.error = URLError(.notConnectedToInternet)
        do { _ = try await service(t).access(token: "fixture-token"); XCTFail() }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(t.requests.count, 1)
    }
}
