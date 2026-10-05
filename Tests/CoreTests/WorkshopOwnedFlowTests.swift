import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Real service/browser with a transport that deliberately ignores cancellation.
@MainActor final class WorkshopOwnedFlowTests: XCTestCase {
    private final class State {
        var current: RuntimeDependencyContext?
        var approval: WorkshopOwnedReadApproval?
        var unauthorized = 0
    }
    private final class Transport: HTTPTransport {
        var paused = false
        var requests: [URLRequest] = []
        var pending: [CheckedContinuation<(Data, Int), Error>] = []
        var response: (Data, Int) = try! WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if paused { return try await withCheckedThrowingContinuation { pending.append($0) } }
            return response
        }
        func release(_ result: (Data, Int)) throws {
            let first = try XCTUnwrap(pending.first); pending.removeFirst(); first.resume(returning: result)
        }
    }
    private struct Harness { let browser: WorkshopOwnedBrowser; let service: WorkshopOwnedService; let transport: Transport; let state: State; let listPermit: WorkshopOwnedPresentationPermit }
    private func harness(approved: Bool = true) throws -> Harness {
        let c = try WorkshopOwnedTestData.context(), t = Transport(), state = State()
        let approval = try WorkshopOwnedReadApproval(context: c, expiresAt: .distantFuture)
        state.current = c; state.approval = approved ? approval : nil
        let lease = ContentDraftSessionLease(context: c, current: { state.current })
        let service = WorkshopOwnedService(api: try APIConfiguration(baseURL: c.baseURL), transport: t, lease: lease,
            approval: state.approval, currentApproval: { state.approval }, onUnauthorized: { _ in state.unauthorized += 1 })
        let browser = WorkshopOwnedBrowser(reader: service, lease: lease)
        return .init(browser: browser, service: service, transport: t, state: state, listPermit: try XCTUnwrap(browser.presentList()))
    }
    private var unauthorized: (Data, Int) { (Data("{\"code\":401}".utf8), 200) }
    private func wait(_ ready: () -> Bool) async throws {
        for _ in 0..<100 { if ready() { return }; await Task.yield() }
        XCTAssertTrue(ready()); if !ready() { throw WorkshopOwnedIssue.unavailable }
    }
    func testDefaultOffDoesNotDispatch() async throws {
        let h = try harness(approved: false); await h.browser.load(action: h.listPermit.offer()!)
        XCTAssertEqual(h.browser.phase, .notEnabled); XCTAssertTrue(h.transport.requests.isEmpty)
    }
    func testVerticalListDetailAndExactKnownLengthForms() async throws {
        let h = try harness(); await h.browser.load(action: h.listPermit.offer()!); XCTAssertEqual(h.browser.phase, .ready)
        XCTAssertNil(h.browser.presentDetail(claimId: "not-listed")); XCTAssertEqual(h.transport.requests.count, 1)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail())
        let detailPermit = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        await h.browser.open(claimId: "synthetic-claim", action: detailPermit.offer()!); XCTAssertEqual(h.browser.detail?.item?.id, "synthetic-claim")
        XCTAssertEqual(h.transport.requests.map { $0.url?.path }, ["/native/api/workshop/owned/list", "/native/api/workshop/owned/detail"])
        XCTAssertEqual(h.transport.requests.map(\.httpBody), [Data(), Data("claim_id=synthetic-claim".utf8)])
        for r in h.transport.requests {
            XCTAssertEqual(r.httpMethod, "POST"); XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Length"), String(r.httpBody!.count))
            XCTAssertEqual(r.value(forHTTPHeaderField: "Cache-Control"), "no-store"); XCTAssertNil(r.url?.query)
        }
    }
    func testEmptyUnavailable404AndRefreshFailureStayDistinct() async throws {
        let h = try harness()
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page(items: [])); await h.browser.load(action: h.listPermit.offer()!); XCTAssertEqual(h.browser.phase, .empty)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page(items: [], enabled: false)); await h.browser.load(action: h.listPermit.offer()!); XCTAssertEqual(h.browser.phase, .notEnabled)
        h.transport.response = (Data(), 404); await h.browser.load(action: h.listPermit.offer()!); XCTAssertEqual(h.browser.phase, .notEnabled)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page()); await h.browser.load(action: h.listPermit.offer()!)
        h.transport.response = (Data(), 500); await h.browser.load(action: h.listPermit.offer()!); XCTAssertEqual(h.browser.phase, .failed); XCTAssertTrue(h.browser.rows.isEmpty)
    }
    func testCloseListSuppressesDelayed401() async throws {
        let h = try harness(); h.transport.paused = true
        let read = Task { [action = h.listPermit.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
        h.browser.closeList(); try h.transport.release(unauthorized); await read.value
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.browser.phase, .idle)
    }
    func testCloseReopenKeepsNewReadWhileOld401IsIgnored() async throws {
        let h = try harness(); h.transport.paused = true
        let old = Task { [action = h.listPermit.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
        h.browser.closeList(); let reopened = try XCTUnwrap(h.browser.presentList()); let current = Task { [action = reopened.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 2 }
        try h.transport.release(unauthorized); await old.value; XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.browser.phase, .loading)
        try h.transport.release(WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())); await current.value; XCTAssertEqual(h.browser.phase, .ready)
    }
    func testCloseDetailSuppressesDelayed401() async throws {
        let h = try harness(); await h.browser.load(action: h.listPermit.offer()!); h.transport.paused = true
        let detailPermit = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        let read = Task { [action = detailPermit.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
        h.browser.closeDetail(); try h.transport.release(unauthorized); await read.value
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.detail); XCTAssertFalse(h.browser.detailLoading)
    }
    func testNewDetailRetiresOld401BeforeSideEffect() async throws {
        let h = try harness(); await h.browser.load(action: h.listPermit.offer()!); h.transport.paused = true
        let detailPermit = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        let old = Task { [action = detailPermit.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
        let current = Task { [action = detailPermit.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 2 }
        try h.transport.release(unauthorized); await old.value; XCTAssertEqual(h.state.unauthorized, 0); XCTAssertTrue(h.browser.detailLoading)
        try h.transport.release(WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail())); await current.value; XCTAssertNotNil(h.browser.detail)
    }
    func testRefreshRetiresInFlightDetail() async throws {
        let h = try harness(); await h.browser.load(action: h.listPermit.offer()!); h.transport.paused = true
        let detailPermit = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        let read = Task { [action = detailPermit.offer()!] in await h.browser.open(claimId: "synthetic-claim", action: action) }; try await wait { h.transport.pending.count == 1 }
        h.transport.paused = false; await h.browser.load(action: h.listPermit.offer()!); try h.transport.release(unauthorized); await read.value
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.detail)
    }
    func testCancelledListAndDetailIgnoreLate401() async throws {
        for detail in [false, true] {
            let h = try harness(); if detail { await h.browser.load(action: h.listPermit.offer()!) }; h.transport.paused = true
            let detailPermit = detail ? try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim")) : h.listPermit
            let read = Task { [action = (detail ? detailPermit : h.listPermit).offer()!] in if detail { await h.browser.open(claimId: "synthetic-claim", action: action) } else { await h.browser.load(action: action) } }
            try await wait { h.transport.pending.count == 1 }; read.cancel(); try h.transport.release(unauthorized); await read.value
            XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.detail); XCTAssertFalse(h.browser.detailLoading)
        }
    }
    func testCurrent401StillNotifies() async throws {
        for detail in [false, true] {
            let h = try harness(); if detail { await h.browser.load(action: h.listPermit.offer()!) }; h.transport.response = unauthorized
            let detailPermit = detail ? try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim")) : h.listPermit
            if detail { await h.browser.open(claimId: "synthetic-claim", action: detailPermit.offer()!) } else { await h.browser.load(action: h.listPermit.offer()!) }
            XCTAssertEqual(h.state.unauthorized, 1)
        }
    }
    func testSessionOrApprovalChangeSuppressesLate401() async throws {
        for sessionChange in [false, true] {
            let h = try harness(); h.transport.paused = true
            let read = Task { [action = h.listPermit.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
            if sessionChange { h.state.current = try WorkshopOwnedTestData.context(account: 8) } else { h.state.approval = nil }
            try h.transport.release(unauthorized); await read.value; XCTAssertEqual(h.state.unauthorized, 0); XCTAssertTrue(h.browser.rows.isEmpty)
        }
    }
    func testInvalidationAndConcurrentLoadsCannotDispatchAgain() async throws {
        let h = try harness(); h.transport.paused = true
        let action = try XCTUnwrap(h.listPermit.offer())
        let read = Task { await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
        await h.browser.load(action: action); XCTAssertEqual(h.transport.requests.count, 1)
        h.browser.invalidate(); try h.transport.release(unauthorized); await read.value; await h.browser.load(action: action)
        XCTAssertEqual(h.transport.requests.count, 1); XCTAssertEqual(h.browser.phase, .invalidated)
    }
    func testHostInvalidatesBeforeRoleTokenEpochAndRealmReplacement() async throws {
        let variants = [try WorkshopOwnedTestData.context(role: "merchant"), try WorkshopOwnedTestData.context(token: "replacement"),
                        try WorkshopOwnedTestData.context(epoch: 2), try WorkshopOwnedTestData.context(realm: "other-realm")]
        for variant in variants {
            let h = try harness(); h.transport.paused = true
            let read = Task { [action = h.listPermit.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
            h.browser.invalidate(); h.state.current = variant
            try h.transport.release(unauthorized); await read.value
            XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.browser.phase, .invalidated)
        }
    }
    func testInvalidationFencesIntermediateAccountABA() async throws {
        let h = try harness(); h.transport.paused = true; let original = h.state.current
        let read = Task { [action = h.listPermit.offer()!] in await h.browser.load(action: action) }; try await wait { h.transport.pending.count == 1 }
        h.browser.invalidate(); h.state.current = try WorkshopOwnedTestData.context(account: 8); h.state.current = original
        try h.transport.release(unauthorized); await read.value; XCTAssertNil(h.listPermit.offer())
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertEqual(h.transport.requests.count, 1)
    }
    func testWrongDetailAndDuplicateEnvelopeAreRejected() async throws {
        let h = try harness(); await h.browser.load(action: h.listPermit.offer()!)
        h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.detail(item: WorkshopOwnedTestData.item("wrong")))
        let detailPermit = try XCTUnwrap(h.browser.presentDetail(claimId: "synthetic-claim"))
        await h.browser.open(claimId: "synthetic-claim", action: detailPermit.offer()!); XCTAssertEqual(h.browser.detailIssue, .malformed)
        h.transport.response = (Data("{\"code\":200,\"code\":401}".utf8), 200); await h.browser.load(action: h.listPermit.offer()!)
        XCTAssertEqual(h.browser.issue, .malformed); XCTAssertEqual(h.state.unauthorized, 0)
    }
    func testNewOfferSuppressesInFlight401BeforeNewReadStarts() async throws {
        let h = try harness(); h.transport.paused = true
        let old = try XCTUnwrap(h.listPermit.offer()), read = Task { await h.browser.load(action: old) }
        try await wait { h.transport.pending.count == 1 }
        let newer = try XCTUnwrap(h.listPermit.offer())
        try h.transport.release(unauthorized); await read.value
        XCTAssertEqual(h.state.unauthorized, 0); XCTAssertNil(h.browser.issue)
        h.transport.paused = false; h.transport.response = try WorkshopOwnedTestData.response(WorkshopOwnedTestData.page())
        await h.browser.load(action: newer); XCTAssertEqual(h.browser.phase, .ready)
    }
}
