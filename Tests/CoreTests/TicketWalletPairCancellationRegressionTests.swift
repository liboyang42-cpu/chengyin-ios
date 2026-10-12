import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Root repair handoff only. These expectations expose the pinned baseline defect.
/// NOT_RUN here; do not count them as passed tests or silently weaken expectations.
@MainActor final class TicketWalletPairCancellationRegressionTests: XCTestCase {
    private actor Pair: HTTPTransport {
        let reversed: Bool
        init(reversed: Bool = false) { self.reversed = reversed }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            if body.contains("name=\"owner_type\"\r\n\r\n1\r\n") != reversed {
                return (Data(#"{"code":401,"data":false}"#.utf8), 200)
            }
            throw CancellationError()
        }
    }
    private func service() throws -> TicketWalletService {
        try .init(configuration: APIConfiguration(baseURL: URL(string:"https://example.test/native")!), transport: Pair())
    }
    func testCancellationFromEitherLaneOutranksAnEarlierLane401() async throws {
        do { _ = try await service().wallet(token:"synthetic-7"); XCTFail("Cancelled aggregate published") }
        catch { XCTAssertTrue(error is CancellationError, "Stale 401 must not outrank another lane cancellation: \(error)") }
    }
    func testCancelledPairDoesNotCallReaderUnauthorizedCallback() async throws {
        let captured = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7")
        var unauthorized = 0
        let reader = TicketWalletSessionReader(service:try service(),currentSession:{ captured },onUnauthorized:{ _ in unauthorized += 1 })
        do { _ = try await reader.ticketWallet(); XCTFail("Cancelled aggregate published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized,0)
    }
    func testReverseLaneCancellationAlsoOutranksUnauthorized() async throws {
        let api = try TicketWalletService(configuration: APIConfiguration(baseURL: URL(string:"https://example.test/native")!), transport: Pair(reversed:true))
        do { _ = try await api.wallet(token:"synthetic-7"); XCTFail("Cancelled aggregate published") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testViewerChangeRotatesReaderScope() throws {
        var current = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:1,role:"player")
        let reader = TicketWalletSessionReader(service:try service(),currentSession:{ current })
        let oldScope = reader.scope
        current = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:2,role:"player")
        XCTAssertNotEqual(reader.scope,oldScope)
        let newScope = reader.scope
        XCTAssertEqual(reader.scope,newScope)
    }
    func testViewerRevisionIsPartOfSessionIdentity() throws {
        let a = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:1,role:"player")
        let b = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:2,role:"player")
        XCTAssertNotEqual(a,b)
    }
    func testRoleChangeIsPartOfSessionIdentity() throws {
        let a = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:1,role:"player")
        let b = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",viewerRevision:1,role:"club")
        XCTAssertNotEqual(a,b)
    }
    func testRoleBytesCannotNormalizeDifferentSourceIdentity() throws {
        let a = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",role:"\u{00e9}")
        let b = try TicketWalletReadSession(accountID:7,epoch:1,token:"synthetic-7",role:"e\u{0301}")
        XCTAssertNotEqual(a,b)
    }

}
