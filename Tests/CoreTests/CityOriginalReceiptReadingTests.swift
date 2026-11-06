import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityOriginalReceiptReadingTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200
        var body = #"{"code":200,"data":{"requestId":"original-1","requestStatus":"COMPLETE"}}"#
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?(); return (Data(body.utf8), status)
        }
    }
    @MainActor private final class Harness {
        let api: APIConfiguration
        let wire = Wire()
        let original: CityOriginalReceiptSession
        var current: CityOriginalReceiptSession?
        var issued: CityOriginalReceiptReadGrant?
        init() throws {
            api = try .init(baseURL: URL(string: "https://city.example.test/native/")!)
            original = try .init(market: .china, baseURL: api.baseURL, namespace: "city-http-test", accountID: 7, epoch: 1, token: "synthetic-city-token")
            current = original
        }
        func reference(_ domain: CityOriginalReceiptDomain = .participation, id: String = "original-1") throws -> CityOriginalReceiptReference {
            try .init(session: original, domain: domain, requestID: id)
        }
        func reader() -> CityOriginalReceiptReader {
            .init(configuration: api, transport: wire, currentSession: { self.current }, grant: { self.issued })
        }
        func approve(_ reference: CityOriginalReceiptReference) { issued = .init(reference: reference) }
    }
    private func rejects(_ expected: CityOriginalReceiptReadFailure, _ operation: () async throws -> CityOriginalReceiptObservation) async {
        do { _ = try await operation(); XCTFail("Expected closed read") }
        catch { XCTAssertEqual(error as? CityOriginalReceiptReadFailure, expected) }
    }
    func testDefaultNilGrantAndWrongDomainOrRequestNeverDispatch() async throws {
        let h = try Harness(), ref = try h.reference(), reader = h.reader()
        await rejects(.disabled) { try await reader.read(ref) }
        let defaultReader = CityOriginalReceiptReader(configuration: h.api, transport: h.wire, currentSession: { h.current })
        await rejects(.disabled) { try await defaultReader.read(ref) }
        h.approve(try h.reference(.acquisition))
        await rejects(.disabled) { try await reader.read(ref) }
        h.approve(try h.reference(id: "other"))
        await rejects(.disabled) { try await reader.read(ref) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAllThreeDomainsUseOnlyExactOriginalGETAndDoNotCoerceBusinessPayload() async throws {
        let h = try Harness(), reader = h.reader()
        for domain in CityOriginalReceiptDomain.allCases {
            let ref = try h.reference(domain); h.approve(ref)
            let observation = try await reader.read(ref)
            XCTAssertEqual(observation.domain, domain); XCTAssertEqual(observation.requestID, ref.requestID)
            XCTAssertEqual(observation.state, .complete(httpStatus: 200, businessCode: 200))
            let request = try XCTUnwrap(h.wire.requests.last)
            XCTAssertEqual(request.url?.path, "/native/api/city-game/\(domain.rawValue)/request/original-1")
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-city-token")
        }
        XCTAssertEqual(h.wire.requests.count, 3)
    }
    func test202UnknownRemainsOriginalUnknownAndDoesNotRetry() async throws {
        let h = try Harness(), ref = try h.reference(.actionBudget); h.approve(ref)
        h.wire.status = 202
        h.wire.body = #"{"code":202,"errorCode":"OUTCOME_UNKNOWN","data":{"requestId":"original-1","requestStatus":"UNKNOWN"}}"#
        let observation = try await h.reader().read(ref)
        XCTAssertEqual(observation.state, .unknown); XCTAssertEqual(observation.requestID, "original-1")
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testMissingAndPrivateReceiptsNeverBecomeCompletionEvenWithCompleteBody() async throws {
        let h = try Harness(), ref = try h.reference(); h.approve(ref)
        for status in [401, 403, 404] {
            h.wire.status = status
            await rejects(.unavailable(status: status)) { try await h.reader().read(ref) }
            h.wire.status = 200
            h.wire.body = "{\"code\":\(status),\"data\":{\"requestId\":\"original-1\",\"requestStatus\":\"COMPLETE\"}}"
            await rejects(.unavailable(status: status)) { try await h.reader().read(ref) }
        }
        XCTAssertEqual(h.wire.requests.count, 6)
    }
    func testMismatchedMissingAndFutureReceiptStatusesStayUnverified() async throws {
        let h = try Harness(), ref = try h.reference(); h.approve(ref)
        for body in [#"{"code":200,"data":{"requestId":"other","requestStatus":"COMPLETE"}}"#,
                     #"{"code":200,"data":{"requestStatus":"COMPLETE"}}"#,
                     #"{"code":200,"data":{"requestId":"original-1","requestStatus":"FUTURE"}}"#,
                     #"{"code":200,"data":{"requestId":"original-1","requestStatus":"UNKNOWN"}}"#] {
            h.wire.body = body
            await rejects(.unverified) { try await h.reader().read(ref) }
        }
        XCTAssertEqual(h.wire.requests.count, 4)
    }
    func testTerminalRejectionIsObservedAsRejectionCodeNotPayerSuccess() async throws {
        let h = try Harness(), ref = try h.reference(.acquisition); h.approve(ref)
        h.wire.status = 409
        h.wire.body = #"{"code":409,"errorCode":"SOURCE_CHANGED","data":{"requestId":"original-1","requestStatus":"COMPLETE"}}"#
        let observation = try await h.reader().read(ref)
        XCTAssertEqual(observation.state, .complete(httpStatus: 409, businessCode: 409))
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testLateAccountEpochOrCredentialChangeDropsOriginalReply() async throws {
        for change in ["account", "epoch", "token", "namespace"] {
            let h = try Harness(), ref = try h.reference(); h.approve(ref)
            let replacement = try CityOriginalReceiptSession(market: .china, baseURL: h.api.baseURL,
                namespace: change == "namespace" ? "other" : "city-http-test", accountID: change == "account" ? 8 : 7,
                epoch: change == "epoch" ? 2 : 1, token: change == "token" ? "replacement-token" : "synthetic-city-token")
            h.wire.beforeReply = { h.current = replacement }
            await rejects(.staleSession) { try await h.reader().read(ref) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testRevokedOrReissuedGrantCannotAcceptOldInFlightReply() async throws {
        for replace in [false, true] {
            let h = try Harness(), ref = try h.reference(); h.approve(ref)
            h.wire.beforeReply = { if replace { h.approve(ref) } else { h.issued?.revoke() } }
            await rejects(.disabled) { try await h.reader().read(ref) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testReferenceRejectsPathInjectionAndInvalidSourceIdentifiers() throws {
        let h = try Harness()
        for id in ["", "../command", "id?x=1", "id/command", "非ASCII", "-leading", String(repeating: "a", count: 97)] {
            XCTAssertThrowsError(try h.reference(id: id))
        }
        XCTAssertNoThrow(try h.reference(id: "A_0-1")); XCTAssertTrue(h.wire.requests.isEmpty)
    }
}
