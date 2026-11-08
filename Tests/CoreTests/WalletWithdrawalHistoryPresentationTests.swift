import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WithdrawalHistoryTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (Int) async throws -> (Data, Int)
    init(_ handler: @escaping (Int) async throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await handler(requests.count) }
}
@MainActor final class WalletWithdrawalHistoryPresentationTests: XCTestCase {
    private func scope(account: Int = 7, namespace: String = "synthetic") -> WalletCommerceScope { .init(namespace: namespace, accountID: account, epoch: UUID()) }
    private func reader(_ fake: WithdrawalHistoryTransport, session: @escaping () -> (scope: WalletCommerceScope, token: String)?) throws -> WalletCommerceReader {
        .init(service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: fake), session: session)
    }
    private func row(_ id: Int = 1, status: Int = 1, extra: String = "") -> String { "{\"id\":\(id),\"amount\":5,\"status\":\(status)\(extra)}" }
    private func payload(_ ids: [Int] = [1], wrapper: String = "array", total: Int = 4) -> (Data, Int) {
        let rows = ids.map { row($0) }.joined(separator: ",")
        let data = wrapper == "array" ? "[\(rows)]" : "{\"\(wrapper)\":[\(rows)],\"total\":\(total)}"
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), 200)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }; throw URLError(.timedOut)
    }
    func testStatusFactsRemainSeparateFromBankReceiptAndMoneyCurrency() async throws {
        for (status, key) in [(0, "wallet.pendingReview"), (1, "wallet.approved"), (2, "wallet.rejected"), (3, "wallet.paid")] {
            let record = try JSONDecoder().decode(WalletWithdrawalRecord.self, from: Data(row(status: status).utf8))
            let entry = WalletWithdrawalHistoryEntry(record: record)
            XCTAssertEqual(entry.statusKey, key); XCTAssertEqual(entry.amount.value, 5); XCTAssertNil(entry.currency)
        }
    }
    func testMissingAndBlankTimeCurrencyAreUnknownAndOnlyMaskedAccountSurvives() async throws {
        let record = try JSONDecoder().decode(WalletWithdrawalRecord.self, from: Data(row(extra: ",\"currency\":\"  \",\"createTime\":\"\\n\",\"bankAccount\":\"SYNTHETIC-123456\"").utf8))
        let entry = WalletWithdrawalHistoryEntry(record: record)
        XCTAssertNil(entry.currency); XCTAssertNil(entry.recordedTime); XCTAssertEqual(entry.maskedAccount, "•••• 3456")
        XCTAssertFalse(entry.maskedAccount!.contains("SYNTHETIC"))
        let absent = WalletWithdrawalHistoryEntry(record: try JSONDecoder().decode(WalletWithdrawalRecord.self, from: Data(row().utf8)))
        XCTAssertNil(absent.maskedAccount)
    }
    func testAllOriginalWrappersRemainOneBodylessPOSTAndKeepSourceOrder() async throws {
        let active = scope()
        for wrapper in ["array", "rows", "list"] {
            let fake = WithdrawalHistoryTransport { _ in self.payload([3, 1, 2], wrapper: wrapper) }
            let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
            model.activate(reader: reader); await model.reload(reader: reader)
            let page = try XCTUnwrap(model.snapshot(for: .init(reader: reader)).page)
            XCTAssertEqual(page.rows.map(\.id), [3, 1, 2]); XCTAssertNil(page.page); XCTAssertNil(page.pageSize)
            let request = try XCTUnwrap(fake.requests.first)
            XCTAssertEqual(request.url?.path, "/api/withdrawal/list"); XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.httpBody); XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type")); XCTAssertNil(request.url?.query)
        }
    }
    func testEmptyBatchWithPositiveTotalIsLimitedRatherThanCompleteHistory() async throws {
        let active = scope(), fake = WithdrawalHistoryTransport { _ in self.payload([], wrapper: "rows", total: 8) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertNotNil(value.page); XCTAssertTrue(value.page!.rows.isEmpty); XCTAssertTrue(value.sourceLimited); XCTAssertNil(value.failure)
    }
    func testAmbiguousDuplicateIDsAndNegativeTotalsFailWithoutChoosingFinancialState() async throws {
        let active = scope()
        for result in [payload([1, 1]), payload([], wrapper: "list", total: -1)] {
            let fake = WithdrawalHistoryTransport { _ in result }
            let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
            model.activate(reader: reader); await model.reload(reader: reader)
            let value = model.snapshot(for: .init(reader: reader))
            XCTAssertNil(value.page); XCTAssertEqual(value.failure, .retryable)
        }
    }
    func testInvalidRecordAmountOrStateCannotBecomeSuccessfulEmptyHistory() async throws {
        let active = scope()
        for raw in [row(status: 4), row().replacingOccurrences(of: "\"amount\":5", with: "\"amount\":0"), row().replacingOccurrences(of: ",\"amount\":5", with: "")] {
            let fake = WithdrawalHistoryTransport { _ in (Data("{\"code\":200,\"data\":[\(raw)]}".utf8), 200) }
            let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
            model.activate(reader: reader); await model.reload(reader: reader)
            XCTAssertNil(model.snapshot(for: .init(reader: reader)).page)
            XCTAssertEqual(model.snapshot(for: .init(reader: reader)).failure, .retryable)
        }
    }
    func testScopeAccountNamespaceAndEpochMaskOldHistoryBeforeAnotherTask() async throws {
        var active = scope(); let fake = WithdrawalHistoryTransport { _ in self.payload() }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        for other in [scope(account: 8), scope(namespace: "another"), scope()] {
            active = other; let value = model.snapshot(for: .init(reader: reader))
            XCTAssertNil(value.page); XCTAssertNil(value.failure); XCTAssertFalse(value.isLoading)
            await model.reload(reader: reader); XCTAssertEqual(fake.requests.count, 1)
        }
    }
    func testRefreshClearsOldHistoryAndRejectsOlderLateSuccessWithoutClearingNewLoading() async throws {
        let active = scope(); var pending: [CheckedContinuation<(Data, Int), Error>] = []
        let fake = WithdrawalHistoryTransport { n in
            if n == 1 { return self.payload([1]) }; return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        let owner = WalletWithdrawalHistoryPresentation.Owner(reader: reader)
        model.activate(reader: reader); await model.reload(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending.count == 1 }
        XCTAssertNil(model.snapshot(for: owner).page)
        let fresh = Task { await model.reload(reader: reader) }; try await waitUntil { pending.count == 2 }
        pending[0].resume(returning: payload([2])); await old.value
        XCTAssertTrue(model.snapshot(for: owner).isLoading); XCTAssertNil(model.snapshot(for: owner).page)
        pending[1].resume(returning: payload([3])); await fresh.value
        XCTAssertEqual(model.snapshot(for: owner).page?.rows.map(\.id), [3])
    }
    func testReplacementReaderSameScopeRejectsOldFailureAndQueuedRetry() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let oldFake = WithdrawalHistoryTransport { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let oldReader = try reader(oldFake) { (active, "synthetic") }
        let freshFake = WithdrawalHistoryTransport { _ in self.payload([2]) }
        let fresh = try reader(freshFake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        model.activate(reader: oldReader)
        let old = Task { await model.reload(reader: oldReader) }; try await waitUntil { pending != nil }
        model.activate(reader: fresh); await model.reload(reader: fresh); await model.reload(reader: oldReader)
        pending!.resume(throwing: URLError(.timedOut)); await old.value
        XCTAssertEqual(model.snapshot(for: .init(reader: fresh)).page?.rows.map(\.id), [2])
        XCTAssertNil(model.snapshot(for: .init(reader: fresh)).failure); XCTAssertEqual(oldFake.requests.count, 1)
    }
    func testDeactivationCancellationAndReentryCannotReviveOldHistory() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = WithdrawalHistoryTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }; return self.payload([2])
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        await model.reload(reader: reader); XCTAssertTrue(fake.requests.isEmpty)
        model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        model.deactivate(); await model.reload(reader: reader); XCTAssertEqual(fake.requests.count, 1)
        model.activate(reader: reader); await model.reload(reader: reader)
        old.cancel(); pending!.resume(returning: payload([1])); await old.value
        XCTAssertEqual(model.snapshot(for: .init(reader: reader)).page?.rows.map(\.id), [2])
    }
    func testFailedRefreshClearsOldRowsAndExplicitRetryRecovers() async throws {
        let active = scope(), fake = WithdrawalHistoryTransport { n in
            if n == 2 { throw URLError(.timedOut) }; return self.payload([n])
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        let owner = WalletWithdrawalHistoryPresentation.Owner(reader: reader)
        model.activate(reader: reader); await model.reload(reader: reader); await model.reload(reader: reader)
        XCTAssertNil(model.snapshot(for: owner).page); XCTAssertEqual(model.snapshot(for: owner).failure, .retryable)
        await model.reload(reader: reader); XCTAssertEqual(model.snapshot(for: owner).page?.rows.map(\.id), [3])
    }
    func testLoginAndUnconfiguredAreDistinctFromRetryableFailure() async throws {
        let active = scope(), fake = WithdrawalHistoryTransport { _ in (Data("{\"code\":401}".utf8), 401) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletWithdrawalHistoryPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        XCTAssertEqual(model.snapshot(for: .init(reader: reader)).failure, .login)
        let unavailable = WalletCommerceReader(session: { (active, "synthetic") })
        model.activate(reader: unavailable); await model.reload(reader: unavailable)
        XCTAssertEqual(model.snapshot(for: .init(reader: unavailable)).failure, .unavailable)
    }
}
