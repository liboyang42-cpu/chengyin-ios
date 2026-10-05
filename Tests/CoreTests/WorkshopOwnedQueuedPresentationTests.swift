import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// A MainActor Task cannot enter the browser until the test yields. Closing/reopening before that
/// yield reproduces a queued toolbar/retry action, not merely a suspended in-flight response.
@MainActor final class WorkshopOwnedQueuedPresentationTests: XCTestCase {
    private final class State { var unauthorized = 0; var context: RuntimeDependencyContext? }
    private final class Transport: HTTPTransport {
        var calls = 0
        var response: (Data, Int) = (Data("{\"code\":401}".utf8), 200)
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; return response }
    }
    private struct Harness { let browser: WorkshopOwnedBrowser; let package: WorkshopOwnedPackageBrowser; let transport: Transport; let state: State }
    private func harness() throws -> Harness {
        let c = try WorkshopOwnedTestData.context(), state = State(), transport = Transport(); state.context = c
        let lease = ContentDraftSessionLease(context: c, current: { state.context })
        let approval = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        let packageApproval = try WorkshopOwnedPackageReadApproval(context: c, expiresAt: .distantFuture)
        let api = try APIConfiguration(baseURL: c.baseURL)
        let package = WorkshopOwnedPackageBrowser(reader: WorkshopOwnedPackageService(api: api, transport: transport, lease: lease, approval: packageApproval, currentApproval: { packageApproval }, onUnauthorized: { _ in state.unauthorized += 1 }), lease: lease)
        let browser = WorkshopOwnedBrowser(reader: WorkshopOwnedService(api: api, transport: transport, lease: lease, approval: approval, currentApproval: { approval }, onUnauthorized: { _ in state.unauthorized += 1 }), lease: lease, packageBrowser: package)
        return .init(browser: browser, package: package, transport: transport, state: state)
    }
    private func readyList(_ h: Harness) async throws -> WorkshopOwnedPresentationPermit {
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        let p = try XCTUnwrap(h.browser.presentList()); await h.browser.load(action: p.offer()!); return p
    }
    func testQueuedListAfterBackCannotCreateRequestOrUnauthorizedSideEffect() async throws {
        let h = try harness(), p = try XCTUnwrap(h.browser.presentList())
        let queued = Task { [action = p.offer()!] in await h.browser.load(action: action) }
        h.browser.closeList(); await queued.value
        XCTAssertEqual(h.transport.calls, 0); XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.browser.phase, .idle)
    }
    func testQueuedListCannotBorrowReopenedPresentation() async throws {
        let h = try harness(), old = try XCTUnwrap(h.browser.presentList())
        let queued = Task { [action = old.offer()!] in await h.browser.load(action: action) }
        h.browser.closeList(); let fresh = try XCTUnwrap(h.browser.presentList())
        await queued.value; XCTAssertEqual(h.transport.calls, 0)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await h.browser.load(action: fresh.offer()!); XCTAssertEqual(h.transport.calls, 1); XCTAssertEqual(h.browser.phase, .ready)
    }
    func testListPushRetiresQueuedActionButRetainsSelectedRowsForDetail() async throws {
        let h = try harness(), p = try await readyList(h)
        let queued = Task { [action = p.offer()!] in await h.browser.load(action: action) }
        h.browser.leaveList(p, closing: false)
        XCTAssertEqual(h.browser.phase, .ready); XCTAssertEqual(h.browser.rows.count, 1)
        let detail = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        await queued.value; XCTAssertEqual(h.transport.calls, 1)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail())
        await h.browser.open(claimId: "synthetic-claim", action: detail.offer()!); XCTAssertNotNil(h.browser.detail)
    }
    func testQueuedDetailAfterBackAndReopenCannotDispatchOrReplaceSelection() async throws {
        let h = try harness(); _ = try await readyList(h)
        let old = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        let queued = Task { [action = old.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }
        h.browser.closeDetail(); let fresh = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        h.transport.response = (Data("{\"code\":401}".utf8), 200); await queued.value
        XCTAssertEqual(h.transport.calls, 1); XCTAssertEqual(h.state.unauthorized, 0)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail())
        await h.browser.open(claimId: "synthetic-claim", action: fresh.offer()!); XCTAssertNotNil(h.browser.detail)
    }
    func testDetailPushRetiresQueuedRetryWithoutClearingParentMetadata() async throws {
        let h = try harness(); _ = try await readyList(h)
        let p = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail())
        await h.browser.open(claimId: "synthetic-claim", action: p.offer()!)
        let queued = Task { [action = p.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }
        h.browser.leaveDetail(p, closing: false); XCTAssertNotNil(h.browser.detail)
        _ = try XCTUnwrap(h.package.present(claimId: "synthetic-claim"))
        await queued.value; XCTAssertEqual(h.transport.calls, 2); XCTAssertEqual(h.state.unauthorized, 0)
    }
    func testQueuedPackageAfterBackCannotBorrowNewPresentation() async throws {
        let h = try harness(), old = try XCTUnwrap(h.package.present(claimId: "synthetic-claim"))
        let queued = Task { [action = old.offer()!] in await h.package.load(claimId: "synthetic-claim", action: action) }
        h.package.close(); let fresh = try XCTUnwrap(h.package.present(claimId: "synthetic-claim"))
        await queued.value; XCTAssertEqual(h.transport.calls, 0); XCTAssertEqual(h.state.unauthorized, 0)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopPackageTestData.object())
        await h.package.load(claimId: "synthetic-claim", action: fresh.offer()!); XCTAssertEqual(h.package.phase, .ready)
    }
    func testQueuedPackageCannotChangeNewClaimSelection() async throws {
        let h = try harness(), old = try XCTUnwrap(h.package.present(claimId: "synthetic-claim"))
        let queued = Task { [action = old.offer()!] in await h.package.load(claimId: "synthetic-claim", action: action) }
        let fresh = try XCTUnwrap(h.package.present(claimId: "other-claim")); await queued.value
        XCTAssertEqual(h.transport.calls, 0)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopPackageTestData.object(id: "other-claim"))
        await h.package.load(claimId: "other-claim", action: fresh.offer()!); XCTAssertEqual(h.package.value?.claimId, "other-claim")
    }
    func testQueuedActionAfterIdentityABAAndInvalidationCannotReissuePermit() async throws {
        let h = try harness(), old = try XCTUnwrap(h.browser.presentList()), context = h.state.context
        let queued = Task { [action = old.offer()!] in await h.browser.load(action: action) }
        h.browser.invalidate(); h.state.context = try WorkshopOwnedTestData.context(account: 8); h.state.context = context
        XCTAssertNil(h.browser.presentList()); await queued.value
        XCTAssertEqual(h.transport.calls, 0); XCTAssertEqual(h.state.unauthorized, 0)
    }
    func testValidCurrentPresentation401StillNotifies() async throws {
        let h = try harness(), p = try XCTUnwrap(h.browser.presentList())
        await h.browser.load(action: p.offer()!); XCTAssertEqual(h.transport.calls, 1); XCTAssertEqual(h.state.unauthorized, 1)
    }
    func testStaleDisappearanceDoesNotCloseNewerPresentation() async throws {
        let h = try harness(), old = try XCTUnwrap(h.browser.presentList()), fresh = try XCTUnwrap(h.browser.presentList())
        h.browser.leaveList(old, closing: true)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await h.browser.load(action: fresh.offer()!); XCTAssertEqual(h.browser.phase, .ready)
    }
    func testNewOfferBeforeQueuedEntryRetiresOlderActionWithinSamePresentation() async throws {
        let h = try harness(), p = try XCTUnwrap(h.browser.presentList()), old = try XCTUnwrap(p.offer())
        let queued = Task { await h.browser.load(action: old) }
        let newer = try XCTUnwrap(p.offer())
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await h.browser.load(action: newer); await queued.value
        XCTAssertEqual(h.transport.calls, 1); XCTAssertEqual(h.browser.phase, .ready); XCTAssertEqual(h.state.unauthorized, 0)
        await h.browser.load(action: old); XCTAssertEqual(h.transport.calls, 1)
    }
    func testParentCloseRetiresQueuedPackageAction() async throws {
        let h = try harness(), p = try XCTUnwrap(h.package.present(claimId: "synthetic-claim")), action = try XCTUnwrap(p.offer())
        let queued = Task { await h.package.load(claimId: "synthetic-claim", action: action) }
        h.browser.closeList(); await queued.value
        XCTAssertEqual(h.transport.calls, 0); XCTAssertEqual(h.state.unauthorized, 0)
    }
}
