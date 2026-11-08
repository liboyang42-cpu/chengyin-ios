import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class AssetsEntryTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (Int) async throws -> (Data, Int)
    init(_ handler: @escaping (Int) async throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await handler(requests.count)
    }
}
@MainActor final class WalletAssetsReadPresentationTests: XCTestCase {
    private func scope(account: Int = 7, namespace: String = "synthetic") -> WalletCommerceScope {
        .init(namespace: namespace, accountID: account, epoch: UUID())
    }
    private func reader(_ fake: AssetsEntryTransport, onUnauthorized: @escaping (WalletCommerceScope) -> Void = { _ in }, session: @escaping () -> (scope: WalletCommerceScope, token: String)?) throws -> WalletCommerceReader {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test")!)
        return WalletCommerceReader(service: .init(configuration: config, transport: fake), onUnauthorized: onUnauthorized, session: session)
    }
    private func payload(_ available: Int = 5, known: Bool = true) -> (Data, Int) {
        (Data("{\"code\":200,\"data\":{\"pendingSettlement\":0,\"disputed\":0,\"withdrawable\":\(available),\"complaintPeriod\":[],\"amountsKnown\":\(known)}}".utf8), 200)
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        throw URLError(.timedOut)
    }
    func testInactiveAndRetiredCallbacksCannotDispatch() async throws {
        let active = scope(), fake = AssetsEntryTransport { _ in self.payload() }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        await model.reload(reader: reader); XCTAssertTrue(fake.requests.isEmpty)
        model.activate(reader: reader); await model.reload(reader: reader)
        XCTAssertEqual(fake.requests.count, 1)
        model.deactivate(); await model.reload(reader: reader)
        XCTAssertEqual(fake.requests.count, 1)
        XCTAssertNil(model.snapshot(for: .init(reader: reader)).stages)
    }
    func testOriginalStagePOSTUsesEmptyJSONAndKeepsMoneySeparate() async throws {
        let active = scope(), fake = AssetsEntryTransport { _ in self.payload(0, known: false) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.stages?.withdrawable.value, 0); XCTAssertEqual(value.stages?.amountsKnown, false)
        XCTAssertNil(value.stages?.currency); XCTAssertNil(value.failure); XCTAssertFalse(value.isLoading)
        let request = try XCTUnwrap(fake.requests.first)
        XCTAssertEqual(request.url?.path, "/api/wallet/stages"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, Data("{}".utf8)); XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testScopeAccountNamespaceAndEpochMaskAllStateBeforeReload() async throws {
        var active = scope(); let first = active
        let fake = AssetsEntryTransport { _ in self.payload() }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        for other in [scope(account: 8), scope(namespace: "another"), scope()] {
            active = other
            let masked = model.snapshot(for: .init(reader: reader))
            XCTAssertNil(masked.stages); XCTAssertNil(masked.failure); XCTAssertFalse(masked.isLoading)
            await model.reload(reader: reader) // stale action cannot activate the new owner
            XCTAssertEqual(fake.requests.count, 1)
        }
        XCTAssertNotEqual(active.epoch, first.epoch)
        model.activate(reader: reader); await model.reload(reader: reader)
        XCTAssertEqual(fake.requests.count, 2)
    }
    func testReplacementReaderSameScopeMasksOldValueAndRejectsOldCallbacks() async throws {
        let active = scope(), fake = AssetsEntryTransport { _ in self.payload() }
        let old = try reader(fake) { (active, "synthetic") }, fresh = try reader(fake) { (active, "synthetic") }
        let model = WalletAssetsReadPresentation()
        model.activate(reader: old); await model.reload(reader: old)
        XCTAssertNil(model.snapshot(for: .init(reader: fresh)).stages)
        model.activate(reader: fresh); await model.reload(reader: old)
        XCTAssertEqual(fake.requests.count, 1)
        await model.reload(reader: fresh); XCTAssertEqual(fake.requests.count, 2)
    }
    func testRefreshRemovesPreviousAmountsAndIgnoresOlderSuccess() async throws {
        let active = scope(); var pending: [CheckedContinuation<(Data, Int), Error>] = []
        let fake = AssetsEntryTransport { n in
            if n == 1 { return self.payload(1) }
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let owner = WalletAssetsReadPresentation.Owner(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending.count == 1 }
        XCTAssertNil(model.snapshot(for: owner).stages); XCTAssertTrue(model.snapshot(for: owner).isLoading)
        let fresh = Task { await model.reload(reader: reader) }; try await waitUntil { pending.count == 2 }
        pending[0].resume(returning: payload(9)); await old.value
        XCTAssertNil(model.snapshot(for: owner).stages); XCTAssertTrue(model.snapshot(for: owner).isLoading)
        pending[1].resume(returning: payload(2)); await fresh.value
        XCTAssertEqual(model.snapshot(for: owner).stages?.withdrawable.value, 2)
    }
    func testRefreshLateFailureCannotReplaceFreshSuccess() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = AssetsEntryTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.payload(2)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        await model.reload(reader: reader); pending!.resume(throwing: URLError(.timedOut)); await old.value
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.stages?.withdrawable.value, 2); XCTAssertNil(value.failure); XCTAssertFalse(value.isLoading)
    }
    func testAccountSwitchLateUnauthorizedCannotExpireNewAccountOrShowItsError() async throws {
        var active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?; var expired: [WalletCommerceScope] = []
        let fake = AssetsEntryTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.payload(2)
        }
        let reader = try reader(fake, onUnauthorized: { expired.append($0) }) { (active, "synthetic") }
        let model = WalletAssetsReadPresentation(); model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        active = scope(account: 8); model.activate(reader: reader); await model.reload(reader: reader)
        pending!.resume(returning: (Data("{\"code\":401}".utf8), 401)); await old.value
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.stages?.withdrawable.value, 2); XCTAssertNil(value.failure); XCTAssertTrue(expired.isEmpty)
    }
    func testDisappearAndReenterRejectsOldResponseAndHidesLoading() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = AssetsEntryTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.payload(2)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        model.deactivate(); XCTAssertFalse(model.snapshot(for: .init(reader: reader)).isLoading)
        model.activate(reader: reader); await model.reload(reader: reader)
        pending!.resume(returning: payload(1)); await old.value
        XCTAssertEqual(model.snapshot(for: .init(reader: reader)).stages?.withdrawable.value, 2)
    }
    func testFailedRefreshDoesNotRetainOldAmountsAndRetryRecovers() async throws {
        let active = scope(), fake = AssetsEntryTransport { n in
            if n == 2 { throw URLError(.timedOut) }; return self.payload(n)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        let owner = WalletAssetsReadPresentation.Owner(reader: reader)
        model.activate(reader: reader); await model.reload(reader: reader); await model.reload(reader: reader)
        XCTAssertNil(model.snapshot(for: owner).stages); XCTAssertEqual(model.snapshot(for: owner).failure, .retryable)
        await model.reload(reader: reader)
        XCTAssertEqual(model.snapshot(for: owner).stages?.withdrawable.value, 3); XCTAssertNil(model.snapshot(for: owner).failure)
    }
    func testMalformedMissingAndBusinessFailureNeverBecomeZeroAssets() async throws {
        let active = scope()
        for payload in ["{\"code\":200,\"data\":{}}", "{\"code\":500,\"data\":{}}", "{\"code\":200,\"data\":{\"pendingSettlement\":0,\"disputed\":0,\"withdrawable\":-1,\"complaintPeriod\":[]}}"] {
            let reader = try reader(AssetsEntryTransport { _ in (Data(payload.utf8), 200) }) { (active, "synthetic") }
            let model = WalletAssetsReadPresentation(); model.activate(reader: reader); await model.reload(reader: reader)
            let value = model.snapshot(for: .init(reader: reader))
            XCTAssertNil(value.stages); XCTAssertEqual(value.failure, .retryable)
        }
    }
    func testUnavailableAndLoginAreExplicitAndNeverDispatchUnconfiguredSource() async throws {
        let active = scope()
        let unavailable = WalletCommerceReader(session: { (active, "synthetic") })
        let model = WalletAssetsReadPresentation(); model.activate(reader: unavailable); await model.reload(reader: unavailable)
        XCTAssertEqual(model.snapshot(for: .init(reader: unavailable)).failure, .unavailable)
        let fake = AssetsEntryTransport { _ in throw APIError.notConfigured }
        let denied = try reader(fake) { (active, "synthetic") }
        model.activate(reader: denied); await model.reload(reader: denied)
        XCTAssertEqual(model.snapshot(for: .init(reader: denied)).failure, .unavailable)
        let signedOut = try reader(fake) { nil }
        model.activate(reader: signedOut); await model.reload(reader: signedOut)
        XCTAssertEqual(model.snapshot(for: .init(reader: signedOut)).failure, .login)
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testCancelledRefreshLeavesNoFalseFailureAndCanRetry() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = AssetsEntryTransport { n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.payload(2)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WalletAssetsReadPresentation()
        model.activate(reader: reader)
        let task = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        task.cancel(); pending!.resume(returning: payload()); await task.value
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertNil(value.stages); XCTAssertNil(value.failure); XCTAssertFalse(value.isLoading)
        await model.reload(reader: reader)
        XCTAssertEqual(model.snapshot(for: .init(reader: reader)).stages?.withdrawable.value, 2)
    }
}
