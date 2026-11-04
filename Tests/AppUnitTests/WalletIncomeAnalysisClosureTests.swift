import XCTest
@testable import Questify

@MainActor final class WalletIncomeAnalysisClosureTests: XCTestCase {
    func testRealOriginalIncomeRouteReadsBoundedPagesToEnd() async throws {
        let h = try Harness(total: 21); await h.model.load(h.reader)
        XCTAssertEqual(h.model.result?.stop, .end)
        XCTAssertEqual(h.model.result?.rows.count, 21)
        XCTAssertEqual(h.model.pagesRead, 2)
        XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertEqual(h.model.displayedResult(for: h.reader)?.rows.count, 21)
    }
    func testMissingTotalIsUnverifiedEvenWhenNoRecordsWereReturned() async throws {
        let h = try Harness(total: 0); h.wire.omitTotal = true
        await h.model.load(h.reader)
        XCTAssertEqual(h.model.result?.stop, .unverified)
        XCTAssertEqual(h.model.result?.isPartial, true)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testTenPageBudgetNeverRequestsAnEleventhPage() async throws {
        let h = try Harness(total: 250); await h.model.load(h.reader)
        XCTAssertEqual(h.model.result?.stop, .budget)
        XCTAssertEqual(h.model.result?.rows.count, 200)
        XCTAssertEqual(h.wire.requests.count, 10)
    }
    func testChangedTotalOrDuplicateBoundaryKeepsOnlyEarlierValidatedSlice() async throws {
        for duplicate in [false, true] {
            let h = try Harness(total: 21)
            h.wire.changedTotal = !duplicate; h.wire.duplicateBoundary = duplicate
            await h.model.load(h.reader)
            XCTAssertEqual(h.model.result?.stop, .changed)
            XCTAssertEqual(h.model.result?.rows.count, 20)
            XCTAssertEqual(h.wire.requests.count, 2)
        }
    }
    func testTransientLaterFailureIsAnExplicitPartialRead() async throws {
        let h = try Harness(total: 21); h.wire.secondStatus = 503
        await h.model.load(h.reader)
        XCTAssertEqual(h.model.result?.stop, .interrupted)
        XCTAssertEqual(h.model.result?.rows.count, 20)
        XCTAssertFalse(h.model.unavailable)
    }
    func testHTTPAndBusiness403ClearPriorPagesRatherThanDisplayPartialMoney() async throws {
        for business in [false, true] {
            let h = try Harness(total: 21)
            h.wire.secondStatus = business ? 200 : 403
            h.wire.secondCode = business ? 403 : nil
            await h.model.load(h.reader)
            XCTAssertTrue(h.model.unavailable)
            XCTAssertNil(h.model.result)
            XCTAssertNil(h.model.displayedResult(for: h.reader))
            XCTAssertEqual(h.model.receivedCount, 0)
            XCTAssertEqual(h.model.pagesRead, 0)
        }
    }
    func testCurrent401ClearsResultsAndNotifiesOriginalReaderOnce() async throws {
        let h = try Harness(total: 21); h.wire.secondStatus = 401
        await h.model.load(h.reader)
        XCTAssertTrue(h.model.requiresLogin)
        XCTAssertNil(h.model.result)
        XCTAssertEqual(h.owner.unauthorized, 1)
    }
    func testCancellationSuppressesLate401AndClearsAllPublishedRows() async throws {
        let h = try Harness(total: 21); h.wire.suspendSecond = true
        let work = Task { await h.model.load(h.reader) }
        await h.wire.waitForSecond()
        h.model.cancel(); h.wire.resumeSecond(status: 401)
        await work.value
        XCTAssertNil(h.model.result)
        XCTAssertEqual(h.model.receivedCount, 0)
        XCTAssertFalse(h.model.loading)
        XCTAssertFalse(h.model.requiresLogin)
        XCTAssertEqual(h.owner.unauthorized, 0)
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testAccountChangeRejectsLatePageAndCannotExpireNewSession() async throws {
        let h = try Harness(total: 21); h.wire.suspendSecond = true
        let work = Task { await h.model.load(h.reader) }
        await h.wire.waitForSecond()
        h.owner.scope = WalletCommerceScope(namespace: "analysis-test", accountID: 8, epoch: UUID())
        h.wire.resumeSecond(status: 401); await work.value
        XCTAssertNil(h.model.result)
        XCTAssertEqual(h.model.receivedCount, 0)
        XCTAssertEqual(h.owner.unauthorized, 0)
    }
    func testSameOwnerReplacementReaderDoesNotAdoptOldDisplay() async throws {
        let h = try Harness(total: 1); await h.model.load(h.reader)
        let replacement = h.makeReader()
        XCTAssertEqual(replacement.scope, h.reader.scope)
        XCTAssertNil(h.model.displayedResult(for: replacement))
        XCTAssertNotNil(h.model.displayedResult(for: h.reader))
    }
    func testCurrencyAndUnknownFieldsStaySeparateAndSourceDecimalsStayExact() throws {
        let rows = try [row(1, amount: "1234.5678", currency: "USD"), row(2, amount: "999", currency: "CNY"),
                        row(3, amount: nil, currency: "USD"), row(4, amount: "12", currency: nil)]
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z"))
        let summary = WalletIncomeAnalysisPresentation(rows: rows, mode: .income, currency: "USD", now: now)
        XCTAssertEqual(summary.months.last?.amount, Decimal(string: "1234.5678"))
        XCTAssertEqual(summary.unknownCount, 2)
        XCTAssertEqual(WalletIncomeAnalysisPresentation.currencies(rows), ["CNY", "USD"])
        for language in ["en", "zh-Hans"] {
            XCTAssertEqual(WalletIncomeAnalysisPresentation.text(try XCTUnwrap(summary.months.last?.amount), currency: "USD", locale: Locale(identifier: language)), "1,234.5678 USD")
        }
    }
    func testWithdrawalsCountOnlyOriginalWithdrawalRequestDebitsNotOtherExpenses() throws {
        let rows = try [row(1, amount: "12", currency: "USD", direction: 2, event: 3),
                        row(2, amount: "99", currency: "USD", direction: 2, event: 2)]
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T12:00:00Z"))
        let summary = WalletIncomeAnalysisPresentation(rows: rows, mode: .withdrawal, currency: "USD", now: now)
        XCTAssertEqual(summary.months.last?.amount, 12)
        XCTAssertEqual(summary.months.last?.count, 1)
        XCTAssertTrue(summary.sources.isEmpty)
    }
    private func row(_ id: Int, amount: String?, currency: String?, direction: Int = 1, event: Int = 1) throws -> WalletLedgerRow {
        var row: [String: Any] = ["id": id, "changeType": direction, "eventType": event, "createTime": "2026-11-01 00:00:00"]
        row["changeBalance"] = amount; row["currency"] = currency
        return try JSONDecoder().decode(WalletLedgerRow.self, from: JSONSerialization.data(withJSONObject: row))
    }
    @MainActor private final class Owner {
        var scope = WalletCommerceScope(namespace: "analysis-test", accountID: 7, epoch: UUID())
        var unauthorized = 0
    }
    @MainActor private final class Harness {
        let owner = Owner(), model = WalletIncomeAnalysisReader(), wire: Wire, service: WalletCommerceService
        lazy var reader = makeReader()
        init(total: Int) throws {
            wire = Wire(total: total)
            service = WalletCommerceService(configuration: try APIConfiguration(baseURL: Wire.base), transport: wire)
        }
        func makeReader() -> WalletCommerceReader {
            WalletCommerceReader(service: service, onUnauthorized: { [owner] _ in owner.unauthorized += 1 },
                session: { [owner] in (owner.scope, "synthetic-only") })
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        static let base = URL(string: "https://example.test/")!
        let total: Int
        var requests: [URLRequest] = []
        var omitTotal = false, changedTotal = false, duplicateBoundary = false, suspendSecond = false
        var secondStatus: Int?, secondCode: Int?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var waiting: CheckedContinuation<Void, Never>?
        init(total: Int) { self.total = total }
        func waitForSecond() async {
            if pending != nil { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func resumeSecond(status: Int) {
            let work = pending; pending = nil
            work?.resume(returning: (Data("{\"code\":\(status)}".utf8), status))
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            XCTAssertEqual(request.url?.path, "/api/user/balance/list")
            XCTAssertNotNil(WalletHistoryReadRoute(request: request, baseURL: Self.base, accountID: 7))
            requests.append(request); let number = requests.count
            XCTAssertTrue(String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("\r\n\(number)\r\n") == true)
            if number == 2, suspendSecond {
                return try await withCheckedThrowingContinuation { pending = $0; waiting?.resume(); waiting = nil }
            }
            if number == 2, let status = secondStatus {
                return (try JSONSerialization.data(withJSONObject: ["code": secondCode ?? status]), status)
            }
            let offset = (number - 1) * 20
            let count = max(0, min(20, total - offset))
            let rows: [[String: Any]] = (0..<count).map { i in
                ["id": duplicateBoundary && number == 2 ? 981 : 1000 - offset - i,
                 "changeBalance": "1.2345", "currency": "USD", "changeType": 1, "eventType": 1,
                 "createTime": "2026-11-01 00:00:00"]
            }
            var data: [String: Any] = ["rows": rows]
            if !omitTotal { data["total"] = changedTotal && number == 2 ? total + 1 : total }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
}
