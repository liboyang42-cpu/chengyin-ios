import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SupportLandingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest, Int) async throws -> (Data, Int)
    init(_ handler: @escaping (URLRequest, Int) async throws -> (Data, Int)) { self.handler = handler }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try await handler(request, requests.count)
    }
}
@MainActor final class WithdrawalSupportReadPresentationTests: XCTestCase {
    private func scope(account: Int = 7) -> WalletCommerceScope { .init(namespace: "synthetic", accountID: account, epoch: UUID()) }
    private func reader(_ fake: SupportLandingTransport, onUnauthorized: @escaping (WalletCommerceScope) -> Void = { _ in }, session: @escaping () -> (scope: WalletCommerceScope, token: String)?) throws -> WalletCommerceReader {
        .init(service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: fake), onUnauthorized: onUnauthorized, session: session)
    }
    private func balance(_ amount: Int = 5) -> (Data, Int) { (Data("{\"code\":200,\"data\":{\"balance\":\(amount)}}".utf8), 200) }
    private func stages(_ amount: Int = 2) -> (Data, Int) {
        (Data("{\"code\":200,\"data\":{\"pendingSettlement\":\(amount),\"disputed\":0,\"withdrawable\":0,\"complaintPeriod\":[]}}".utf8), 200)
    }
    private func success(_ request: URLRequest) -> (Data, Int) { request.url!.path.hasSuffix("api/user/info") ? balance() : stages() }
    private func unauthorized() -> (Data, Int) { (Data("{\"code\":401}".utf8), 401) }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<10_000 { if condition() { return }; await Task.yield() }
        throw URLError(.timedOut)
    }
    func testExactCurrentAccountReadAndStageJSONArePreserved() async throws {
        let active = scope(), fake = SupportLandingTransport { request, _ in self.success(request) }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.balance?.balance.value, 5); XCTAssertNil(value.balance?.currency)
        XCTAssertEqual(value.stages?.pendingSettlement.value, 2); XCTAssertNil(value.stages?.currency)
        XCTAssertNil(value.balanceFailure); XCTAssertNil(value.stagesFailure)
        XCTAssertEqual(fake.requests.map { $0.url!.path }, ["/api/user/info", "/api/wallet/stages"])
        XCTAssertTrue(String(data: fake.requests[0].httpBody!, encoding: .utf8)!.contains("name=\"member_id\"\r\n\r\n7"))
        XCTAssertEqual(fake.requests[1].httpBody, Data("{}".utf8))
        for request in fake.requests { XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic") }
    }
    func testBalanceAndStagesHaveIndependentRetryableOutcomes() async throws {
        let active = scope()
        for failing in ["/api/user/info", "/api/wallet/stages"] {
            let fake = SupportLandingTransport { request, _ in
                if request.url!.path == failing { throw URLError(.timedOut) }; return self.success(request)
            }
            let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
            model.activate(reader: reader); await model.reload(reader: reader)
            let value = model.snapshot(for: .init(reader: reader))
            if failing.hasSuffix("info") {
                XCTAssertNil(value.balance); XCTAssertEqual(value.balanceFailure, .retryable); XCTAssertNotNil(value.stages)
            } else { XCTAssertNotNil(value.balance); XCTAssertNil(value.stages); XCTAssertEqual(value.stagesFailure, .retryable) }
            XCTAssertFalse(value.balanceLoading); XCTAssertFalse(value.stagesLoading)
        }
    }
    func testKnownUnauthorizedBalanceStopsSiblingRead() async throws {
        let active = scope(); var expired: [WalletCommerceScope] = []
        let fake = SupportLandingTransport { _, _ in self.unauthorized() }
        let reader = try reader(fake, onUnauthorized: { expired.append($0) }) { (active, "synthetic") }
        let model = WithdrawalSupportReadPresentation(); model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.balanceFailure, .login); XCTAssertEqual(value.stagesFailure, .login)
        XCTAssertNil(value.balance); XCTAssertNil(value.stages); XCTAssertEqual(fake.requests.count, 1); XCTAssertEqual(expired, [active])
    }
    func testUnauthorizedStageRetiresPreviouslySuccessfulBalance() async throws {
        let active = scope(), fake = SupportLandingTransport { request, n in n == 1 ? self.balance() : self.unauthorized() }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertNil(value.balance); XCTAssertNil(value.stages)
        XCTAssertEqual(value.balanceFailure, .login); XCTAssertEqual(value.stagesFailure, .login)
    }
    func testEndpointSpecificDenialDoesNotEraseAuthorizedSibling() async throws {
        let active = scope(), fake = SupportLandingTransport { request, n in
            if n == 1 { throw APIError.notConfigured }; return self.stages()
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: reader); await model.reload(reader: reader)
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.balanceFailure, .unavailable); XCTAssertNotNil(value.stages); XCTAssertNil(value.stagesFailure)
    }
    func testOriginalNewAccountZeroRuleRequiresSuccessfulUserDataObject() async throws {
        let active = scope()
        for (raw, expectedZero) in [("{\"code\":200,\"data\":{}}", true), ("{\"code\":200}", false), ("{\"code\":500,\"data\":{}}", false)] {
            let fake = SupportLandingTransport { request, n in n == 1 ? (Data(raw.utf8), 200) : self.stages() }
            let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
            model.activate(reader: reader); await model.reload(reader: reader)
            let value = model.snapshot(for: .init(reader: reader))
            if expectedZero { XCTAssertEqual(value.balance?.balance.value, 0); XCTAssertNil(value.balanceFailure) }
            else { XCTAssertNil(value.balance); XCTAssertEqual(value.balanceFailure, .retryable) }
            XCTAssertNotNil(value.stages)
        }
    }
    func testRefreshMasksBothValuesAndLateResponseCannotDispatchOldSibling() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = SupportLandingTransport { request, n in
            if n == 3 { return try await withCheckedThrowingContinuation { pending = $0 } }
            return self.success(request)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        let owner = WithdrawalSupportReadPresentation.Owner(reader: reader)
        model.activate(reader: reader); await model.reload(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        XCTAssertNil(model.snapshot(for: owner).balance); XCTAssertNil(model.snapshot(for: owner).stages)
        XCTAssertTrue(model.snapshot(for: owner).balanceLoading); XCTAssertTrue(model.snapshot(for: owner).stagesLoading)
        await model.reload(reader: reader); pending!.resume(returning: balance(99)); await old.value
        XCTAssertEqual(model.snapshot(for: owner).balance?.balance.value, 5)
        XCTAssertEqual(fake.requests.count, 5) // Initial pair, held old balance, fresh pair.
    }
    func testAccountSwitchMasksEveryStateAndLate401CannotExpireNewAccount() async throws {
        var active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?; var expired: [WalletCommerceScope] = []
        let fake = SupportLandingTransport { request, n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }; return self.success(request)
        }
        let reader = try reader(fake, onUnauthorized: { expired.append($0) }) { (active, "synthetic") }
        let model = WithdrawalSupportReadPresentation(); model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        active = scope(account: 8)
        let masked = model.snapshot(for: .init(reader: reader))
        XCTAssertNil(masked.balance); XCTAssertNil(masked.balanceFailure); XCTAssertFalse(masked.balanceLoading); XCTAssertFalse(masked.stagesLoading)
        model.activate(reader: reader); await model.reload(reader: reader)
        pending!.resume(returning: unauthorized()); await old.value
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertEqual(value.balance?.balance.value, 5); XCTAssertNotNil(value.stages); XCTAssertTrue(expired.isEmpty)
        XCTAssertEqual(fake.requests.count, 3)
    }
    func testReplacementReaderSameScopeRejectsOldStageFailureAndOldActions() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let oldFake = SupportLandingTransport { request, n in
            if n == 2 { return try await withCheckedThrowingContinuation { pending = $0 } }; return self.balance(99)
        }
        let oldReader = try reader(oldFake) { (active, "synthetic") }
        let freshFake = SupportLandingTransport { request, _ in self.success(request) }
        let fresh = try reader(freshFake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: oldReader)
        let old = Task { await model.reload(reader: oldReader) }; try await waitUntil { pending != nil }
        XCTAssertNil(model.snapshot(for: .init(reader: fresh)).balance)
        model.activate(reader: fresh); await model.reload(reader: fresh); await model.reload(reader: oldReader)
        pending!.resume(throwing: URLError(.timedOut)); await old.value
        let value = model.snapshot(for: .init(reader: fresh))
        XCTAssertEqual(value.balance?.balance.value, 5); XCTAssertNil(value.stagesFailure)
        XCTAssertEqual(oldFake.requests.count, 2); XCTAssertEqual(freshFake.requests.count, 2)
    }
    func testDisappearRejectsPendingCompletionAndQueuedRetryUntilReactivated() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = SupportLandingTransport { request, n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }; return self.success(request)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        await model.reload(reader: reader); XCTAssertTrue(fake.requests.isEmpty)
        model.activate(reader: reader)
        let old = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        model.deactivate(); await model.reload(reader: reader); XCTAssertEqual(fake.requests.count, 1)
        model.activate(reader: reader); await model.reload(reader: reader)
        pending!.resume(returning: balance(99)); await old.value
        XCTAssertEqual(model.snapshot(for: .init(reader: reader)).balance?.balance.value, 5); XCTAssertEqual(fake.requests.count, 3)
    }
    func testCancellationStopsSiblingAndAllowsExplicitRetry() async throws {
        let active = scope(); var pending: CheckedContinuation<(Data, Int), Error>?
        let fake = SupportLandingTransport { request, n in
            if n == 1 { return try await withCheckedThrowingContinuation { pending = $0 } }; return self.success(request)
        }
        let reader = try reader(fake) { (active, "synthetic") }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: reader)
        let task = Task { await model.reload(reader: reader) }; try await waitUntil { pending != nil }
        task.cancel(); pending!.resume(returning: balance()); await task.value
        let value = model.snapshot(for: .init(reader: reader))
        XCTAssertFalse(value.balanceLoading); XCTAssertFalse(value.stagesLoading); XCTAssertNil(value.balanceFailure); XCTAssertNil(value.stagesFailure)
        XCTAssertEqual(fake.requests.count, 1)
        await model.reload(reader: reader); XCTAssertEqual(fake.requests.count, 3)
    }
    func testSignedOutAndUnconfiguredOwnersDoNotDispatch() async throws {
        let active = scope(), fake = SupportLandingTransport { request, _ in self.success(request) }
        let signedOut = try reader(fake) { nil }, model = WithdrawalSupportReadPresentation()
        model.activate(reader: signedOut); await model.reload(reader: signedOut)
        XCTAssertEqual(model.snapshot(for: .init(reader: signedOut)).balanceFailure, .login)
        let unavailable = WalletCommerceReader(session: { (active, "synthetic") })
        model.activate(reader: unavailable); await model.reload(reader: unavailable)
        XCTAssertEqual(model.snapshot(for: .init(reader: unavailable)).stagesFailure, .unavailable)
        XCTAssertTrue(fake.requests.isEmpty)
    }
}
