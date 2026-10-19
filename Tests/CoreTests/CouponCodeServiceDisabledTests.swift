import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program coupon-qr parity (w2-05): server code 503 stops refresh and polling until an
/// explicit retry, and a not-yet-started coupon exposes its start time without a code.
@MainActor final class CouponCodeServiceDisabledTests: XCTestCase {
    private func session() throws -> CouponCodeSession {
        try .init(accountID: 1, epoch: 1, namespace: "synthetic-cn", role: "player", token: "synthetic-token")
    }
    private func receipt(_ extra: String = "") throws -> CouponCodeReceipt {
        try JSONDecoder().decode(CouponCodeReceipt.self, from: Data("{\"useStatus\":0,\"expiresIn\":60,\"token\":\"SYNTHETIC-NOT-REDEEMABLE\"\(extra)}".utf8))
    }
    private func http(_ body: String, status: Int = 200) throws -> (CouponCodeHTTPService, ServiceDisabledTransport) {
        let transport = ServiceDisabledTransport(body: body, status: status)
        return (CouponCodeHTTPService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: true), transport)
    }
    func testIssueAndStatusMap503ToServiceDisabled() async throws {
        for (body, status) in [(#"{"code":503,"msg":"off"}"#, 200), ("", 503)] {
            let (service, _) = try http(body, status: status)
            do { _ = try await service.issue(historyID: 7, session: session()); XCTFail() }
            catch { XCTAssertEqual(error as? CouponCodeFailure, .serviceDisabled) }
            do { _ = try await service.status(historyID: 7, session: session()); XCTFail() }
            catch { XCTAssertEqual(error as? CouponCodeFailure, .serviceDisabled) }
        }
    }
    func testOtherServerFailuresKeepTheirExistingMapping() async throws {
        let (service, _) = try http("", status: 502)
        do { _ = try await service.issue(historyID: 7, session: session()); XCTFail() }
        catch { XCTAssertEqual(error as? CouponCodeFailure, .failed) }
    }
    func testServiceDisabledStopsAutomaticRetryUntilExplicitRetry() async throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let api = ServiceDisabledFixtureService(receipt: try receipt()), owner = try session()
        api.issueFailure = .serviceDisabled
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { clock })
        await model.confirmPresentation()
        XCTAssertEqual(model.phase, .serviceDisabled); XCTAssertNil(model.displayToken); XCTAssertEqual(api.issues, 1)
        clock = clock.addingTimeInterval(60); await model.tick()
        XCTAssertEqual(api.issues, 1); XCTAssertEqual(api.polls, 0); XCTAssertEqual(model.phase, .serviceDisabled)
        api.issueFailure = nil; await model.retry()
        XCTAssertEqual(api.issues, 2); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.displayToken, "SYNTHETIC-NOT-REDEEMABLE")
        clock = clock.addingTimeInterval(6); await model.tick()
        XCTAssertEqual(api.polls, 1)
    }
    func testPollServiceDisabledHidesCode() async throws {
        let clock = Date(timeIntervalSince1970: 1_000_000)
        var now = clock
        let api = ServiceDisabledFixtureService(receipt: try receipt()), owner = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { now })
        await model.confirmPresentation(); XCTAssertEqual(model.phase, .ready)
        api.statusFailure = .serviceDisabled; now = clock.addingTimeInterval(6); await model.tick()
        XCTAssertEqual(model.phase, .serviceDisabled); XCTAssertNil(model.displayToken); XCTAssertFalse(model.pollDelayed)
    }
    func testWaitingReceiptKeepsStartTimeForDisplayWithoutAToken() async throws {
        let now = try XCTUnwrap(OrderLifecycleTime.date("2026-10-02 09:00:00"))
        let api = ServiceDisabledFixtureService(receipt: try receipt(",\"startTime\":\"2026-10-02 10:00:00\"")), owner = try session()
        let model = CouponCodeCoordinator(historyID: 71, service: api, currentSession: { owner }, now: { now })
        await model.confirmPresentation()
        XCTAssertEqual(model.phase, .waiting); XCTAssertNil(model.displayToken)
        XCTAssertEqual(model.receipt?.startTime, "2026-10-02 10:00:00")
    }
}

@MainActor private final class ServiceDisabledFixtureService: CouponCodeServing {
    let enabled = true
    var issues = 0, polls = 0
    var issueFailure: CouponCodeFailure?
    var statusFailure: CouponCodeFailure?
    let receipt: CouponCodeReceipt
    init(receipt: CouponCodeReceipt) { self.receipt = receipt }
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt {
        issues += 1; if let issueFailure { throw issueFailure }; return receipt
    }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus {
        polls += 1; if let statusFailure { throw statusFailure }
        return try JSONDecoder().decode(OrderCouponStatus.self, from: Data(#"{"useStatus":0}"#.utf8))
    }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.mediaUnavailable }
}
private final class ServiceDisabledTransport: HTTPTransport {
    let body: String, status: Int
    init(body: String, status: Int) { self.body = body; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(body.utf8), status) }
}
