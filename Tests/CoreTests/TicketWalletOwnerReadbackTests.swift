import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor L4TicketOwnerTransport: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(json.utf8), status)
    }
}

private actor L4TicketOwnerSuspendedTransport: HTTPTransport {
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async { while pending == nil { await Task.yield() } }
    func finish(_ json: String) {
        let reply = pending; pending = nil
        reply?.resume(returning: (Data(json.utf8), 200))
    }
}

/// Synthetic identifiers only. This suite never calls a backend or changes a grant.
@MainActor final class TicketWalletOwnerReadbackTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> TicketWalletService {
        try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.test/native/")!), transport: transport)
    }
    private func session(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-ticket-token",
                         revision: UInt64 = 1, role: String = "player") throws -> TicketWalletReadSession {
        try .init(accountID: account, epoch: epoch, token: token, viewerRevision: revision, role: role)
    }

    func testSessionAcceptsBuyerAndIgnoresNestedPublisher() async throws {
        let current = try session()
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":{"id":71,"memberId":7,"registrationStatus":97,"cmsActivity":{"memberId":900,"name":"Synthetic activity"}}}"#)
        let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current })
        let result = try await reader.ticketDetail(id: 71)
        XCTAssertEqual(result.id, 71)
        XCTAssertEqual(result.title, "Synthetic activity")
        XCTAssertEqual(result.registrationStatus, 97)
        XCTAssertEqual(result.status, .unknown)
    }

    func testSessionRejectsOtherBuyerEvenWhenPublisherMatches() async throws {
        let current = try session()
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":{"id":71,"memberId":8,"cmsActivity":{"memberId":7}}}"#)
        var invalidations = 0
        let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
        do { _ = try await reader.ticketDetail(id: 71); XCTFail("Other buyer was returned") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        XCTAssertEqual(invalidations, 0)
    }

    func testMissingNullMalformedAndNonpositiveBuyerFailClosed() async throws {
        let current = try session()
        let fragments = ["", #", "memberId":null"#, #", "memberId":0"#, #", "memberId":-1"#,
                         #", "memberId":"7""#, #", "memberId":7.5"#, #", "memberId":true"#,
                         #", "cmsTopic":{"memberId":7}"#]
        for fragment in fragments {
            let json = #"{"code":200,"data":{"id":71"# + fragment + "}}"
            let transport = L4TicketOwnerTransport(json)
            let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current })
            do { _ = try await reader.ticketDetail(id: 71); XCTFail("Buyer was not established") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }

    func testInvalidExpectedAccountIsRejectedBeforeDispatch() async throws {
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":{"id":71,"memberId":7}}"#)
        let api = try service(transport)
        for account in [0, -1] {
            do { _ = try await api.detail(id: 71, token: "synthetic-ticket-token", expectedAccountID: account); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testLegacyDirectReadWithoutExpectedAccountRemainsCompatible() async throws {
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":{"id":71}}"#)
        let result = try await service(transport).detail(id: 71, token: "synthetic-ticket-token")
        XCTAssertEqual(result.id, 71)
    }

    func testBuyerIsNeverAddedAsRequestIdentityOverride() async throws {
        let current = try session()
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":{"id":71,"memberId":7}}"#)
        let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current })
        _ = try await reader.ticketDetail(id: 71)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/native/api/registration/info")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-ticket-token")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n71\r\n"))
        for field in ["memberId", "member_id", "accountID", "owner_type"] {
            XCTAssertFalse(body.contains("name=\"\(field)\""))
        }
    }

    func testMissingOrWrongRegistrationKeepsUnavailableMeaning() async throws {
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#,
                     #"{"code":200,"data":{"id":72,"memberId":7}}"#] {
            let transport = L4TicketOwnerTransport(json)
            do { _ = try await service(transport).detail(id: 71, token: "synthetic-ticket-token", expectedAccountID: 7); XCTFail() }
            catch { XCTAssertEqual(error as? TicketWalletReadFailure, .unavailable) }
        }
    }

    func testCurrentHTTPAndBusiness401StillInvalidateOnce() async throws {
        let current = try session()
        for (json, status) in [("not JSON", 401), (#"{"code":401,"msg":[],"data":false}"#, 200)] {
            let transport = L4TicketOwnerTransport(json, status: status)
            var invalidations = 0
            let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
            do { _ = try await reader.ticketDetail(id: 71); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertEqual(invalidations, 1)
        }
    }

    func testBusinessDenialIsNotReclassifiedAsMissingOwner() async throws {
        let current = try session()
        let transport = L4TicketOwnerTransport(#"{"code":403,"msg":"Synthetic denial","data":false}"#)
        let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current })
        do { _ = try await reader.ticketDetail(id: 71); XCTFail() }
        catch { XCTAssertEqual(error as? TicketWalletReadFailure, .rejected(code: 403, message: "Synthetic denial")) }
    }

    func testRetiredAccountEpochTokenViewerAndRoleDiscardLateSuccessOr401() async throws {
        let original = try session()
        let replacements: [TicketWalletReadSession?] = [nil, try session(account: 8), try session(epoch: 2),
            try session(token: "synthetic-rotated-token"), try session(revision: 2), try session(role: "club")]
        for replacement in replacements {
            for reply in [#"{"code":200,"data":{"id":71,"memberId":7}}"#, #"{"code":401}"#] {
                var current: TicketWalletReadSession? = original
                var invalidations = 0
                let transport = L4TicketOwnerSuspendedTransport()
                let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
                let task = Task { try await reader.ticketDetail(id: 71) }
                await transport.waitForRequest()
                current = replacement
                await transport.finish(reply)
                do { _ = try await task.value; XCTFail("Retired read was returned") }
                catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(invalidations, 0)
            }
        }
    }

    func testCancelledReadDiscardsLateSuccessOr401() async throws {
        let current = try session()
        for reply in [#"{"code":200,"data":{"id":71,"memberId":7}}"#, #"{"code":401}"#] {
            let transport = L4TicketOwnerSuspendedTransport()
            var invalidations = 0
            let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in invalidations += 1 })
            let task = Task { try await reader.ticketDetail(id: 71) }
            await transport.waitForRequest()
            task.cancel()
            await transport.finish(reply)
            do { _ = try await task.value; XCTFail() }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(invalidations, 0)
        }
    }

    func testListStillUsesTheOriginalTwoLanesWithoutIdentityOverride() async throws {
        let current = try session()
        let transport = L4TicketOwnerTransport(#"{"code":200,"data":[]}"#)
        let reader = TicketWalletSessionReader(service: try service(transport), currentSession: { current })
        let result = try await reader.ticketWallet()
        XCTAssertTrue(result.tickets.isEmpty)
        XCTAssertNil(result.partialFailure)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.url?.path, "/native/api/registration/list")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-ticket-token")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"owner_type\""))
            XCTAssertFalse(body.contains("name=\"memberId\""))
        }
    }
}
