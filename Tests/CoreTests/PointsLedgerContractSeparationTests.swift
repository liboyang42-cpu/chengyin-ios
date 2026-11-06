import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PointsLedgerTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var payload: String
    init(_ payload: String) { self.payload = payload }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(payload.utf8), 200) }
}

/// I07: POST api/points/list (assetPoints) is one full, unpaged list; api/user/points/list (points) is a
/// paged table. Neither borrows the other's page fields, wrapper or load-more semantics.
@MainActor final class PointsLedgerContractSeparationTests: XCTestCase {
    private func service(_ transport: PointsLedgerTransport) throws -> WalletCommerceService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testAssetPointsIsOneFullListWithoutPageFieldsOrLoadMore() async throws {
        let transport = PointsLedgerTransport(#"{"code":200,"data":[{"id":3,"changePoints":"5","afterPoints":"25"},{"id":2,"changePoints":"-5","afterPoints":"20"}]}"#)
        let list = try await service(transport).ledger(.assetPoints, token: "synthetic-token")
        XCTAssertEqual(list.rows.map(\.id), [3, 2]); XCTAssertNil(list.total); XCTAssertNil(list.page); XCTAssertNil(list.pageSize)
        XCTAssertFalse(list.hasMore(loadedCount: list.rows.count))
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/points/list"])
        for field in ["pageNum", "pageSize", "change_type"] { XCTAssertFalse(body(transport.requests[0]).contains("name=\"\(field)\"")) }
        for page in [2, 3] {
            do { _ = try await service(transport).ledger(.assetPoints, page: page, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertEqual(transport.requests.count, 1, "A later page of the full list is never requested")
    }
    func testPagedPointsAlwaysSendsPageFieldsAndKeepsTableTotals() async throws {
        let transport = PointsLedgerTransport(#"{"code":200,"data":{"rows":[{"id":9,"changePoints":"1"}],"total":"41"}}"#)
        let page = try await service(transport).ledger(.points, page: 2, pageSize: 20, token: "synthetic-token")
        XCTAssertEqual(page.total, 41); XCTAssertEqual(page.page, 2); XCTAssertEqual(page.pageSize, 20)
        XCTAssertTrue(page.hasMore(loadedCount: 21))
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/user/points/list"])
        let sent = body(transport.requests[0])
        XCTAssertTrue(sent.contains("name=\"pageNum\"\r\n\r\n2")); XCTAssertTrue(sent.contains("name=\"pageSize\"\r\n\r\n20"))
    }
    func testNeitherPointsSurfaceAcceptsTheOtherWrapper() async throws {
        // A table where the full list is expected (or a bare array where a table is expected) is a contract
        // mismatch, not an empty or single-page result.
        let table = PointsLedgerTransport(#"{"code":200,"data":{"rows":[{"id":1}],"total":1}}"#)
        do { _ = try await service(table).ledger(.assetPoints, token: "synthetic-token"); XCTFail() } catch {}
        let array = PointsLedgerTransport(#"{"code":200,"data":[{"id":1}]}"#)
        do { _ = try await service(array).ledger(.points, token: "synthetic-token"); XCTFail() } catch {}
    }
}
