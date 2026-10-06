import XCTest
@testable import Questify

private actor OwnedCouponCompositionHTTP: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ count: Int) async { while requests.count < count { await Task.yield() } }
    func finish(_ index: Int, status: Int = 200, name: String = "Owned terms") {
        let object: [String: Any] = ["code": 200, "data": [["id": 71, "couponId": 9, "useStatus": 0, "couponName": name, "couponDescription": "Current merchant terms", "endTime": "2026-10-30 16:00:00", "couponCode": "IGNORED-SECRET"]]]
        pending.removeValue(forKey: index)?.resume(returning: (try! JSONSerialization.data(withJSONObject: object), status))
    }
}
@MainActor private final class OwnedCouponCompositionHarness {
    let http = OwnedCouponCompositionHTTP()
    var session: AccountCollectionReadSession? = try! .init(accountID: 1, epoch: 1, token: "synthetic-owner")
    var unauthorized = 0
    lazy var reader = AccountCollectionSessionReader(service: AccountCollectionService(
        configuration: try! APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: http),
        currentSession: { [unowned self] in session }, onUnauthorized: { [unowned self] _ in unauthorized += 1 })
    func list(_ keyword: String? = nil) -> OwnedCouponReadRequest { .list(ownerScope: reader.scope, keyword: keyword) }
    func detail() -> OwnedCouponReadRequest { .detail(.init(historyID: 71, ownerScope: reader.scope)) }
}
@MainActor private final class WrongCouponCompositionReader: AccountCollectionReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true
    let isOfflineExample = true
    var requests = 0
    func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage { throw APIError.notConfigured }
    func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage { throw APIError.notConfigured }
    func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon] { throw APIError.notConfigured }
    func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon {
        requests += 1
        return try JSONDecoder().decode(AccountCollectionCoupon.self, from: Data(#"{"id":72,"useStatus":0}"#.utf8))
    }
}
@MainActor private struct OwnedCouponUnusedCodeService: CouponCodeServing {
    let enabled = false
    func issue(historyID: Int, session: CouponCodeSession) async throws -> CouponCodeReceipt { throw CouponCodeFailure.disabled }
    func status(historyID: Int, session: CouponCodeSession) async throws -> OrderCouponStatus { throw CouponCodeFailure.disabled }
    func image(_ receipt: CouponCodeReceipt) async throws -> Data { throw CouponCodeFailure.disabled }
}
@MainActor final class OwnedCouponCompositionTests: XCTestCase {
    func testAcceptedOwnerSelectionCannotRebindBeforeDeferredDetailConstruction() async throws {
        let h = OwnedCouponCompositionHarness(), list = OwnedCouponReadScreenModel(), request = h.list()
        let p = list.beginPresentation(for: request, foreground: true)
        let read = Task { await list.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); await h.http.finish(0); await read.value
        let selected = try XCTUnwrap(list.selections(for: request, filter: .all).first)
        h.session = try .init(accountID: 2, epoch: 2, token: "other-owner")
        let detail = OwnedCouponReadScreenModel(), detailRequest = OwnedCouponReadRequest.detail(selected)
        let fresh = detail.beginPresentation(for: detailRequest, foreground: true)
        await detail.refresh(request: detailRequest, reader: h.reader, presentation: fresh)
        XCTAssertNil(detail.issue(for: detailRequest)); XCTAssertNil(detail.detail(for: detailRequest))
        XCTAssertNotEqual(selected.ownerScope, h.reader.scope)
        let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testDetailReadsExactOwnedHistoryAndCurrentTermsWithoutCodeEndpoint() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); await h.http.finish(0); await read.value
        XCTAssertEqual(screen.detail(for: request)?.id, 71)
        XCTAssertEqual(screen.detail(for: request)?.description, "Current merchant terms")
        XCTAssertEqual(screen.detail(for: request)?.endTime, "2026-10-30 16:00:00")
        let requests = await h.http.requests
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/coupon/myrecvlist"])
        XCTAssertEqual(requests[0].httpMethod, "POST")
    }
    func testQueuedOfferAfterCloseHasZeroTransportRequests() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        let queued = try XCTUnwrap(screen.offerRead(request: h.detail(), reader: h.reader, presentation: p))
        screen.endPresentation(presentation: p); await queued()
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty); XCTAssertNil(screen.loadedRequest)
    }
    func testActualOwnedRetryTaskQueuedThenClosedHasZeroRequests() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        screen.schedule(request: h.detail(), reader: h.reader, presentation: p); screen.endPresentation(presentation: p)
        for _ in 0..<10 { await Task.yield() }
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testOldOfferCannotBorrowReopenOrCancelNewRead() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let old = screen.beginPresentation(for: request, foreground: true)
        let queued = try XCTUnwrap(screen.offerRead(request: request, reader: h.reader, presentation: old))
        screen.endPresentation(presentation: old); let fresh = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: fresh) }
        await h.http.waitFor(1); await queued()
        XCTAssertTrue(screen.isLoading)
        await h.http.finish(0); await read.value
        XCTAssertEqual(screen.detail(for: request)?.id, 71)
        let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testStaleForegroundAndPullRefreshCannotReviveClosedPresentation() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let old = screen.beginPresentation(for: request, foreground: true)
        screen.endPresentation(presentation: old); _ = screen.beginPresentation(for: request, foreground: true)
        screen.setForeground(true, request: request, reader: h.reader, presentation: old)
        await screen.refresh(request: request, reader: h.reader, presentation: old)
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testQueuedForegroundReadIsRevokedByBackground() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: false)
        screen.setForeground(true, request: request, reader: h.reader, presentation: p)
        screen.setForeground(false, request: request, reader: h.reader, presentation: p)
        for _ in 0..<10 { await Task.yield() }
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCloseDuringRealReaderSuppressesLate401BeforeSessionCallback() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); screen.endPresentation(presentation: p); await h.http.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(screen.detail(for: request)); XCTAssertNil(screen.issue(for: request))
    }
    func testNewerKeywordReadSuppressesOld401AndAcceptsOnlyNewRows() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), oldRequest = h.list("old"), newRequest = h.list("new")
        let p = screen.beginPresentation(for: oldRequest, foreground: true)
        let old = Task { await screen.refresh(request: oldRequest, reader: h.reader, presentation: p) }; await h.http.waitFor(1)
        let next = screen.beginPresentation(for: newRequest, foreground: true)
        let fresh = Task { await screen.refresh(request: newRequest, reader: h.reader, presentation: next) }; await h.http.waitFor(2)
        await h.http.finish(0, status: 401); await old.value
        XCTAssertTrue(screen.isLoading); XCTAssertEqual(h.unauthorized, 0)
        await h.http.finish(1, name: "New query"); await fresh.value
        XCTAssertEqual(screen.rows(for: newRequest)?.first?.name, "New query"); XCTAssertNil(screen.rows(for: oldRequest))
    }
    func testCurrentRealReader401StillCallsUnauthorizedAndShowsLogin() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); await h.http.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 1); XCTAssertEqual(screen.issue(for: request), .login)
    }
    func testPushedOwnerChangeHidesRowsAndRefusesRetainedDetailRead() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let p = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); await h.http.finish(0); await read.value
        h.session = try .init(accountID: 2, epoch: 2, token: "other-owner")
        XCTAssertNil(screen.detail(for: h.detail()))
        await screen.refresh(request: request, reader: h.reader, presentation: p)
        XCTAssertNil(screen.detail(for: h.detail())); let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testAcceptedRowsStayMountedWhilePushedDestinationOwnsNavigation() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.list()
        let p = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); await h.http.finish(0); await read.value
        screen.endPresentation(presentation: p)
        XCTAssertEqual(screen.rows(for: request)?.first?.id, 71)
        XCTAssertNil(screen.presentation); XCTAssertFalse(screen.isLoading)
    }
    func testWrongDetailIdentityNeverBecomesAccepted() async {
        let reader = WrongCouponCompositionReader(), screen = OwnedCouponReadScreenModel()
        let request = OwnedCouponReadRequest.detail(.init(historyID: 71, ownerScope: reader.scope))
        let p = screen.beginPresentation(for: request, foreground: true)
        await screen.refresh(request: request, reader: reader, presentation: p)
        XCTAssertNil(screen.detail(for: request)); XCTAssertEqual(screen.issue(for: request), .failure); XCTAssertEqual(reader.requests, 1)
    }
    func testConfigurationAndAuthenticationDenialsHaveNoReaderDispatch() async {
        let reader = WrongCouponCompositionReader(), screen = OwnedCouponReadScreenModel()
        let request = OwnedCouponReadRequest.detail(.init(historyID: 71, ownerScope: reader.scope))
        let p = screen.beginPresentation(for: request, foreground: true)
        reader.isConfigured = false; await screen.refresh(request: request, reader: reader, presentation: p)
        XCTAssertEqual(screen.issue(for: request), .notConfigured)
        reader.isConfigured = true; reader.isAuthenticated = false
        await screen.refresh(request: request, reader: reader, presentation: p)
        XCTAssertEqual(screen.issue(for: request), .login); XCTAssertEqual(reader.requests, 0)
    }
    func testRetainedCodeDestinationCannotInvokeFactoryAfterOwnerSwitch() async throws {
        let h = OwnedCouponCompositionHarness()
        let selected = OwnedCouponDetailSelection(historyID: 71, ownerScope: h.reader.scope)
        let destination = OwnedCouponCodeDestination(selection: selected)
        h.session = try .init(accountID: 2, epoch: 2, token: "other-owner")
        var calls = 0
        let model = destination.makeCoordinator(reader: h.reader) { id in
            calls += 1; return CouponCodeCoordinator(historyID: id, service: OwnedCouponUnusedCodeService(), currentSession: { nil })
        }
        XCTAssertNil(model); XCTAssertEqual(calls, 0)
        XCTAssertNotEqual(destination.id, OwnedCouponCodeDestination(selection: .init(historyID: 71, ownerScope: h.reader.scope)).id)
    }
    func testFreshCodeDestinationInvokesFactoryWithExactHistoryOnly() throws {
        let reader = WrongCouponCompositionReader(), selected = OwnedCouponDetailSelection(historyID: 71, ownerScope: reader.scope)
        var ids: [Int] = []
        let model = OwnedCouponCodeDestination(selection: selected).makeCoordinator(reader: reader) { id in
            ids.append(id); return CouponCodeCoordinator(historyID: id, service: OwnedCouponUnusedCodeService(), currentSession: { nil })
        }
        XCTAssertEqual(ids, [71]); XCTAssertEqual(model?.historyID, 71); XCTAssertFalse(try XCTUnwrap(model).enabled)
    }
    func testOldQueryRefreshCannotCancelNewPresentationRead() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel()
        let oldRequest = h.list("old"), newRequest = h.list("new")
        let old = screen.beginPresentation(for: oldRequest, foreground: true)
        let fresh = screen.beginPresentation(for: newRequest, foreground: true)
        let read = Task { await screen.refresh(request: newRequest, reader: h.reader, presentation: fresh) }
        await h.http.waitFor(1)
        await screen.refresh(request: oldRequest, reader: h.reader, presentation: old)
        screen.setForeground(true, request: oldRequest, reader: h.reader, presentation: old)
        XCTAssertTrue(screen.isLoading)
        await h.http.finish(0, name: "New query"); await read.value
        XCTAssertEqual(screen.rows(for: newRequest)?.first?.name, "New query")
        let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testLateCloseOfPriorPresentationCannotCancelNewRealListRead() async {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.list()
        let old = screen.beginPresentation(for: request, foreground: true)
        let fresh = screen.beginPresentation(for: request, foreground: true)
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: fresh) }
        await h.http.waitFor(1)
        XCTAssertFalse(screen.endPresentation(presentation: old)); XCTAssertTrue(fresh.isActive)
        XCTAssertTrue(screen.isLoading); XCTAssertTrue(screen.presentation === fresh)
        await h.http.finish(0, name: "Reopened list"); await read.value
        XCTAssertEqual(screen.rows(for: request)?.first?.name, "Reopened list")
        let requests = await h.http.requests; XCTAssertEqual(requests.count, 1)
    }
    func testLateCloseOfPriorViewCannotCancelReopenedRealDetailRead() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let oldView = OwnedCouponReadViewPresentation(), newView = OwnedCouponReadViewPresentation()
        _ = oldView.begin(model: screen, request: request, foreground: true)
        let fresh = try XCTUnwrap(newView.begin(model: screen, request: request, foreground: true))
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: fresh) }
        await h.http.waitFor(1)
        XCTAssertFalse(oldView.end(model: screen)); XCTAssertTrue(screen.isLoading)
        XCTAssertTrue(screen.presentation === fresh); XCTAssertNil(oldView.begin(model: screen, request: request, foreground: true))
        await h.http.finish(0); await read.value
        XCTAssertEqual(screen.detail(for: request)?.id, 71)
    }
    func testCurrentViewCloseBeforeFirstRedrawRevokesQueuedReadAndCannotBeReused() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let view = OwnedCouponReadViewPresentation()
        let capturedClose = { view.end(model: screen) } // Captured while permit is still nil.
        let p = try XCTUnwrap(view.begin(model: screen, request: request, foreground: true))
        let read = try XCTUnwrap(screen.offerRead(request: request, reader: h.reader, presentation: p))
        XCTAssertTrue(capturedClose()); XCTAssertFalse(capturedClose()); await read()
        XCTAssertNil(view.begin(model: screen, request: request, foreground: true)); XCTAssertNil(screen.presentation)
        let requests = await h.http.requests; XCTAssertTrue(requests.isEmpty)
    }
    func testCurrentViewCloseStillSuppressesPendingRealReader401AfterStaleClose() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), request = h.detail()
        let oldView = OwnedCouponReadViewPresentation(), newView = OwnedCouponReadViewPresentation()
        _ = oldView.begin(model: screen, request: request, foreground: true)
        let p = try XCTUnwrap(newView.begin(model: screen, request: request, foreground: true))
        let read = Task { await screen.refresh(request: request, reader: h.reader, presentation: p) }
        await h.http.waitFor(1); XCTAssertFalse(oldView.end(model: screen)); XCTAssertTrue(newView.end(model: screen))
        await h.http.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(screen.presentation); XCTAssertNil(screen.issue(for: request))
    }
    func testCurrentViewRequestReplacementRetainsItsCloseOwnership() async throws {
        let h = OwnedCouponCompositionHarness(), screen = OwnedCouponReadScreenModel(), view = OwnedCouponReadViewPresentation()
        let old = try XCTUnwrap(view.begin(model: screen, request: h.list("old"), foreground: true))
        let fresh = try XCTUnwrap(view.replace(model: screen, request: h.list("new"), foreground: true))
        XCTAssertFalse(old.isActive); XCTAssertTrue(fresh.isActive)
        XCTAssertFalse(screen.endPresentation(presentation: old)); XCTAssertTrue(view.end(model: screen))
        XCTAssertFalse(fresh.isActive); XCTAssertNil(screen.presentation)
    }
    func testCodeViewLateCloseKeepsNewConsentAndTasksButCurrentCloseCancelsOwnTask() async throws {
        let model = CouponCodeCoordinator(historyID: 71, service: OwnedCouponUnusedCodeService(), currentSession: { nil })
        let oldView = CouponCodeViewPresentation(), newView = CouponCodeViewPresentation()
        _ = oldView.begin(model: model)
        let fresh = try XCTUnwrap(newView.begin(model: model))
        let task = Task { for _ in 0..<10 { await Task.yield() } }
        newView.actionTask = task
        XCTAssertFalse(oldView.end(model: model)); XCTAssertFalse(task.isCancelled)
        XCTAssertTrue(model.presentation === fresh); XCTAssertNotNil(model.offerConfirmation(presentation: fresh))
        XCTAssertNil(oldView.begin(model: model))
        XCTAssertTrue(newView.end(model: model)); XCTAssertTrue(task.isCancelled)
        XCTAssertNil(model.presentation); await task.value
    }
    func testCodeViewCloseCapturedBeforeFirstRedrawClosesExactPermit() throws {
        let model = CouponCodeCoordinator(historyID: 71, service: OwnedCouponUnusedCodeService(), currentSession: { nil })
        let view = CouponCodeViewPresentation(), close = { (v: CouponCodeViewPresentation) in v.end(model: model) }
        let p = try XCTUnwrap(view.begin(model: model))
        XCTAssertTrue(close(view)); XCTAssertNil(model.offerConfirmation(presentation: p))
        XCTAssertNil(view.begin(model: model)); XCTAssertFalse(close(view)); XCTAssertNil(model.presentation)
    }
}
