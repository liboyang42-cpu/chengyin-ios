import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor enum InvoiceLaunchTestSupport {
    static func session(account: Int64 = 7, epoch: UInt64 = 1, namespace: String = "synthetic-cn",
                        role: String = "player", token: String = "synthetic-invoice-token") throws -> InvoiceLaunchSession {
        try .init(baseURL: URL(string: "https://example.com/native")!, namespace: namespace,
                  accountID: account, role: role, epoch: epoch, token: token)
    }
    static func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    static func success(_ object: Any) throws -> (Data, Int) { (try data(["code": 200, "data": object]), 200) }
    static func failure(_ code: String) throws -> (Data, Int) { (try data(["code": 500, "errorCode": code]), 200) }
    static var title: [String: Any] {
        ["id": 11, "titleType": "PERSONAL", "titleName": "Synthetic title", "isDefault": false, "taxNoMasked": NSNull()]
    }
    static func application(id: Int64 = 51, status: String = "SUBMITTED", orders: [Int64] = [21, 22]) -> [String: Any] {
        ["id": id, "applicationNo": "SYNTHETIC-51", "status": status, "titleType": "PERSONAL",
         "titleName": "Synthetic title", "taxNoMasked": NSNull(), "totalAmount": 14.25,
         "orderCount": orders.count, "provider": "MANUAL", "invoiceNo": NSNull(), "rejectReason": NSNull(),
         "issuedAt": NSNull(), "createTime": "2026-11-04 00:00:00", "replayed": false,
         "orders": orders.map { ["orderId": $0, "orderSource": "registration", "amount": 7.125,
                                  "orderTitle": "Synthetic order", "ticketName": NSNull(), "paymentTime": 1_794_000_000_000] }]
    }
    @MainActor final class Memory: InvoiceLaunchStorage {
        var values: [String: Data] = [:]
        var failWrite = false, ignoreWrite = false, failRemove = false
        var writeCount = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws {
            writeCount += 1
            if failWrite { throw InvoiceLaunchIssue.storageUnavailable }
            if !ignoreWrite { values[key] = data }
        }
        func remove(_ key: String) throws {
            if failRemove { throw InvoiceLaunchIssue.storageUnavailable }
            values.removeValue(forKey: key)
        }
    }
    @MainActor final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var responses: [(Data, Int)] = []
        var beforeSend: (() throws -> Void)?
        var afterSend: (() -> Void)?
        var failNext = false
        var suspended: CheckedContinuation<(Data, Int), Never>?
        var suspendNext = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); try beforeSend?()
            if failNext { failNext = false; throw URLError(.timedOut) }
            if suspendNext { suspendNext = false; return await withCheckedContinuation { suspended = $0 } }
            guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
            let response = responses.removeFirst(); afterSend?(); return response
        }
    }
    @MainActor final class Harness {
        let captured: InvoiceLaunchSession
        var current: InvoiceLaunchSession?
        var enabled = true, mutations = true, unauthorized = 0
        let memory: Memory, wire = Wire()
        lazy var service = InvoiceLaunchService(session: captured, transport: wire,
            enabled: { [unowned self] in enabled }, mutationsEnabled: { [unowned self] in mutations },
            current: { [unowned self] in current }, unauthorized: { [unowned self] in unauthorized += 1 })
        lazy var store = InvoiceLaunchPendingStore(session: captured, storage: memory)
        init(memory: Memory? = nil, captured: InvoiceLaunchSession? = nil) throws {
            self.captured = try captured ?? session(); current = self.captured; self.memory = memory ?? Memory()
        }
        func coordinator() throws -> InvoiceLaunchCoordinator { try .init(service: service, store: store) }
        func command() throws -> InvoiceLaunchApply { try .init(requestId: "synthetic-original-request", titleId: 11, orderIds: [21, 22]) }
    }
    static func expect(_ expected: InvoiceLaunchIssue, _ operation: () async throws -> Void,
                       file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? InvoiceLaunchIssue, expected, file: file, line: line) }
    }
}

@MainActor final class InvoiceLaunchServiceTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    func testFrozenRouteInventoryAndDefaultClosed() async throws {
        XCTAssertEqual(InvoiceLaunchRoute.allCases.count, 8)
        XCTAssertFalse(InvoiceLaunchRoute.allCases.contains { $0.path.hasSuffix("/request") })
        let wire = S.Wire(), session = try S.session()
        let service = InvoiceLaunchService(session: session, transport: wire, current: { session })
        await S.expect(.disabled) { _ = try await service.titles() }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testTitleRequestUsesFrozenJSONRawAuthorizationAndMaskOnly() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success([S.title])]
        let titles = try await h.service.titles(); XCTAssertEqual(titles.first?.id, 11)
        let request = try XCTUnwrap(h.wire.requests.first)
        XCTAssertEqual(request.url?.path, "/native/api/invoice/titles")
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.httpBody, Data("{}".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-invoice-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        var unsafe = S.title; unsafe["taxNoMasked"] = "913456789012345678"
        h.wire.responses = [try S.success([unsafe])]
        await S.expect(.malformed) { _ = try await h.service.titles() }
    }
    func testServerAmountsRemainExactAndSummaryMayHaveNoLines() async throws {
        let h = try S.Harness(); var summary = S.application(); summary["orders"] = []
        h.wire.responses = [try S.success(S.application()), try S.success([summary])]
        let app = try await h.service.detail(id: 51)
        XCTAssertEqual(app.totalAmount, Decimal(string: "14.25"))
        XCTAssertEqual(app.orders[0].amount, Decimal(string: "7.125"))
        XCTAssertEqual(app.orders[0].paymentTime, .epochMilliseconds(1_794_000_000_000))
        let rows = try await h.service.applications(); XCTAssertTrue(rows[0].orders.isEmpty)
    }
    func testMismatchedIDsAndFutureStatusFailClosed() async throws {
        let h = try S.Harness(); h.wire.responses = [try S.success(S.application(id: 52)), try S.success(S.application(status: "PROCESSING"))]
        await S.expect(.malformed) { _ = try await h.service.detail(id: 51) }
        do { _ = try await h.service.detail(id: 51); XCTFail("Future contract must not be silently enabled") } catch {}
    }
    func testSessionChangesBeforeAndDuringReadFenceResults() async throws {
        let h = try S.Harness(); h.current = try S.session(account: 8)
        await S.expect(.staleSession) { _ = try await h.service.titles() }; XCTAssertTrue(h.wire.requests.isEmpty)
        h.current = h.captured
        await S.expect(.staleSession) { _ = try await h.service.titles() }
        let other = try S.Harness(); other.wire.responses = [try S.success([S.title])]
        other.wire.afterSend = { other.current = nil }
        await S.expect(.staleSession) { _ = try await other.service.titles() }
    }
    func testAuthenticationFailureIsReportedOnlyToMatchingSession() async throws {
        let h = try S.Harness(); h.wire.responses = [(Data("{}".utf8), 401)]
        await S.expect(.unauthorized) { _ = try await h.service.titles() }; XCTAssertEqual(h.unauthorized, 1)
        h.wire.responses = [(Data("{}".utf8), 401)]; h.wire.afterSend = { h.current = nil }
        await S.expect(.staleSession) { _ = try await h.service.titles() }; XCTAssertEqual(h.unauthorized, 1)
    }
    func testEverySessionDimensionInvalidatesRetainedService() async throws {
        for replacement in [try S.session(epoch: 2), try S.session(role: "merchant"),
                            try S.session(token: "synthetic-rotated-token"), try S.session(namespace: "synthetic-us")] {
            let h = try S.Harness(); h.current = replacement
            await S.expect(.staleSession) { _ = try await h.service.eligibleOrders() }
            XCTAssertTrue(h.wire.requests.isEmpty)
        }
    }
    func testIssuedInvoiceNumberNeverFabricatesDownloadableDocument() async throws {
        let h = try S.Harness(); var issued = S.application(status: "ISSUED"); issued["invoiceNo"] = "SYNTHETIC-INVOICE-51"
        h.wire.responses = [try S.success(issued)]
        let application = try await h.service.detail(id: 51)
        XCTAssertEqual(application.invoiceNo, "SYNTHETIC-INVOICE-51")
        XCTAssertEqual(application.documentStatus, .unknown)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
}
