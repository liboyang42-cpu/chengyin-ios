import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PointsLedgerTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (Int) async throws -> (Data, Int)
    init(_ handler: @escaping (Int) async throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await handler(requests.count)
    }
}
@MainActor final class WalletPointsLedgerPresentationTests: XCTestCase {
    private func row(_ fields: String = "") throws -> WalletLedgerRow {
        try JSONDecoder().decode(WalletLedgerRow.self, from: Data(("{\"id\":1" + fields + "}").utf8))
    }
    private func scope(account: Int = 7) -> WalletCommerceScope { .init(namespace: "synthetic", accountID: account, epoch: UUID()) }
    private func reader(_ transport: PointsLedgerTransport, session: @escaping () -> (scope: WalletCommerceScope, token: String)?) throws -> WalletCommerceReader {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test")!)
        return WalletCommerceReader(service: WalletCommerceService(configuration: config, transport: transport), session: session)
    }
    private func payload(_ ids: [Int], paged: Bool = false, total: Int = 2) -> (Data, Int) {
        let rows = ids.map { "{\"id\":\($0),\"changePoints\":1}" }.joined(separator: ",")
        return (Data((paged ? "{\"code\":200,\"data\":{\"rows\":[\(rows)],\"total\":\(total)}}" : "{\"code\":200,\"data\":[\(rows)]}").utf8), 200)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        throw URLError(.timedOut)
    }
    func testPointsDirectionNeverFallsBackToMoneyOrXP() async throws {
        let entry = WalletPointsLedgerEntry(row: try row(",\"changeBalance\":-9,\"afterBalance\":10,\"xp\":99"))
        XCTAssertEqual(entry.direction, .unknown); XCTAssertNil(entry.signedChange); XCTAssertNil(entry.afterPoints)
    }
    func testAbsentTypeUsesOnlyNonzeroPointsSign() async throws {
        for (text, direction, signed) in [("-1.25", WalletDirection.expense, "−1.25"), ("2.5", .income, "+2.5"), ("0", .unknown, "0")] {
            let entry = WalletPointsLedgerEntry(row: try row(",\"changePoints\":\"\(text)\""))
            XCTAssertEqual(entry.direction, direction); XCTAssertEqual(entry.signedChange, signed)
        }
    }
    func testTypeRemainsAuthoritativeAndUnknownTypeIsNotGuessed() async throws {
        for (type, direction, signed) in [(1, WalletDirection.income, "+2"), (2, .expense, "−2"), (9, .unknown, "-2")] {
            let entry = WalletPointsLedgerEntry(row: try row(",\"changePoints\":-2,\"changeType\":\(type)"))
            XCTAssertEqual(entry.direction, direction); XCTAssertEqual(entry.signedChange, signed)
        }
        let missing = WalletPointsLedgerEntry(row: try row(",\"changeType\":2"))
        XCTAssertEqual(missing.direction, .expense); XCTAssertNil(missing.signedChange)
    }
    func testAfterPointsIsPerEntryAndMissingTextRemainsUnknown() async throws {
        let missing = WalletPointsLedgerEntry(row: try row(",\"changeReason\":\"  \",\"createTime\":\"\\n\""))
        XCTAssertNil(missing.afterPoints); XCTAssertNil(missing.reason); XCTAssertNil(missing.recordedTime)
        let fact = WalletPointsLedgerEntry(row: try row(",\"afterPoints\":0,\"changeReason\":\"source reason\",\"createTime\":\"2026-11-08 09:12:00\""))
        XCTAssertEqual(fact.afterPoints?.value, 0); XCTAssertEqual(fact.reason, "source reason")
        XCTAssertEqual(fact.recordedTime, "2026-11-08 09:12:00")
    }
    func testOriginalAssetEndpointRetainsSourceOrderAndHasNoPagination() async throws {
        let active = scope(), fake = PointsLedgerTransport { _ in self.payload([3, 1, 2]) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let owner = WalletPointsLedgerPresentation.Owner(reader: reader, kind: .assetPoints)
        await model.load(reader: reader, kind: .assetPoints)
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [3, 1, 2])
        XCTAssertFalse(model.snapshot(for: owner).hasMore)
        await model.load(reader: reader, kind: .assetPoints)
        XCTAssertEqual(fake.requests.count, 1); XCTAssertEqual(fake.requests[0].httpMethod, "POST")
        XCTAssertEqual(fake.requests[0].url?.path, "/api/points/list")
        let body = String(data: fake.requests[0].httpBody ?? Data(), encoding: .utf8)!
        XCTAssertFalse(body.contains("pageNum")); XCTAssertFalse(body.contains("change_type"))
    }
    func testPageFailureRetainsRowsAndRetriesSameRawPage() async throws {
        let active = scope(), fake = PointsLedgerTransport { n in
            if n == 2 { throw URLError(.timedOut) }
            return self.payload([n == 1 ? 1 : 2], paged: true)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let owner = WalletPointsLedgerPresentation.Owner(reader: reader, kind: .points)
        await model.load(reader: reader, kind: .points); await model.load(reader: reader, kind: .points)
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [1]); XCTAssertEqual(model.snapshot(for: owner).failure, .retryable)
        await model.load(reader: reader, kind: .points)
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [1, 2]); XCTAssertFalse(model.snapshot(for: owner).hasMore)
        for request in fake.requests.dropFirst() {
            XCTAssertTrue(String(data: request.httpBody!, encoding: .utf8)!.contains("name=\"pageNum\"\r\n\r\n2"))
        }
    }
    func testDuplicatePageFailsWithoutAdvancingThenCanRecover() async throws {
        let active = scope(), fake = PointsLedgerTransport { n in self.payload([n <= 2 ? 1 : 2], paged: true) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let owner = WalletPointsLedgerPresentation.Owner(reader: reader, kind: .points)
        await model.load(reader: reader, kind: .points); await model.load(reader: reader, kind: .points)
        XCTAssertEqual(model.snapshot(for: owner).failure, .retryable)
        await model.load(reader: reader, kind: .points)
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [1, 2])
    }
    func testReaderKindAndScopeMaskOldSnapshotBeforeAnotherLoad() async throws {
        var active = scope()
        let fake = PointsLedgerTransport { _ in self.payload([1]) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        await model.load(reader: reader, kind: .assetPoints)
        let otherReader = try self.reader(fake) { (active, "synthetic") }
        XCTAssertFalse(model.snapshot(for: .init(reader: otherReader, kind: .assetPoints)).loaded)
        XCTAssertFalse(model.snapshot(for: .init(reader: reader, kind: .points)).loaded)
        active = scope(account: 8)
        XCTAssertTrue(model.snapshot(for: .init(reader: reader, kind: .assetPoints)).rows.isEmpty)
        await model.load(reader: reader, kind: .assetPoints)
        XCTAssertEqual(fake.requests.count, 2)
    }
    func testRefreshRejectsLateSuccessAndDoesNotClearNewLoading() async throws {
        let active = scope(); var pending: [CheckedContinuation<(Data, Int), Error>] = []
        let fake = PointsLedgerTransport { _ in try await withCheckedThrowingContinuation { pending.append($0) } }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let owner = WalletPointsLedgerPresentation.Owner(reader: reader, kind: .assetPoints)
        let first = Task { await model.load(reader: reader, kind: .assetPoints) }
        try await waitUntil { pending.count >= 1 }
        let refresh = Task { await model.load(reader: reader, kind: .assetPoints, refresh: true) }
        try await waitUntil { pending.count >= 2 }
        pending[0].resume(returning: payload([1])); await first.value
        XCTAssertTrue(model.snapshot(for: owner).isLoading); XCTAssertTrue(model.snapshot(for: owner).rows.isEmpty)
        pending[1].resume(returning: payload([2])); await refresh.value
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [2]); XCTAssertFalse(model.snapshot(for: owner).isLoading)
    }
    func testAccountSwitchLateFailureCannotReplaceNewSuccess() async throws {
        var active = scope(); var old: CheckedContinuation<(Data, Int), Error>?
        let fake = PointsLedgerTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { old = $0 } }
            return self.payload([2])
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let first = Task { await model.load(reader: reader, kind: .assetPoints) }
        try await waitUntil { old != nil }; active = scope(account: 8)
        await model.load(reader: reader, kind: .assetPoints)
        old!.resume(throwing: URLError(.timedOut)); await first.value
        let value = model.snapshot(for: .init(reader: reader, kind: .assetPoints))
        XCTAssertEqual(value.rows.map(\.id), [2]); XCTAssertNil(value.failure)
    }
    func testCancelAndReenterRejectLateResponse() async throws {
        let active = scope(); var old: CheckedContinuation<(Data, Int), Error>?
        let fake = PointsLedgerTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { old = $0 } }
            return self.payload([2])
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let first = Task { await model.load(reader: reader, kind: .assetPoints) }
        try await waitUntil { old != nil }; model.cancel()
        await model.load(reader: reader, kind: .assetPoints, refresh: true)
        old!.resume(returning: payload([1])); await first.value
        XCTAssertEqual(model.snapshot(for: .init(reader: reader, kind: .assetPoints)).rows.map(\.id), [2])
    }
    func testFailuresAreNotSuccessfulEmptyAndRemainOwnerBound() async throws {
        let active = scope()
        for (status, expected) in [(401, WalletPointsLedgerPresentation.Failure.login), (500, .retryable)] {
            let fake = PointsLedgerTransport { _ in (Data("{\"code\":\(status)}".utf8), status) }
            let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
            await model.load(reader: reader, kind: .assetPoints)
            let value = model.snapshot(for: .init(reader: reader, kind: .assetPoints))
            XCTAssertFalse(value.loaded); XCTAssertEqual(value.failure, expected)
            XCTAssertNil(model.snapshot(for: .init(reader: reader, kind: .points)).failure)
        }
        let unavailable = WalletCommerceReader(session: { (active, "synthetic") }), model = WalletPointsLedgerPresentation()
        await model.load(reader: unavailable, kind: .assetPoints)
        XCTAssertEqual(model.snapshot(for: .init(reader: unavailable, kind: .assetPoints)).failure, .unavailable)
    }
    func testEmptySuccessIsLoadedAndCannotInventMoreAssetPages() async throws {
        let active = scope(), fake = PointsLedgerTransport { _ in self.payload([]) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        await model.load(reader: reader, kind: .assetPoints)
        let value = model.snapshot(for: .init(reader: reader, kind: .assetPoints))
        XCTAssertTrue(value.loaded); XCTAssertTrue(value.rows.isEmpty); XCTAssertFalse(value.hasMore)
        XCTAssertNil(value.failure)
    }
    func testConcurrentLoadDoesNotDispatchDuplicateAndCancellationRetriesPageOne() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = PointsLedgerTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.payload([2], paged: true)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletPointsLedgerPresentation()
        let first = Task { await model.load(reader: reader, kind: .points) }
        try await waitUntil { pending != nil }
        await model.load(reader: reader, kind: .points); XCTAssertEqual(fake.requests.count, 1)
        first.cancel(); pending!.resume(returning: payload([1], paged: true)); await first.value
        let owner = WalletPointsLedgerPresentation.Owner(reader: reader, kind: .points)
        XCTAssertFalse(model.snapshot(for: owner).isLoading); XCTAssertNil(model.snapshot(for: owner).failure)
        XCTAssertTrue(model.snapshot(for: owner).rows.isEmpty)
        await model.load(reader: reader, kind: .points)
        XCTAssertTrue(String(data: fake.requests.last!.httpBody!, encoding: .utf8)!.contains("name=\"pageNum\"\r\n\r\n1"))
        XCTAssertEqual(model.snapshot(for: owner).rows.map(\.id), [2])
    }
    func testReplacementReaderSameScopeRejectsLateOldSuccess() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let oldFake = PointsLedgerTransport { _ in try await withCheckedThrowingContinuation { pending = $0 } }
        let oldReader = try reader(oldFake) { (active, "synthetic") }
        let newReader = try reader(PointsLedgerTransport { _ in self.payload([2]) }) { (active, "synthetic") }
        let model = WalletPointsLedgerPresentation()
        let old = Task { await model.load(reader: oldReader, kind: .assetPoints) }
        try await waitUntil { pending != nil }
        await model.load(reader: newReader, kind: .assetPoints)
        pending!.resume(returning: payload([1])); await old.value
        XCTAssertEqual(model.snapshot(for: .init(reader: newReader, kind: .assetPoints)).rows.map(\.id), [2])
        XCTAssertFalse(model.snapshot(for: .init(reader: oldReader, kind: .assetPoints)).loaded)
    }
}
