import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class MerchantFeaturedActivityOptionsTests: XCTestCase {
    private func page(_ raw: String) throws -> MerchantFeaturedActivityPage { try JSONDecoder().decode(MerchantFeaturedActivityPage.self, from: Data(raw.utf8)) }
    func testArrayResponseKeepsUnknownTotalWithoutClaimingExhaustion() throws {
        let value = try page(#"[{"id":7,"name":"Candidate"}]"#)
        XCTAssertEqual(value.rows.first?.id, 7); XCTAssertNil(value.total)
    }
    func testWrappedPageUsesTitleFallbackAndCount() throws {
        let value = try page(#"{"rows":[{"id":7,"name":"","title":"Fallback"}],"total":3}"#)
        XCTAssertEqual(value.rows.first?.name, "Fallback"); XCTAssertEqual(value.total, 3)
    }
    func testInvalidDuplicateAndUnsafeIdentitiesAreRejected() {
        for raw in [#"[{"id":0}]"#, #"[{"id":true}]"#, #"[{"id":9007199254740992}]"#, #"[{"id":1},{"id":1}]"#] {
            XCTAssertThrowsError(try page(raw))
        }
    }
    func testCountsCannotPretendThatLoadedRowsAreMissingOrComplete() throws {
        XCTAssertThrowsError(try page(#"{"rows":[{"id":1}],"total":0}"#))
        XCTAssertThrowsError(try page(#"{"rows":[],"total":-1}"#))
        let incomplete = try page(#"{"rows":[],"total":2}"#)
        XCTAssertThrowsError(try incomplete.appended(to: []))
        XCTAssertTrue(try page(#"{"rows":[],"total":0}"#).appended(to: []).isEmpty)
    }
    func testNextPageRejectsDuplicateIdentityAndRetainsExistingValues() throws {
        let first = try page(#"{"rows":[{"id":7,"name":"First"}],"total":2}"#)
        let second = try page(#"{"rows":[{"id":8,"name":"Second"}],"total":2}"#)
        XCTAssertEqual(try second.appended(to: first.rows).map(\.id), [7, 8])
        XCTAssertThrowsError(try first.appended(to: first.rows)); XCTAssertEqual(first.rows.map(\.id), [7])
    }
    func testResponseDoesNotExceedRequestedPageSize() {
        let rows = (1...21).map { "{\"id\":\($0)}" }.joined(separator: ",")
        XCTAssertThrowsError(try page("[" + rows + "]"))
    }
}

private final class FeaturedActivityScriptTransport: HTTPTransport {
    var access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":["merchant:profile:write"]}}"#
    var requests: [URLRequest] = []
    var delay = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var onPending: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.path == "/api/merchant/access/me" { return (Data(access.utf8), 200) }
        if delay { return try await withCheckedThrowingContinuation { pending = $0; onPending?() } }
        return (Data(#"{"code":200,"data":{"rows":[{"id":7,"name":"Candidate"}],"total":1}}"#.utf8), 200)
    }
}

@MainActor final class MerchantFeaturedActivityReaderTests: XCTestCase {
    private func session(_ revision: UInt64 = 0) throws -> MerchantOperationsSession {
        try .init(accountID: 1, epoch: 1, token: "synthetic-token", storageNamespace: "test", viewerRevision: revision)
    }
    private func service(_ transport: FeaturedActivityScriptTransport) throws -> MerchantOperationsService {
        .init(configuration: try APIConfiguration(baseURL: URL(string: "https://featured.example")!), transport: transport)
    }
    func testEveryPageRechecksAccessAndUsesOnlyCurrentAccountOwnedQuery() async throws {
        let transport = FeaturedActivityScriptTransport(), identity = try session()
        let reader = MerchantOperationsSessionReader(service: try service(transport), currentSession: { identity })
        _ = try await reader.featuredActivities(page: 2)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/merchant/access/me", "/api/activity/list"])
        let request = try XCTUnwrap(transport.requests.last), body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        for field in ["name=\"is_my\"\r\n\r\n1", "name=\"pageNum\"\r\n\r\n2", "name=\"pageSize\"\r\n\r\n20"] { XCTAssertTrue(body.contains(field)) }
        XCTAssertFalse(body.contains("merchantId")); XCTAssertFalse(body.contains("memberId"))
    }
    func testDeniedProfilePermissionPreventsOwnedActivityRead() async throws {
        let transport = FeaturedActivityScriptTransport(), identity = try session()
        transport.access = #"{"code":200,"data":{"active":true,"merchant":{"id":31},"roleCode":"MERCHANT_OWNER","permissions":[]}}"#
        let reader = MerchantOperationsSessionReader(service: try service(transport), currentSession: { identity })
        do { _ = try await reader.featuredActivities(page: 1); XCTFail() } catch { XCTAssertEqual(error as? MerchantOperationsFailure, .accessDenied) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testRoleReplacementBeforeLate401CannotExpireReplacementSession() async throws {
        let transport = FeaturedActivityScriptTransport(); transport.delay = true
        var current: MerchantOperationsSession? = try session(), expirations = 0
        let started = expectation(description: "owned list started"); transport.onPending = { started.fulfill() }
        let reader = MerchantOperationsSessionReader(service: try service(transport), currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        let task = Task { try await reader.featuredActivities(page: 1) }
        await fulfillment(of: [started], timeout: 2)
        current = try session(1); transport.pending?.resume(returning: (Data(), 401)); transport.pending = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
    func testCancelledReadBeforeLate401CannotExpireCurrentSession() async throws {
        let transport = FeaturedActivityScriptTransport(); transport.delay = true
        let identity = try session(); var expirations = 0
        let started = expectation(description: "owned list started"); transport.onPending = { started.fulfill() }
        let reader = MerchantOperationsSessionReader(service: try service(transport), currentSession: { identity }, onUnauthorized: { _ in expirations += 1 })
        let task = Task { try await reader.featuredActivities(page: 1) }
        await fulfillment(of: [started], timeout: 2); task.cancel()
        transport.pending?.resume(returning: (Data(), 401)); transport.pending = nil
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
}
