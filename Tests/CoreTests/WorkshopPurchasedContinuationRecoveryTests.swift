import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Real read service, synthetic data only. Existing next-page replacement semantics stay intact.
@MainActor final class WorkshopPurchasedContinuationRecoveryTests: XCTestCase {
    final class Wire: HTTPTransport {
        var response: (Data, Int) = (Data(), 503), requests: [URLRequest] = [], pause = false, failNetwork = false
        var pending: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if pause { return try await withCheckedThrowingContinuation { pending = $0 } }
            if failNetwork { throw URLError(.timedOut) }
            return response
        }
        func wait() async { for _ in 0..<1000 { if pending != nil { return }; await Task.yield() }; XCTFail("Expected synthetic delayed continuation") }
        func releaseNetworkFailure() { let old = pending; pending = nil; old?.resume(throwing: URLError(.timedOut)) }
    }
    final class Fixture {
        let context: RuntimeDependencyContext, wire = Wire()
        var approval: WorkshopPurchasedReadApproval?
        lazy var lease = ContentDraftSessionLease(context: context, current: { [weak self] in self?.context })
        lazy var service = WorkshopPurchasedService(api: try! APIConfiguration(baseURL: context.baseURL), transport: wire, lease: lease, approval: approval, currentApproval: { [weak self] in self?.approval })
        lazy var browser = WorkshopPurchasedBrowser(reader: service, lease: lease)
        init() throws { context = try WorkshopOwnedTestData.context(); approval = try .init(context: context, expiresAt: .distantFuture) }
        func first() async throws -> WorkshopPurchasedPresentationPermit {
            var rows: [[String: Any]] = []
            for id in 100...149 { var row = WorkshopPurchasedTestData.item; row["licenseId"] = "w18-paid-\(id)"; rows.append(row) }
            wire.response = (try WorkshopPurchasedTestData.envelope(WorkshopPurchasedTestData.page(rows, next: 100)), 200)
            let permit = try XCTUnwrap(browser.presentList())
            await browser.load(action: try XCTUnwrap(permit.offer()))
            XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(browser.nextCursor, 100)
            return permit
        }
    }
    func testTransientContinuationRetainsOriginalPageAndRetriesExactCursor() async throws {
        let f = try Fixture(), permit = try await f.first()
        let rows = f.browser.rows, checked = f.browser.checkedAt
        f.wire.failNetwork = true
        await f.browser.load(before: 100, action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(f.browser.phase, .ready); XCTAssertEqual(f.browser.issue, .unavailable)
        XCTAssertEqual(f.browser.rows, rows); XCTAssertEqual(f.browser.checkedAt, checked); XCTAssertEqual(f.browser.nextCursor, 100)
        XCTAssertEqual(f.wire.requests.count, 2)
        f.wire.failNetwork = false
        f.wire.response = (try WorkshopPurchasedTestData.envelope(WorkshopPurchasedTestData.page()), 200)
        await f.browser.load(before: 100, action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(f.wire.requests.suffix(2).map { String(data: $0.httpBody ?? Data(), encoding: .utf8) }, ["before_order_line_id=100", "before_order_line_id=100"])
        XCTAssertEqual(f.browser.rows.count, 1) // original next-page replacement, not appended history
        XCTAssertEqual(f.browser.rows.first?.licenseId, "w18-paid-11")
        XCTAssertNil(f.browser.nextCursor); XCTAssertNil(f.browser.issue)
    }
    func test401RetiresInsteadOfRestoringOldPage() async throws {
        let f = try Fixture(), permit = try await f.first(); f.wire.response = (Data(), 401)
        await f.browser.load(before: 100, action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(f.browser.phase, .invalidated); XCTAssertEqual(f.browser.issue, .unauthorized)
        XCTAssertTrue(f.browser.rows.isEmpty); XCTAssertNil(f.browser.nextCursor)
        XCTAssertNil(permit.offer()); XCTAssertFalse(f.lease.isCurrent)
    }
    func testMalformedPageAndRevokedReadApprovalDoNotRestoreRejectedData() async throws {
        for revoked in [false, true] {
            let f = try Fixture(), permit = try await f.first()
            f.wire.response = (Data("{}".utf8), 200)
            if revoked { f.approval = nil }
            await f.browser.load(before: 100, action: try XCTUnwrap(permit.offer()))
            XCTAssertTrue(f.browser.rows.isEmpty); XCTAssertNil(f.browser.nextCursor)
            XCTAssertEqual(f.browser.phase, revoked ? .notEnabled : .failed)
            XCTAssertEqual(f.wire.requests.count, revoked ? 1 : 2)
        }
    }
    func testLateNetworkFailureCannotRestoreAnOldPageAfterFreshReload() async throws {
        let f = try Fixture(), old = try await f.first(); f.wire.pause = true
        let action = try XCTUnwrap(old.offer()), task = Task { await f.browser.load(before: 100, action: action) }
        await f.wire.wait(); f.browser.leaveList(old, closing: true)
        let fresh = try XCTUnwrap(f.browser.presentList()); f.wire.pause = false
        f.wire.response = (try WorkshopPurchasedTestData.envelope(WorkshopPurchasedTestData.page([])), 200)
        await f.browser.load(action: try XCTUnwrap(fresh.offer()))
        f.wire.releaseNetworkFailure(); await task.value
        XCTAssertEqual(f.browser.phase, .empty); XCTAssertTrue(f.browser.rows.isEmpty)
        XCTAssertNil(f.browser.nextCursor); XCTAssertNil(f.browser.issue)
    }
    func test503IsDeploymentDisabledAndNeverRestoresContinuation() async throws {
        let f = try Fixture(), permit = try await f.first()
        f.wire.response = (Data(), 503)
        await f.browser.load(before: 100, action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(f.browser.phase, .notEnabled); XCTAssertEqual(f.browser.issue, .disabled)
        XCTAssertTrue(f.browser.rows.isEmpty); XCTAssertNil(f.browser.nextCursor)
        XCTAssertEqual(f.wire.requests.count, 2)
    }
    func testInitialFailureRemainsInitialRetryNotFalseContinuation() async throws {
        let f = try Fixture(), permit = try XCTUnwrap(f.browser.presentList())
        f.wire.failNetwork = true
        await f.browser.load(action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(f.browser.phase, .failed); XCTAssertNil(f.browser.nextCursor)
        XCTAssertTrue(f.browser.rows.isEmpty); XCTAssertEqual(f.wire.requests.count, 1)
    }
}
