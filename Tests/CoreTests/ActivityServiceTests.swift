import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ActivityFixtureTransport: HTTPTransport {
    let json:String
    var request:URLRequest?
    init(_ json:String) { self.json=json }
    func send(_ request:URLRequest) async throws -> (Data,Int) {
        self.request=request;return (Data(json.utf8),200)
    }
}
final class ActivityServiceTests: XCTestCase {
    private func service(_ transport:ActivityFixtureTransport) throws -> ActivityService {
        try ActivityService(configuration:APIConfiguration(baseURL:URL(string:"https://api.example.com/prod-api")!),transport:transport)
    }
    func testListPathMultipartPaginationAndCredential() async throws {
        let transport=ActivityFixtureTransport(#"{"code":200,"data":{"rows":[]}}"#)
        let rows=try await service(transport).list(page:2,keyword:"walk",token:"fixture")
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(transport.request?.url?.path,"/prod-api/api/activity/list")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField:"Authorization"),"fixture")
        let body=String(data:transport.request!.httpBody!,encoding:.utf8)!
        XCTAssertTrue(body.contains("name=\"pageNum\"\r\n\r\n2"))
        XCTAssertTrue(body.contains("name=\"keyword\"\r\n\r\nwalk"))
    }
    func testClubGateIsAnExplicitTerminalState() async throws {
        let transport=ActivityFixtureTransport(#"{"code":200,"data":{"gate":true,"clubId":"7","message":"Club access required"}}"#)
        let access=try await service(transport).detail(id:8)
        XCTAssertEqual(access,.clubRequired(clubID:7,message:"Club access required"))
    }
    func testUnknownClubIDDoesNotBecomeNavigableZero() async throws {
        let transport=ActivityFixtureTransport(#"{"code":200,"data":{"gate":true,"clubId":0}}"#)
        let access=try await service(transport).detail(id:8)
        XCTAssertEqual(access,.clubRequired(clubID:nil,message:nil))
    }
    func testMissingTicketPriceAndInventoryRemainUnknown() async throws {
        let transport=ActivityFixtureTransport(#"{"code":200,"data":{"id":8,"name":"Activity","omsTicketList":[{"id":9,"name":"Ticket"}]}}"#)
        guard case .allowed(let detail)=try await service(transport).detail(id:8) else { return XCTFail("Expected detail") }
        let ticket=try XCTUnwrap(detail.tickets.first)
        XCTAssertNil(ticket.price);XCTAssertFalse(ticket.isConfirmedFree)
        XCTAssertNil(ticket.remainingInventory);XCTAssertFalse(ticket.isSoldOut)
    }
    func testInvalidTicketIDAndNegativePriceAreRejected() {
        for json in [#"{"id":0,"name":"Ticket"}"#, #"{"id":1,"name":"Ticket","price":-1}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityTicket.self,from:Data(json.utf8)))
        }
    }
    func testBusinessFailureIsNotAnEmptyList() async throws {
        let transport=ActivityFixtureTransport(#"{"code":500,"data":{"rows":[]}}"#)
        do { _=try await service(transport).list();XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? APIError,.businessCode(500)) }
    }
    func testInvalidPagingDoesNotSendRequest() async throws {
        let transport=ActivityFixtureTransport("{}")
        do { _=try await service(transport).list(page:0);XCTFail("Must fail") }
        catch { XCTAssertEqual(error as? APIError,.invalidRequest) }
        XCTAssertNil(transport.request)
    }
}
