import XCTest
@testable import Questify

@MainActor private final class DetailCompositionReader: NonCashRewardReading {
    var scope = UUID(), isConfigured = true, isAuthenticated = true
    var isOfflineExample: Bool { false }
    var requests: [NonCashRewardReference] = []
    var suspends = true
    var pending: CheckedContinuation<NonCashReward, Error>?
    let row: NonCashReward
    init(context: NonCashReward.Context = .map, instance: String = "season") {
        row = NonCashReward(awardId: "fixture", contextType: context, contextId: "context", releaseId: "release", instanceId: instance,
            rulesVersion: "rules", merchantId: "7", storeId: "8", rewardTitle: "Item", quantity: 1,
            validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200),
            redemptionConditions: "Original terms", state: .awarded, awardedAt: Date(timeIntervalSince1970: 100), asOf: Date(timeIntervalSince1970: 150))
    }
    func rewards(cursor: String?) async throws -> NonCashRewardPage { .init(items: [row], nextCursor: nil, asOf: row.asOf) }
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward {
        requests.append(reference)
        guard suspends else { return row }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async { while pending == nil { await Task.yield() } }
    func finish() { let continuation = pending; pending = nil; continuation?.resume(returning: row) }
    func fail() { let continuation = pending; pending = nil; continuation?.resume(throwing: APIError.unauthorized) }
    func destination() -> NonCashRewardDetailDestination { .init(selection: .init(reference: .init(row), ownerScope: scope)) }
}
private actor DetailCloseSuspendedTransport: HTTPTransport {
    private var requests: [URLRequest] = []
    private var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let index = requests.count; requests.append(request)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func waitFor(_ count: Int) async { while requests.count < count { await Task.yield() } }
    func count() -> Int { requests.count }
    func finish(_ index: Int, status: Int) {
        let body = #"{"code":200,"data":{"awardId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","contextType":"MAP","contextId":"map","releaseId":"release","instanceId":"season","rulesVersion":"rules","merchantId":"7","storeId":"8","rewardKind":"PHYSICAL","rewardTitle":"Item","redemptionConditions":"Store only","state":"AWARDED","quantity":1,"validFrom":100000,"validUntil":200000,"awardedAt":100000,"asOf":150000,"validityStatus":"IN_WINDOW","fulfillmentStatus":"UNVERIFIED"}}"#
        pending.removeValue(forKey: index)?.resume(returning: (Data(body.utf8), status))
    }
}
@MainActor private final class DetailCloseSessionHarness {
    var session: NonCashRewardReadSession? = try! .init(accountID: 7, epoch: 1, token: "synthetic")
    var unauthorized = 0
    let transport = DetailCloseSuspendedTransport()
    lazy var reader = NonCashRewardSessionReader(service: NonCashRewardService(
        configuration: try! APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport),
        currentSession: { [unowned self] in session }, onUnauthorized: { [unowned self] _ in unauthorized += 1 })
    func screen() -> NonCashRewardDetailScreenModel { .init(selection: .init(reference: .init(reward), ownerScope: reader.scope)) }
    var reward: NonCashReward {
        NonCashReward(awardId: String(repeating: "a", count: 64), contextType: .map, contextId: "map", releaseId: "release", instanceId: "season",
            rulesVersion: "rules", merchantId: "7", storeId: "8", rewardTitle: "Item", quantity: 1,
            validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200), redemptionConditions: "Store only",
            state: .awarded, awardedAt: Date(timeIntervalSince1970: 100), asOf: Date(timeIntervalSince1970: 150))
    }
}
@MainActor final class NonCashRewardDetailCompositionTests: XCTestCase {
    func testAcceptedRowSelectionRetainedBeforeDestinationConstructionCannotRebindAccount() async throws {
        let reader = DetailCompositionReader(), collection = NonCashRewardCollectionScreenModel(), scopeA = reader.scope
        await collection.refresh(reader: reader)
        let retained = try XCTUnwrap(collection.state.visibleSelections(scope: scopeA).first)
        reader.scope = UUID()
        let destination = NonCashRewardDetailDestination(selection: retained), screen = destination.makeScreenModel()
        screen.beginPresentation(); await screen.refresh(reader: reader, presentation: screen.presentation)
        XCTAssertEqual(destination.selection.ownerScope, scopeA); XCTAssertEqual(screen.state.selection, retained)
        XCTAssertTrue(reader.requests.isEmpty); XCTAssertNil(screen.value(scope: reader.scope))
    }
    func testDestinationIdentityUsesOwnerAndExactContextRatherThanOnlyAwardID() {
        let reader = DetailCompositionReader(), selected = reader.destination()
        reader.scope = UUID(); XCTAssertNotEqual(selected.id, reader.destination().id)
        let theme = DetailCompositionReader(context: .theme, instance: "run"); theme.scope = selected.selection.ownerScope
        XCTAssertNotEqual(selected.id, theme.destination().id)
        XCTAssertEqual(selected.makeScreenModel().state.selection, selected.selection)
    }
    func testScreenRequestsFreshDetailAndKeepsExactFrozenSource() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        screen.beginPresentation()
        XCTAssertNil(screen.value(scope: reader.scope))
        let task = Task { await screen.refresh(reader: reader, presentation: screen.presentation) }; await reader.waitForRequest()
        XCTAssertEqual(reader.requests, [.init(reader.row)]); XCTAssertNil(screen.value(scope: reader.scope))
        reader.finish(); await task.value
        XCTAssertEqual(screen.value(scope: reader.scope), reader.row)
        XCTAssertEqual(screen.projection(scope: reader.scope)?.origin.instanceId, "season")
        XCTAssertEqual(screen.projection(scope: reader.scope)?.qualification, .notProvided)
    }
    func testPushedScreenHidesOldScopeAndRefusesAnotherAccountRead() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel(), oldScope = reader.scope
        screen.beginPresentation()
        let task = Task { await screen.refresh(reader: reader, presentation: screen.presentation) }; await reader.waitForRequest(); reader.finish(); await task.value
        reader.scope = UUID(); XCTAssertNil(screen.value(scope: reader.scope)); await screen.refresh(reader: reader, presentation: screen.presentation)
        XCTAssertEqual(reader.requests.count, 1); XCTAssertNil(screen.value(scope: oldScope))
    }
    func testCloseInvalidatesPendingErrorAndNoSnapshotReturns() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        screen.beginPresentation()
        let task = Task { await screen.refresh(reader: reader, presentation: screen.presentation) }; await reader.waitForRequest()
        screen.endPresentation(presentation: screen.presentation); reader.fail(); await task.value
        XCTAssertNil(screen.value(scope: reader.scope)); XCTAssertNil(screen.issue(scope: reader.scope)); XCTAssertFalse(screen.isLoading)
    }
    func testChangedGrantsDisableDetailWithoutDispatch() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        screen.beginPresentation()
        reader.isConfigured = false; await screen.refresh(reader: reader, presentation: screen.presentation)
        XCTAssertEqual(screen.issue(scope: reader.scope), .notConfigured)
        reader.isConfigured = true; reader.isAuthenticated = false; await screen.refresh(reader: reader, presentation: screen.presentation)
        XCTAssertEqual(screen.issue(scope: reader.scope), .login); XCTAssertTrue(reader.requests.isEmpty)
    }
    func testOfferedRefreshQueuedBeforeCloseCannotDispatchWhenExecutedLater() async throws {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        reader.suspends = false; screen.beginPresentation()
        let queued = try XCTUnwrap(screen.offerRefresh(reader: reader, presentation: screen.presentation))
        screen.endPresentation(presentation: screen.presentation); await queued()
        XCTAssertTrue(reader.requests.isEmpty); XCTAssertNil(screen.loadedScope)
    }
    func testCloseThenReopenDoesNotReactivateOldOfferButNewOfferWorks() async throws {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        reader.suspends = false; screen.beginPresentation()
        let old = try XCTUnwrap(screen.offerRefresh(reader: reader, presentation: screen.presentation))
        screen.endPresentation(presentation: screen.presentation); screen.beginPresentation()
        let reopened = try XCTUnwrap(screen.offerRefresh(reader: reader, presentation: screen.presentation))
        await old(); XCTAssertTrue(reader.requests.isEmpty)
        await reopened(); XCTAssertEqual(reader.requests.count, 1)
        XCTAssertEqual(screen.value(scope: reader.scope), reader.row)
    }
    func testActualOwnedRetryTaskQueuedThenClosedDoesNotDispatch() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        reader.suspends = false; screen.beginPresentation()
        screen.scheduleRefresh(reader: reader, presentation: screen.presentation); screen.endPresentation(presentation: screen.presentation)
        // Tasks inherit MainActor; Close occurs before yielding to the queued body.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(reader.requests.isEmpty); XCTAssertNil(screen.loadedScope)
        await screen.refresh(reader: reader, presentation: screen.presentation)
        XCTAssertTrue(reader.requests.isEmpty)
    }
    func testForegroundQueuedRefreshCannotRunAfterCloseOrBackground() async throws {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        reader.suspends = false; screen.beginPresentation(foreground: false)
        XCTAssertNil(screen.offerRefresh(reader: reader, presentation: screen.presentation))
        screen.setForeground(true, reader: reader, presentation: screen.presentation); screen.endPresentation(presentation: screen.presentation)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertTrue(reader.requests.isEmpty)
        screen.beginPresentation(); let queued = try XCTUnwrap(screen.offerRefresh(reader: reader, presentation: screen.presentation))
        screen.setForeground(false, reader: reader, presentation: screen.presentation); await queued()
        XCTAssertTrue(reader.requests.isEmpty)
    }

    func testOldDeferredPullRefreshCannotBorrowReopenedPresentation() async {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        reader.suspends = false
        let oldPresentation = screen.beginPresentation()
        screen.endPresentation(presentation: screen.presentation)
        let reopened = screen.beginPresentation()
        // This is the body of a previously offered SwiftUI async refresh closure.
        await screen.refresh(reader: reader, presentation: oldPresentation)
        XCTAssertTrue(reader.requests.isEmpty)
        await screen.refresh(reader: reader, presentation: reopened)
        XCTAssertEqual(reader.requests.count, 1); XCTAssertEqual(screen.value(scope: reader.scope), reader.row)
    }

    func testLateOldCloseCannotCancelReopenedScreenReadThroughRealReader() async throws {
        let h = DetailCloseSessionHarness(), screen = h.screen()
        let old = screen.beginPresentation(), fresh = screen.beginPresentation()
        let read = Task { await screen.refresh(reader: h.reader, presentation: fresh) }; await h.transport.waitFor(1)
        XCTAssertFalse(screen.endPresentation(presentation: old)); XCTAssertTrue(screen.isLoading)
        XCTAssertTrue(fresh.isActive); XCTAssertTrue(screen.presentation === fresh)
        await h.transport.finish(0, status: 200); await read.value
        XCTAssertEqual(screen.value(scope: h.reader.scope), h.reward)
        let count = await h.transport.count(); XCTAssertEqual(count, 1)
    }
    func testLateOldViewCloseKeepsNewOfferAndCurrentCloseRevokesItBeforeRealDispatch() async throws {
        let h = DetailCloseSessionHarness(), screen = h.screen()
        let oldView = NonCashRewardDetailViewPresentation(), newView = NonCashRewardDetailViewPresentation()
        _ = oldView.begin(model: screen, foreground: true)
        let fresh = try XCTUnwrap(newView.begin(model: screen, foreground: true))
        let offered = try XCTUnwrap(screen.offerRefresh(reader: h.reader, presentation: fresh))
        XCTAssertFalse(oldView.end(model: screen)); XCTAssertTrue(fresh.isActive)
        XCTAssertTrue(newView.end(model: screen)); await offered()
        let count = await h.transport.count(); XCTAssertEqual(count, 0)
        XCTAssertNil(screen.presentation); XCTAssertNil(screen.loadedScope)
    }
    func testCloseCapturedBeforeOnAppearStillClosesPermitBeforeFirstRedraw() async throws {
        let h = DetailCloseSessionHarness(), screen = h.screen(), view = NonCashRewardDetailViewPresentation()
        let capturedClose = { view.end(model: screen) }
        let p = try XCTUnwrap(view.begin(model: screen, foreground: true))
        let offered = try XCTUnwrap(screen.offerRefresh(reader: h.reader, presentation: p))
        XCTAssertTrue(capturedClose()); await offered(); XCTAssertFalse(capturedClose())
        XCTAssertNil(view.begin(model: screen, foreground: true)); XCTAssertNil(screen.presentation)
        let count = await h.transport.count(); XCTAssertEqual(count, 0)
    }
    func testCurrentViewCloseAfterStaleCloseSuppressesLateReal401() async throws {
        let h = DetailCloseSessionHarness(), screen = h.screen()
        let oldView = NonCashRewardDetailViewPresentation(), newView = NonCashRewardDetailViewPresentation()
        _ = oldView.begin(model: screen, foreground: true)
        let fresh = try XCTUnwrap(newView.begin(model: screen, foreground: true))
        let read = Task { await screen.refresh(reader: h.reader, presentation: fresh) }; await h.transport.waitFor(1)
        XCTAssertFalse(oldView.end(model: screen)); XCTAssertTrue(newView.end(model: screen))
        await h.transport.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 0); XCTAssertNil(screen.value(scope: h.reader.scope)); XCTAssertNil(screen.issue(scope: h.reader.scope))
    }
    func testStaleCloseDoesNotSuppressCurrentReal401() async {
        let h = DetailCloseSessionHarness(), screen = h.screen()
        let old = screen.beginPresentation(), fresh = screen.beginPresentation()
        let read = Task { await screen.refresh(reader: h.reader, presentation: fresh) }; await h.transport.waitFor(1)
        XCTAssertFalse(screen.endPresentation(presentation: old))
        await h.transport.finish(0, status: 401); await read.value
        XCTAssertEqual(h.unauthorized, 1); XCTAssertEqual(screen.issue(scope: h.reader.scope), .login)
    }
    func testNilOrAlreadyClosedViewCannotCloseReopenedScreen() throws {
        let reader = DetailCompositionReader(), screen = reader.destination().makeScreenModel()
        let oldView = NonCashRewardDetailViewPresentation(), newView = NonCashRewardDetailViewPresentation()
        _ = oldView.begin(model: screen, foreground: true); XCTAssertTrue(oldView.end(model: screen))
        let fresh = try XCTUnwrap(newView.begin(model: screen, foreground: true))
        XCTAssertFalse(oldView.end(model: screen)); XCTAssertNil(oldView.begin(model: screen, foreground: true))
        XCTAssertFalse(screen.endPresentation(presentation: nil)); XCTAssertTrue(fresh.isActive)
        XCTAssertTrue(screen.presentation === fresh)
    }
}
