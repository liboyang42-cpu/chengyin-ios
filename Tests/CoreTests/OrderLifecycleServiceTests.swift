import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor LifecycleRecordingTransport: HTTPTransport {
    let body: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(_ body: String, status: Int = 200) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), status) }
}
private actor LifecycleSuspendedTransport: HTTPTransport {
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { pending = $0 } }
    func isReady() -> Bool { pending != nil }
    func finish(_ body: String) { pending?.resume(returning: (Data(body.utf8), 200)); pending = nil }
}
final class OrderLifecycleServiceTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> OrderLifecycleService {
        try OrderLifecycleService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    func testExactDetailRequestHasOnlyIDAndNoMutationEndpoint() async throws {
        let t = LifecycleRecordingTransport("{\"code\":200,\"data\":" + OrderLifecycleSyntheticFixtures.pending + "}")
        let value = try await service(t).detail(id: 9701, token: "synthetic-session")
        XCTAssertEqual(value.id, 9701)
        let requests = await t.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/registration/info")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-session")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n9701\r\n"))
        XCTAssertFalse(body.contains("requestId")); XCTAssertFalse(body.contains("quoteSign"))
    }
    func testCouponStatusUsesHistoryIDAnd410IsUnavailable() async throws {
        let t = LifecycleRecordingTransport(#"{"code":410,"msg":"Sample expired"}"#)
        do { _ = try await service(t).couponStatus(historyID: 9710, token: "synthetic-session"); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? OrderLifecycleFailure, .unavailable) }
        let requests = await t.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/test/api/coupon/status")
        XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("name=\"couponHistoryId\"") == true)
    }
    func testWrongIDAndMissingDataAreMalformed() async throws {
        for raw in [#"{"code":200,"data":{"id":8}}"#, #"{"code":200}"#] {
            do { _ = try await service(LifecycleRecordingTransport(raw)).detail(id: 7, token: "synthetic-session"); XCTFail("Unexpected success") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testExpectedAccountIDRejectsMissingOrMismatchedTopLevelBuyerMemberIdEvenWhenNestedOwnerMatches() async throws {
        // Matching top-level memberId succeeds and remains distinct from nested ownerMemberID.
        let matchingJSON = #"{"code":200,"data":{"id":41,"memberId":7,"cmsActivity":{"name":"Activity","memberId":999}}}"#
        let detail = try await service(LifecycleRecordingTransport(matchingJSON)).detail(id: 41, token: "synthetic-session", expectedAccountID: 7)
        XCTAssertEqual(detail.id, 41)
        XCTAssertEqual(detail.memberID, 7)
        XCTAssertEqual(detail.ownerMemberID, 999)

        // Wrong top-level memberId (even if nested cmsActivity.memberId matches expectedAccountID) is rejected.
        let wrongBuyerJSON = #"{"code":200,"data":{"id":41,"memberId":8,"cmsActivity":{"name":"Activity","memberId":7}}}"#
        do {
            _ = try await service(LifecycleRecordingTransport(wrongBuyerJSON)).detail(id: 41, token: "synthetic-session", expectedAccountID: 7)
            XCTFail("Expected malformedResponse for wrong top-level buyer memberId")
        } catch {
            XCTAssertEqual(error as? APIError, .malformedResponse)
        }

        // Missing top-level memberId (even if nested cmsActivity.memberId or cmsTopic.memberId matches expectedAccountID) is rejected.
        for missingBuyerJSON in [
            #"{"code":200,"data":{"id":41,"cmsActivity":{"name":"Activity","memberId":7}}}"#,
            #"{"code":200,"data":{"id":41,"cmsTopic":{"name":"Topic","memberId":7}}}"#
        ] {
            do {
                _ = try await service(LifecycleRecordingTransport(missingBuyerJSON)).detail(id: 41, token: "synthetic-session", expectedAccountID: 7)
                XCTFail("Expected malformedResponse for missing top-level buyer memberId")
            } catch {
                XCTAssertEqual(error as? APIError, .malformedResponse)
            }
        }
    }
    func testUnauthorizedPrecedesMalformedData() async throws {
        do { _ = try await service(LifecycleRecordingTransport(#"{"code":401,"data":"bad"}"#)).detail(id: 7, token: "synthetic-session"); XCTFail("Unexpected success") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testInvalidIDMakesZeroRequests() async throws {
        let t = LifecycleRecordingTransport("{}")
        do { _ = try await service(t).detail(id: 0, token: "synthetic-session"); XCTFail("Unexpected success") } catch {}
        let requests = await t.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testStale401CannotSignOutReplacementSession() async throws {
        let transport = LifecycleSuspendedTransport()
        var session: OrderLifecycleSession? = try OrderLifecycleSession(accountID: 100, epoch: 1, token: "synthetic-old")
        var expired = 0
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        let task = Task { try await reader.detail(id: 7) }
        while !(await transport.isReady()) { await Task.yield() }
        session = try OrderLifecycleSession(accountID: 100, epoch: 2, token: "synthetic-new")
        await transport.finish(#"{"code":401}"#)
        do { _ = try await task.value; XCTFail("Unexpected success") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expired, 0)
    }
    @MainActor func testSessionReaderAcceptsBuyerForBothThemePurchaseKindsWithoutChangingReadRequest() async throws {
        for purchaseKind in [1, 3] {
            let transport = LifecycleRecordingTransport("{\"code\":200,\"data\":{\"id\":41,\"memberId\":7,\"purchaseKind\":\(purchaseKind),\"cmsActivity\":{\"memberId\":99}}}")
            let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
            let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
            let detail = try await reader.detail(id: 41)
            XCTAssertEqual(detail.memberID, 7)
            XCTAssertEqual(detail.ownerMemberID, 99)
            // Missing server outcomes remain unknown, including after account binding.
            XCTAssertNil(detail.registrationStatus)
            XCTAssertNil(detail.paymentStatus)
            XCTAssertEqual(detail.summary().state, .unknown)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.path, "/test/api/registration/info")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n41\r\n"))
            XCTAssertFalse(body.contains("memberId"))
            XCTAssertFalse(body.contains("requestId"))
            XCTAssertFalse(body.contains("quoteSign"))
        }
    }
    @MainActor func testSessionReaderRejectsOtherOrMissingBuyerEvenWhenPublisherMatches() async throws {
        for body in [
            #"{"code":200,"data":{"id":41,"memberId":8,"cmsActivity":{"memberId":7}}}"#,
            #"{"code":200,"data":{"id":41,"memberId":8,"cmsTopic":{"memberId":7}}}"#,
            #"{"code":200,"data":{"id":41,"cmsActivity":{"memberId":7}}}"#,
            #"{"code":200,"data":{"id":41,"memberId":null,"cmsTopic":{"memberId":7}}}"#
        ] {
            let transport = LifecycleRecordingTransport(body)
            let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
            var expired = 0
            let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
            do { _ = try await reader.detail(id: 41); XCTFail("A different or absent buyer cannot become the current order") }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            XCTAssertEqual(expired, 0)
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1, "Malformed readback must not retry or create a replacement order")
        }
    }
    @MainActor func testSessionReaderRejectsAnotherOrderForTheSameBuyer() async throws {
        let transport = LifecycleRecordingTransport(#"{"code":200,"data":{"id":42,"memberId":7}}"#)
        let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
        do { _ = try await reader.detail(id: 41); XCTFail("A matching buyer is not a matching order") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    @MainActor func testExplicitRereadAndRecreatedReaderKeepTheSameOrderReadOnly() async throws {
        let transport = LifecycleRecordingTransport(#"{"code":200,"data":{"id":41,"memberId":7,"registrationStatus":2,"paymentStatus":1}}"#)
        let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
        let originalReader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
        let first = try await originalReader.detail(id: 41)
        let repeated = try await originalReader.detail(id: 41)
        // Reconstruction models a new reader lifetime, not a full app-restart test.
        let recreatedReader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
        let recreated = try await recreatedReader.detail(id: 41)
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first, recreated)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        for request in requests {
            XCTAssertEqual(request.url?.path, "/test/api/registration/info")
            let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n41\r\n"))
            XCTAssertFalse(body.contains("requestId"))
        }
    }
    @MainActor func testCurrent401ExpiresCapturedSessionWithoutRetry() async throws {
        let transport = LifecycleRecordingTransport(#"{"code":401,"data":"bad"}"#)
        let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
        var expired: [OrderLifecycleSession] = []
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { expired.append($0) })
        do { _ = try await reader.detail(id: 41); XCTFail("Unauthorized read must fail") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [session])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    @MainActor func testCurrent403DoesNotExpireSessionOrRetry() async throws {
        let transport = LifecycleRecordingTransport(#"{"code":403,"data":"bad"}"#)
        let session = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
        var expired = 0
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in expired += 1 })
        do { _ = try await reader.detail(id: 41); XCTFail("Denied read must fail") }
        catch { XCTAssertEqual(error as? OrderLifecycleFailure, .accessDenied) }
        XCTAssertEqual(expired, 0)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
    }
    @MainActor func testLateOrderForOldBuyerCannotReachReplacementAccount() async throws {
        let transport = LifecycleSuspendedTransport()
        var session: OrderLifecycleSession? = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-old")
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
        let task = Task { try await reader.detail(id: 41) }
        while !(await transport.isReady()) { await Task.yield() }
        session = try OrderLifecycleSession(accountID: 8, epoch: 2, token: "synthetic-new")
        await transport.finish(#"{"code":200,"data":{"id":41,"memberId":7}}"#)
        do { _ = try await task.value; XCTFail("Old account read cannot cross the session fence") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    @MainActor func testLateOrderCannotReachSignedOutReader() async throws {
        let transport = LifecycleSuspendedTransport()
        var session: OrderLifecycleSession? = try OrderLifecycleSession(accountID: 7, epoch: 1, token: "synthetic-session")
        let reader = OrderLifecycleSessionReader(service: try service(transport), currentSession: { session })
        let task = Task { try await reader.detail(id: 41) }
        while !(await transport.isReady()) { await Task.yield() }
        session = nil
        await transport.finish(#"{"code":200,"data":{"id":41,"memberId":7}}"#)
        do { _ = try await task.value; XCTFail("Signed-out reader cannot publish retained order data") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
