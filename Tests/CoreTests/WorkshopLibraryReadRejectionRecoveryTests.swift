import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Source-only tests of real read services and browser permits, never purchases or installs.
@MainActor final class WorkshopLibraryReadRejectionRecoveryTests: XCTestCase {
    final class Wire: HTTPTransport {
        var response: (Data, Int) = (Data(), 401)
        var requests = 0, pause = false, failNetwork = false
        var pending: CheckedContinuation<(Data, Int), Never>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests += 1
            if failNetwork { throw URLError(.timedOut) }
            if pause { return await withCheckedContinuation { pending = $0 } }
            return response
        }
        func wait() async {
            for _ in 0..<1000 { if pending != nil { return }; await Task.yield() }
            XCTFail("Expected synthetic suspended read")
        }
        func release401() { let old = pending; pending = nil; old?.resume(returning: (Data(), 401)) }
    }
    func owned(_ wire: Wire) throws -> (WorkshopOwnedBrowser, ContentDraftSessionLease) {
        let c = try WorkshopOwnedTestData.context()
        let lease = ContentDraftSessionLease(context: c, current: { c })
        let grant = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        let reader = WorkshopOwnedService(api: try APIConfiguration(baseURL: c.baseURL), transport: wire, lease: lease, approval: grant, currentApproval: { grant })
        return (WorkshopOwnedBrowser(reader: reader, lease: lease), lease)
    }
    func purchased(_ wire: Wire) throws -> (WorkshopPurchasedBrowser, ContentDraftSessionLease) {
        let c = try WorkshopOwnedTestData.context()
        let lease = ContentDraftSessionLease(context: c, current: { c })
        let grant = try WorkshopPurchasedReadApproval(context: c, expiresAt: .distantFuture)
        let reader = WorkshopPurchasedService(api: try APIConfiguration(baseURL: c.baseURL), transport: wire, lease: lease, approval: grant, currentApproval: { grant })
        return (WorkshopPurchasedBrowser(reader: reader, lease: lease), lease)
    }
    func testOwnedListCurrent401RevokesPermitWithoutDependingOnCallback() async throws {
        for response in [(Data(), 401), (Data("{\"code\":401}".utf8), 200)] {
            let wire = Wire(); wire.response = response
            let (browser, lease) = try owned(wire), permit = try XCTUnwrap(browser.presentList())
            await browser.load(action: try XCTUnwrap(permit.offer()))
            XCTAssertEqual(browser.phase, .invalidated); XCTAssertEqual(browser.issue, .unauthorized)
            XCTAssertFalse(lease.isCurrent); XCTAssertNil(permit.offer()); XCTAssertNil(browser.presentList())
            XCTAssertTrue(browser.rows.isEmpty); XCTAssertEqual(wire.requests, 1)
        }
    }
    func testOwnedDetail401ClearsListAndRejectsFurtherSelection() async throws {
        let wire = Wire(); wire.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        let (browser, lease) = try owned(wire), list = try XCTUnwrap(browser.presentList())
        await browser.load(action: try XCTUnwrap(list.offer()))
        let id = try XCTUnwrap(browser.rows.first?.claimId), detail = try XCTUnwrap(browser.presentDetail(claimId: id))
        wire.response = (Data(), 401)
        await browser.open(claimId: id, action: try XCTUnwrap(detail.offer()))
        XCTAssertEqual(browser.phase, .invalidated); XCTAssertTrue(browser.rows.isEmpty)
        XCTAssertEqual(browser.detailIssue, .unauthorized); XCTAssertNil(browser.detail)
        XCTAssertNil(detail.offer()); XCTAssertNil(list.offer()); XCTAssertNil(browser.presentDetail(claimId: id))
        XCTAssertFalse(lease.isCurrent)
    }
    func testPurchasedDetail401ClearsMetadataAndRetiresBothPermits() async throws {
        let wire = Wire(); wire.response = (try WorkshopPurchasedTestData.envelope(WorkshopPurchasedTestData.page()), 200)
        let (browser, lease) = try purchased(wire), list = try XCTUnwrap(browser.presentList())
        await browser.load(action: try XCTUnwrap(list.offer()))
        let id = try XCTUnwrap(browser.rows.first?.licenseId), detail = try XCTUnwrap(browser.presentDetail(licenseId: id))
        wire.response = (Data(), 401)
        await browser.open(licenseId: id, action: try XCTUnwrap(detail.offer()))
        XCTAssertEqual(browser.phase, .invalidated); XCTAssertEqual(browser.detailIssue, .unauthorized)
        XCTAssertTrue(browser.rows.isEmpty); XCTAssertNil(browser.detail); XCTAssertNil(browser.nextCursor)
        XCTAssertNil(list.offer()); XCTAssertNil(detail.offer()); XCTAssertFalse(lease.isCurrent)
    }
    func testPurchasedList401CannotIssueReplacementPresentation() async throws {
        let wire = Wire(), (browser, lease) = try purchased(wire), permit = try XCTUnwrap(browser.presentList())
        await browser.load(action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(browser.phase, .invalidated); XCTAssertEqual(browser.issue, .unauthorized)
        XCTAssertFalse(lease.isCurrent); XCTAssertNil(permit.offer()); XCTAssertNil(browser.presentList())
    }
    func testPackage401ClearsMetadataAndRejectsNewClaim() async throws {
        let c = try WorkshopOwnedTestData.context(), wire = Wire()
        let lease = ContentDraftSessionLease(context: c, current: { c })
        let grant = try WorkshopOwnedPackageReadApproval(context: c, expiresAt: .distantFuture)
        let reader = WorkshopOwnedPackageService(api: try APIConfiguration(baseURL: c.baseURL), transport: wire, lease: lease, approval: grant, currentApproval: { grant })
        let browser = WorkshopOwnedPackageBrowser(reader: reader, lease: lease)
        let permit = try XCTUnwrap(browser.present(claimId: "synthetic-claim"))
        wire.response = try WorkshopOwnedTestData.response(WorkshopPackageTestData.object())
        await browser.load(claimId: "synthetic-claim", action: try XCTUnwrap(permit.offer()))
        XCTAssertNotNil(browser.value)
        wire.response = (Data(), 401)
        await browser.load(claimId: "synthetic-claim", action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(browser.phase, .invalidated); XCTAssertEqual(browser.issue, .unauthorized)
        XCTAssertNil(browser.value); XCTAssertNil(permit.offer()); XCTAssertFalse(lease.isCurrent)
        XCTAssertNil(browser.present(claimId: "synthetic-claim"))
    }
    func testTransientOwnedAndPurchasedReadsRemainExplicitlyRetryable() async throws {
        let wire = Wire(); wire.failNetwork = true
        let (browser, lease) = try owned(wire), permit = try XCTUnwrap(browser.presentList())
        await browser.load(action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(browser.phase, .failed); XCTAssertTrue(lease.isCurrent)
        wire.failNetwork = false
        wire.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await browser.load(action: try XCTUnwrap(permit.offer()))
        XCTAssertEqual(browser.phase, .ready)
        let other = Wire(); other.failNetwork = true
        let (paid, paidLease) = try purchased(other), paidPermit = try XCTUnwrap(paid.presentList())
        await paid.load(action: try XCTUnwrap(paidPermit.offer()))
        XCTAssertEqual(paid.phase, .failed); XCTAssertTrue(paidLease.isCurrent)
        other.failNetwork = false
        other.response = (try WorkshopPurchasedTestData.envelope(WorkshopPurchasedTestData.page()), 200)
        await paid.load(action: try XCTUnwrap(paidPermit.offer()))
        XCTAssertEqual(paid.phase, .ready)
    }
    func testLate401CannotRetireNewOwnedPresentation() async throws {
        let wire = Wire(), (browser, lease) = try owned(wire), old = try XCTUnwrap(browser.presentList())
        wire.pause = true
        let action = try XCTUnwrap(old.offer()), task = Task { await browser.load(action: action) }
        await wire.wait(); browser.leaveList(old, closing: true)
        let fresh = try XCTUnwrap(browser.presentList()); wire.pause = false
        wire.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await browser.load(action: try XCTUnwrap(fresh.offer()))
        wire.release401(); await task.value
        XCTAssertEqual(browser.phase, .ready); XCTAssertTrue(lease.isCurrent)
        XCTAssertNotNil(fresh.offer()); XCTAssertEqual(wire.requests, 2)
    }
}
