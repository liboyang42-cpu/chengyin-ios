import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CouponCodePresentationTests: XCTestCase {
    private func session(epoch: UInt64 = 1) throws -> CouponCodeSession {
        try .init(accountID: 1, epoch: epoch, namespace: "synthetic-cn", role: "player", token: "synthetic-token")
    }
    private func receipt(status: Int = 0, ttl: Int = 60, extra: String = "") throws -> CouponCodeReceipt {
        try JSONDecoder().decode(CouponCodeReceipt.self, from: Data("{\"useStatus\":\(status),\"expiresIn\":\(ttl),\"token\":\"SYNTHETIC-NOT-REDEEMABLE\",\"couponName\":\"Synthetic coupon\"\(extra)}".utf8))
    }
    func testReceiptRejectsUnknownStatusInvalidLifetimeAndMissingCredential() {
        for raw in [#"{"useStatus":4,"expiresIn":60,"token":"A"}"#, #"{"useStatus":0,"expiresIn":91,"token":"A"}"#, #"{"useStatus":0,"expiresIn":0,"token":"A"}"#, #"{"useStatus":0,"expiresIn":60,"qrcodeUrl":"http://example.test/q.png"}"#, #"{"useStatus":0,"expiresIn":60}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(CouponCodeReceipt.self, from: Data(raw.utf8)))
        }
    }
    func testTerminalReceiptNeedsNoCredentialOrTTL() throws {
        let value = try JSONDecoder().decode(CouponCodeReceipt.self, from: Data(#"{"useStatus":1}"#.utf8))
        XCTAssertEqual(value.useStatus, 1); XCTAssertNil(value.token); XCTAssertNil(value.imageURL)
    }
    func testStartTimeUsesChinaSemanticsAndMalformedDateFailsClosed() throws {
        let value = try receipt(extra: ",\"startTime\":\"2026-10-02 10:00:00\"")
        XCTAssertFalse(value.hasStarted(at: try XCTUnwrap(OrderLifecycleTime.date("2026-10-02 09:59:59"))))
        XCTAssertTrue(value.hasStarted(at: try XCTUnwrap(OrderLifecycleTime.date("2026-10-02 10:00:00"))))
        XCTAssertFalse(try receipt(extra: ",\"startTime\":\"bad date\"").hasStarted(at: Date()))
    }
    func testDefaultServiceCannotIssuePollOrFetchImage() async throws {
        let transport = CouponCodeTestTransport { _ in XCTFail("Default-off service dispatched"); return (Data(), 200) }
        let service = CouponCodeHTTPService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport)
        do { _ = try await service.issue(historyID: 7, session: session()); XCTFail() } catch { XCTAssertEqual(error as? CouponCodeFailure, .disabled) }
        do { _ = try await service.status(historyID: 7, session: session()); XCTFail() } catch { XCTAssertEqual(error as? CouponCodeFailure, .disabled) }
        do { _ = try await service.image(receipt()); XCTFail() } catch { XCTAssertEqual(error as? CouponCodeFailure, .mediaUnavailable) }
        XCTAssertEqual(transport.requests.count, 0)
    }
    func testIssueUsesExactHistoryIDContractAndStatusMaps410() async throws {
        let transport = CouponCodeTestTransport { request in
            if request.url?.path.hasSuffix("/status") == true { return (Data(#"{"code":410}"#.utf8), 200) }
            return (Data(#"{"code":200,"data":{"useStatus":0,"expiresIn":60,"token":"SYNTHETIC"}}"#.utf8), 200)
        }
        let service = CouponCodeHTTPService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: true)
        _ = try await service.issue(historyID: 71, session: session())
        XCTAssertEqual(transport.requests[0].url?.path, "/api/coupon/qr-token")
        let body = String(decoding: try XCTUnwrap(transport.requests[0].httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"couponHistoryId\"")); XCTAssertFalse(body.contains("name=\"couponId\""))
        do { _ = try await service.status(historyID: 71, session: session()); XCTFail() } catch { XCTAssertEqual(error as? CouponCodeFailure, .unavailable) }
    }
    func testNoIssuanceBeforeReviewAndRepeatedConfirmationIsSingleFlight() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await model.tick(); XCTAssertEqual(api.issues, 0); XCTAssertEqual(model.phase, .review)
        await model.confirmPresentation(); await model.confirmPresentation()
        XCTAssertEqual(api.issues, 1); XCTAssertEqual(model.displayToken, "SYNTHETIC-NOT-REDEEMABLE")
    }
    func testMissingOwnerAndDisabledConfigurationDoNotIssue() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt())
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { nil })
        await model.confirmPresentation(); XCTAssertEqual(model.phase, .login); XCTAssertEqual(api.issues, 0)
        api.enabled = false; let owner = try session()
        let dormant = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await dormant.confirmPresentation(); XCTAssertEqual(dormant.phase, .disabled); XCTAssertEqual(api.issues, 0)
    }
    func testExpiryUsesRequestStartAndRefreshesAtDeadline() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        var date = Date(timeIntervalSince1970: 100)
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { date })
        await model.confirmPresentation(); XCTAssertTrue(model.canDisplay)
        date = date.addingTimeInterval(61); XCTAssertFalse(model.canDisplay)
        await model.tick(); XCTAssertEqual(api.issues, 2); XCTAssertTrue(model.canDisplay)
    }
    func testDelayedIssueDoesNotGetFreshLifetimeAtResponseTime() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        var date = Date(timeIntervalSince1970: 100)
        api.onIssue = { date = date.addingTimeInterval(61) }
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { date })
        await model.confirmPresentation(); XCTAssertEqual(model.phase, .failed); XCTAssertNil(model.displayToken)
    }
    func testPollTerminalClearsCredentialAndStopsAllRenewal() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        var date = Date(timeIntervalSince1970: 100)
        api.statusValue = 1
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { date })
        await model.confirmPresentation(); date = date.addingTimeInterval(5); await model.tick()
        XCTAssertEqual(model.phase, .used); XCTAssertNil(model.displayToken); XCTAssertNil(model.receipt)
        date = date.addingTimeInterval(500); await model.tick(); await model.retry()
        XCTAssertEqual(api.issues, 1); XCTAssertEqual(api.polls, 1)
    }
    func testPollFailureKeepsUnexpiredCodeBut410RemovesIt() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        var date = Date(timeIntervalSince1970: 100)
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { date })
        await model.confirmPresentation(); api.statusFailure = .failed
        date = date.addingTimeInterval(5); await model.tick(); XCTAssertTrue(model.pollDelayed); XCTAssertTrue(model.canDisplay)
        api.statusFailure = .unavailable; date = date.addingTimeInterval(5); await model.tick()
        XCTAssertEqual(model.phase, .unavailable); XCTAssertNil(model.displayToken)
    }
    func testOwnerReplacementDropsLateIssueAndEveryPrivatePixel() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt())
        var owner: CouponCodeSession? = try session(); let next = try session(epoch: 2)
        api.onIssue = { owner = next }
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await model.confirmPresentation(); XCTAssertNil(model.receipt); XCTAssertNil(model.displayToken); XCTAssertNil(model.imageBytes)
        await model.tick(); XCTAssertEqual(model.phase, .stale)
    }
    func testPauseClearsCredentialAndResumeIssuesFreshOnlyForSameOwner() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt())
        var owner: CouponCodeSession? = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await model.confirmPresentation(); model.pause(); XCTAssertNil(model.displayToken); XCTAssertNil(model.receipt)
        await model.tick(); XCTAssertEqual(api.issues, 1)
        await model.resume(); XCTAssertEqual(api.issues, 2)
        model.pause(); owner = nil; await model.resume(); XCTAssertEqual(model.phase, .stale); XCTAssertEqual(api.issues, 2)
    }
    func testDismissalPreventsLateReceiptAndPolling() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt()), owner = try session()
        var model: CouponCodeCoordinator!
        api.onIssue = { model.invalidate() }
        model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await model.confirmPresentation(); await model.tick()
        XCTAssertNil(model.receipt); XCTAssertNil(model.displayToken); XCTAssertEqual(api.polls, 0)
    }
    func testFutureStartNeverDisplaysQR() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt(extra: ",\"startTime\":\"2099-01-01 00:00:00\"")), owner = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        await model.confirmPresentation(); XCTAssertEqual(model.phase, .waiting); XCTAssertFalse(model.canDisplay); XCTAssertNil(model.displayToken)
    }
    func testRoleABAGenerationCannotRedisplayCachedCodeWithoutAnInterveningTick() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt())
        var owner = try CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 1)
        let old = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        let oldPresentation = try XCTUnwrap(old.beginPresentation())
        await old.confirmPresentation(permit: try XCTUnwrap(old.offerConfirmation(presentation: oldPresentation)))
        XCTAssertTrue(old.canDisplay); XCTAssertNotNil(old.displayToken)
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "merchant", token: "synthetic-token", viewerRevision: 2)
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 3)
        // No tick/pause/current-session read occurred between the two identity changes.
        XCTAssertFalse(old.canDisplay); XCTAssertNil(old.displayToken)
        await old.tick(presentation: oldPresentation)
        XCTAssertEqual(old.phase, .stale); XCTAssertNil(old.receipt); XCTAssertNil(old.imageBytes)
        let fresh = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        let presentation = try XCTUnwrap(fresh.beginPresentation())
        await fresh.confirmPresentation(permit: try XCTUnwrap(fresh.offerConfirmation(presentation: presentation)))
        XCTAssertTrue(fresh.canDisplay); XCTAssertNotNil(fresh.displayToken); XCTAssertEqual(api.issues, 2)
    }
    func testRoleABAGenerationRejectsQueuedConfirmationAndOldReopen() async throws {
        let api = CouponCodeFixtureService(receipt: try receipt())
        var owner = try CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 1)
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner })
        let presentation = try XCTUnwrap(model.beginPresentation())
        let queued = try XCTUnwrap(model.offerConfirmation(presentation: presentation))
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "merchant", token: "synthetic-token", viewerRevision: 2)
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 3)
        await model.confirmPresentation(permit: queued)
        XCTAssertEqual(api.issues, 0); XCTAssertEqual(model.phase, .stale)
        XCTAssertNil(model.beginPresentation()); XCTAssertNil(model.displayToken)
    }
    func testRoleABAGenerationDropsLateUnauthorizedButCurrentUnauthorizedStillApplies() async throws {
        let api = CouponCodeSuspendedIssueService()
        var owner = try CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 1)
        var unauthorized = 0
        let old = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, onUnauthorized: { _ in unauthorized += 1 })
        let started = expectation(description: "old issue suspended"); api.onIssue = { started.fulfill() }
        let task = Task { await old.confirmPresentation() }
        await fulfillment(of: [started], timeout: 2)
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "merchant", token: "synthetic-token", viewerRevision: 2)
        owner = try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 3)
        api.failUnauthorized(); await task.value
        XCTAssertEqual(unauthorized, 0); XCTAssertNil(old.displayToken); XCTAssertNil(old.receipt)
        let current = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, onUnauthorized: { _ in unauthorized += 1 })
        let currentStarted = expectation(description: "current issue suspended"); api.onIssue = { currentStarted.fulfill() }
        let currentTask = Task { await current.confirmPresentation() }
        await fulfillment(of: [currentStarted], timeout: 2); api.failUnauthorized(); await currentTask.value
        XCTAssertEqual(unauthorized, 1); XCTAssertEqual(current.phase, .login)
    }
    func testViewerGenerationRemainsLocalAndDoesNotChangeCouponIssueFields() async throws {
        let transport = CouponCodeTestTransport { _ in
            (Data(#"{"code":200,"data":{"useStatus":0,"expiresIn":60,"token":"SYNTHETIC"}}"#.utf8), 200)
        }
        let service = CouponCodeHTTPService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: true)
        let revised = try CouponCodeSession(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token", viewerRevision: 8)
        _ = try await service.issue(historyID: 71, session: revised)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/coupon/qr-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"couponHistoryId\"")); XCTAssertTrue(body.contains("\r\n71\r\n"))
        XCTAssertFalse(body.contains("viewerRevision")); XCTAssertFalse(body.contains("name=\"couponId\""))
        XCTAssertEqual(try session().viewerRevision, 0) // Existing initializer call sites remain source-compatible.
    }

}
@MainActor private final class CouponCodeFixtureService: CouponCodeServing {
    var enabled = true
    var issues = 0, polls = 0
    let receipt: CouponCodeReceipt
    var statusValue = 0
    var statusFailure: CouponCodeFailure?
    var onIssue: (() -> Void)?
    init(receipt: CouponCodeReceipt) { self.receipt = receipt }
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt { issues += 1; onIssue?(); return receipt }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        polls += 1; if let statusFailure { throw statusFailure }
        return try JSONDecoder().decode(OrderCouponStatus.self, from: Data("{\"useStatus\":\(statusValue)}".utf8))
    }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
}
private final class CouponCodeTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}

@MainActor private final class CouponCodeSuspendedIssueService: CouponCodeServing {
    let enabled = true
    var onIssue: (() -> Void)?
    private var continuation: CheckedContinuation<CouponCodeReceipt, Error>?
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        try await withCheckedThrowingContinuation { continuation = $0; onIssue?() }
    }
    func failUnauthorized() { let pending = continuation; continuation = nil; pending?.resume(throwing: CouponCodeFailure.unauthorized) }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus { throw CouponCodeFailure.failed }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
}
