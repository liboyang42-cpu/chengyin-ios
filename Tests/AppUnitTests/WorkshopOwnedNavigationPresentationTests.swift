import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class WorkshopOwnedNavigationPresentationTests: XCTestCase {
    private final class Recorder: HTTPTransport {
        var paths: [String] = []
        var unauthorized = false
        var hold = false
        var waiting: [CheckedContinuation<Void, Never>] = []
        func releaseAll() { let pending = waiting; waiting = []; for item in pending { item.resume() } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = request.url!.path; paths.append(path)
            if hold { await withCheckedContinuation { waiting.append($0) } }
            if unauthorized { return (Data("{\"code\":401}".utf8), 200) }
            let item: [String: Any] = ["claimId":"synthetic-claim","acquisition":"FREE","buyerKind":"INDIVIDUAL","acquiredAt":"2026-10-01T00:00:00Z","validUntil":"2026-11-01T00:00:00Z","storedStatus":"ACTIVE","status":"ACTIVE","publicationStatus":"LISTED"]
            var payload: [String: Any] = ["schema":"workshop-owned-v1","scope":"FREE_INDIVIDUAL_ONLY","availability":"FREE_CLAIMS_ONLY","purchasedLibraryStatus":"NOT_AVAILABLE","contentUseStatus":"UNAVAILABLE","checkedAt":"2026-10-05T00:00:00Z"]
            if path.hasSuffix("/list") { payload["items"] = [item]; payload["hasMore"] = false }
            else if path.hasSuffix("/detail") { payload["item"] = item }
            else {
                payload = ["schema":"workshop-package-v1","scope":"FREE_INDIVIDUAL_ONLY","availability":"UNAVAILABLE","purchasedLibraryStatus":"NOT_AVAILABLE","contentUseStatus":"UNAVAILABLE","checkedAt":"2026-10-05T00:00:00Z","claimId":"synthetic-claim","manifestStatus":"NOT_AVAILABLE","editorStatus":"POST_INSTALL_POLICY_UNAVAILABLE","packageInfo":NSNull()]
            }
            return (try JSONSerialization.data(withJSONObject: ["code":200,"data":payload]), 200)
        }
    }
    private final class State { var unauthorized = 0 }
    private struct Fixture { let browser: WorkshopOwnedBrowser; let navigation: WorkshopOwnedNavigationState; let recorder: Recorder; let state: State }
    private func fixture() throws -> Fixture {
        let c = RuntimeDependencyContext(market: .china, baseURL: URL(string:"https://workshop-read.example/native")!, role:"player", session: try .init(accountID:42,epoch:1,namespace:"synthetic",token:"synthetic"))
        let recorder = Recorder(), state = State(), approval = try WorkshopOwnedReadApproval(context:c,expiresAt:.distantFuture)
        let packageApproval = try WorkshopOwnedPackageReadApproval(context:c,expiresAt:.distantFuture)
        let browser = try XCTUnwrap(WorkshopOwnedComposition.makeBrowser(context:c,api:try APIConfiguration(baseURL:c.baseURL),transport:recorder,approval:approval,currentApproval:{approval},current:{c},packageApproval:packageApproval,currentPackageApproval:{packageApproval},onUnauthorized:{_ in state.unauthorized += 1}))
        return .init(browser:browser,navigation:.init(browser:browser),recorder:recorder,state:state)
    }
    private func wait(_ stage: String = "condition", file: StaticString = #filePath, line: UInt = #line, diagnostics: () -> String = { "" }, _ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), stage + " " + diagnostics(), file: file, line: line); if !condition() { throw WorkshopOwnedIssue.unavailable }
    }
    /// Actual SwiftUI NavigationStack appearance/disappearance and destination binding, not only
    /// direct browser calls. Button handlers use these exact navigation-state actions in production.
    func testHostedListDetailPackageBackAndReopenIssueFreshPermits() async throws {
        let f = try fixture()
#if DEBUG
        f.navigation.syntheticTrace = { snapshot in
            print("WORKSHOP_SYNTHETIC_OWNED event=\(snapshot.event.rawValue) current=\(snapshot.currentAppearance) appeared=\(snapshot.displayedAppeared) closed=\(snapshot.displayedClosed) currentAppeared=\(snapshot.currentAppeared) currentClosed=\(snapshot.currentClosed) eligible=\(snapshot.eligible) live=\(snapshot.displayedLive) list=\(snapshot.list) detail=\(snapshot.detail) package=\(snapshot.package) selected=\(snapshot.selected) showsPackage=\(snapshot.showsPackage)")
        }
#endif
        // This one sealed-fixture method emits at most twelve fixed stages. No IDs,
        // routes, credentials, response bodies or user-visible content are printed.
        var stageCount = 0
        func stage(_ name: String) {
            guard stageCount < 12 else { return }; stageCount += 1
            print("WORKSHOP_HOST_STAGE \(name) list=\(f.navigation.listPermit != nil) detail=\(f.navigation.detailPermit != nil) package=\(f.navigation.packagePermit != nil) selected=\(f.navigation.selection != nil) showsPackage=\(f.navigation.showsPackage)")
        }
        stage("before-window")
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser:f.browser,navigation:f.navigation) })
        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        stage("window-visible")
        try await wait("initial list ready") { f.browser.phase == .ready && f.navigation.listPermit != nil }
        XCTAssertTrue(host.view.window === window)
        XCTAssertEqual(window.windowScene?.activationState, .foregroundActive)
        stage("list-ready")
        let listPermit = try XCTUnwrap(f.navigation.listPermit)
        let firstListBox = f.navigation.listAppearance
        f.navigation.select(claimId:"synthetic-claim",presentation:f.navigation.listPermit)
        stage("detail-requested")
        try await wait("detail pushed and ready") { f.browser.detail?.item?.claimId == "synthetic-claim" && f.navigation.detailPermit != nil }
        stage("detail-ready")
        XCTAssertNil(f.navigation.listPermit); XCTAssertEqual(f.browser.rows.count,1)
        let detailPermit = try XCTUnwrap(f.navigation.detailPermit)
        let firstDetailBox = f.navigation.detailAppearance
        f.navigation.openPackage(presentation:f.navigation.detailPermit)
        stage("package-requested")
        try await wait("package pushed and unavailable") { f.browser.packageBrowser?.phase == .unavailable && f.navigation.packagePermit != nil }
        stage("package-ready")
        let firstPackageBox = f.navigation.packageAppearance
        XCTAssertNil(f.navigation.detailPermit); XCTAssertNotNil(f.browser.detail)
        f.navigation.showsPackage = false
        stage("back-detail-requested")
        try await wait("Back from package restores detail and retires package", diagnostics: { "detailPermit=\(f.navigation.detailPermit != nil), packagePermit=\(f.navigation.packagePermit != nil), detail=\(f.browser.detail != nil), showsPackage=\(f.navigation.showsPackage), selected=\(f.navigation.selection != nil)" }) { f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil }
        stage("detail-returned")
        XCTAssertFalse(f.navigation.detailPermit === detailPermit)
        f.navigation.selection = nil
        stage("back-list-requested")
        try await wait("Back from detail restores list and retires detail") { f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil }
        stage("list-returned")
        XCTAssertFalse(f.navigation.listPermit === listPermit)
        XCTAssertTrue(f.recorder.paths.contains("/native/api/workshop/owned/package")); XCTAssertEqual(f.state.unauthorized,0)

        // Returning and reopening must be real appearances, not content-ID replacement callbacks.
        let returnedList = try XCTUnwrap(f.navigation.listPermit)
        let returnedListBox = f.navigation.listAppearance
        f.navigation.listViewDisappeared(firstListBox)
        f.navigation.detailViewDisappeared(firstDetailBox)
        f.navigation.packageViewDisappeared(firstPackageBox)
        XCTAssertTrue(f.navigation.listPermit === returnedList); XCTAssertTrue(returnedList.isLive)
        f.navigation.select(claimId:"synthetic-claim",presentation:returnedList)
        try await wait("same hosted detail reopens with fresh permit") { f.browser.detail?.item?.claimId == "synthetic-claim" && f.navigation.detailPermit != nil }
        let reopenedDetail = try XCTUnwrap(f.navigation.detailPermit)
        XCTAssertFalse(reopenedDetail === detailPermit)
        f.navigation.listViewDisappeared(returnedListBox)
        f.navigation.detailViewDisappeared(firstDetailBox)
        XCTAssertTrue(f.navigation.detailPermit === reopenedDetail); XCTAssertTrue(reopenedDetail.isLive)
        f.navigation.selection = nil
        try await wait("second Back restores live list") { f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil }
        XCTAssertFalse(f.navigation.listPermit === returnedList)

        // Retiring visible content changes its identity once. A redraw must not manufacture
        // another screen appearance, read, permit or recursive disappearance of the fresh box.
        let retiringBox = f.navigation.listAppearance
        let retiringPermit = try XCTUnwrap(f.navigation.listPermit)
        let calls = f.recorder.paths.count
        f.navigation.listViewDisappeared(retiringBox)
        let inactiveBox = f.navigation.listAppearance
        XCTAssertFalse(inactiveBox === retiringBox); XCTAssertFalse(retiringPermit.isLive)
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(f.navigation.listAppearance === inactiveBox)
            XCTAssertNil(f.navigation.listPermit); XCTAssertEqual(f.recorder.paths.count,calls)
        }
        f.navigation.listViewDisappeared(retiringBox)
        XCTAssertTrue(f.navigation.listAppearance === inactiveBox); XCTAssertNil(f.navigation.listPermit)
        XCTAssertEqual(f.state.unauthorized,0)
    }

    func testHiddenParentDisappearanceDoesNotContinuouslyReplaceInactiveIdentities() async throws {
        let f = try fixture(), listBox = f.navigation.listAppearance
        let list = try XCTUnwrap(f.navigation.listViewAppeared(listBox))
        await f.browser.load(action: list.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: list)
        let inactiveList = f.navigation.listAppearance
        XCTAssertNil(inactiveList.permit)
        for _ in 0..<3 {
            XCTAssertNil(f.navigation.listViewAppeared(inactiveList))
            f.navigation.listViewDisappeared(inactiveList)
            XCTAssertTrue(f.navigation.listAppearance === inactiveList)
        }
        let detailBox = f.navigation.detailAppearance
        let detail = try XCTUnwrap(f.navigation.detailViewAppeared(detailBox, claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: detail.offer()!)
        f.navigation.openPackage(presentation: detail)
        let inactiveDetail = f.navigation.detailAppearance
        XCTAssertNil(inactiveDetail.permit)
        for _ in 0..<3 {
            XCTAssertNil(f.navigation.detailViewAppeared(inactiveDetail, claimId: "synthetic-claim"))
            f.navigation.detailViewDisappeared(inactiveDetail)
            XCTAssertTrue(f.navigation.detailAppearance === inactiveDetail)
        }
        XCTAssertEqual(f.recorder.paths.count, 2)
        XCTAssertTrue(f.navigation.showsPackage)
        XCTAssertNotNil(f.browser.detail)
        XCTAssertEqual(f.state.unauthorized, 0)
    }

    func testCurrentVisibleCloseCreatesOneFreshBoxAndOldCloseCannotRetireItsRead() async throws {
        let f = try fixture(), oldBox = f.navigation.listAppearance
        let old = try XCTUnwrap(f.navigation.listViewAppeared(oldBox))
        // The current permit was installed synchronously, before any body redraw.
        f.navigation.listViewDisappeared(oldBox)
        let freshBox = f.navigation.listAppearance
        XCTAssertFalse(freshBox === oldBox); XCTAssertFalse(old.isLive)
        XCTAssertNil(f.navigation.listViewAppeared(oldBox))
        let fresh = try XCTUnwrap(f.navigation.listViewAppeared(freshBox))
        f.recorder.hold = true; f.navigation.scheduleList(fresh)
        try await wait("current reopened list held") { f.recorder.waiting.count == 1 }
        for _ in 0..<3 { f.navigation.listViewDisappeared(oldBox) }
        XCTAssertTrue(f.navigation.listAppearance === freshBox)
        XCTAssertTrue(f.navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
        f.recorder.releaseAll()
        try await wait("current reopened list ready") { f.browser.phase == .ready }
        XCTAssertEqual(f.recorder.paths.count, 1); XCTAssertEqual(f.state.unauthorized, 0)
    }

    func testAlreadyInvalidatedPresentationCannotProduceAnotherViewIdentity() async throws {
        let f = try fixture(), box = f.navigation.listAppearance
        let permit = try XCTUnwrap(f.navigation.listViewAppeared(box))
        await f.browser.load(action: permit.offer()!)
        f.browser.leaveList(permit, closing: false)
        XCTAssertFalse(permit.isLive)
        for _ in 0..<3 {
            f.navigation.listViewDisappeared(box)
            XCTAssertTrue(f.navigation.listAppearance === box)
            XCTAssertNil(f.navigation.listViewAppeared(box))
        }
        XCTAssertNil(f.navigation.listPermit)
        XCTAssertEqual(f.recorder.paths.count, 1); XCTAssertEqual(f.state.unauthorized, 0)
    }

    func testPackageBackInactiveCallbacksDoNotReplaceTheReturningDetail() async throws {
        let f = try fixture(), list = try XCTUnwrap(f.navigation.listViewAppeared(f.navigation.listAppearance))
        await f.browser.load(action: list.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: list)
        let detail = try XCTUnwrap(f.navigation.detailViewAppeared(f.navigation.detailAppearance, claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: detail.offer()!)
        f.navigation.openPackage(presentation: detail)
        let package = try XCTUnwrap(f.navigation.packageViewAppeared(f.navigation.packageAppearance, claimId: "synthetic-claim"))
        await f.browser.packageBrowser!.load(claimId: "synthetic-claim", action: package.offer()!)
        f.navigation.showsPackage = false
        let inactivePackage = f.navigation.packageAppearance, returningDetail = f.navigation.detailAppearance
        for _ in 0..<3 {
            XCTAssertNil(f.navigation.packageViewAppeared(inactivePackage, claimId: "synthetic-claim"))
            f.navigation.packageViewDisappeared(inactivePackage)
            XCTAssertTrue(f.navigation.packageAppearance === inactivePackage)
            XCTAssertTrue(f.navigation.detailAppearance === returningDetail)
        }
        let fresh = try XCTUnwrap(f.navigation.detailViewAppeared(returningDetail, claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: fresh.offer()!)
        XCTAssertTrue(f.navigation.detailPermit === fresh)
        XCTAssertFalse(f.navigation.showsPackage); XCTAssertFalse(package.isLive)
        XCTAssertEqual(f.recorder.paths.count, 4); XCTAssertEqual(f.state.unauthorized, 0)
    }
    func testHostedDismissalRevokesQueuedToolbarActionBeforeEntry() async throws {
        let f = try fixture()
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser:f.browser,navigation:f.navigation) })
        let window = UIWindow(frame:UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { f.browser.phase == .ready && f.navigation.listPermit != nil }
        let permit = try XCTUnwrap(f.navigation.listPermit), calls = f.recorder.paths.count
        // Same synchronous dismissal hook used by onDisappear; the queued button captures old permit.
        let queued = Task { [action = permit.offer()!] in await f.browser.load(action:action) }
        f.navigation.listDisappeared(permit); f.recorder.unauthorized = true
        await queued.value; XCTAssertEqual(f.recorder.paths.count,calls); XCTAssertEqual(f.state.unauthorized,0)
        window.isHidden = true; window.rootViewController = nil
        XCTAssertNil(f.navigation.listPermit)
    }
    func testNavigationPushRevokesQueuedListAndDetailActionsSynchronously() async throws {
        let f = try fixture(), list = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action:list.offer()!)
        let queuedList = Task { [action = list.offer()!] in await f.browser.load(action:action) }
        f.navigation.select(claimId:"synthetic-claim",presentation:f.navigation.listPermit)
        let detail = try XCTUnwrap(f.navigation.detailAppeared(claimId:"synthetic-claim"))
        await queuedList.value; XCTAssertEqual(f.recorder.paths.count,1)
        await f.browser.open(claimId:"synthetic-claim",action:detail.offer()!)
        let queuedDetail = Task { [action = detail.offer()!] in await f.browser.open(claimId:"synthetic-claim",action:action) }
        f.navigation.openPackage(presentation:f.navigation.detailPermit); f.recorder.unauthorized = true
        await queuedDetail.value; XCTAssertEqual(f.recorder.paths.count,2); XCTAssertEqual(f.state.unauthorized,0)
        XCTAssertNotNil(f.browser.detail); XCTAssertEqual(f.browser.rows.count,1)
    }
    func testOldListDisappearanceDoesNotCancelNewHeldRead() async throws {
        let f = try fixture(), old = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action: old.offer()!)
        f.navigation.listDisappeared(old)
        let fresh = try XCTUnwrap(f.navigation.listAppeared())
        f.recorder.hold = true; f.navigation.scheduleList(fresh)
        try await wait("new list held") { f.recorder.waiting.count == 1 }
        f.navigation.listDisappeared(old)
        XCTAssertTrue(f.navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
        f.recorder.releaseAll()
        try await wait("new list completes") { f.browser.phase == .ready }
        XCTAssertEqual(f.browser.rows.count, 1); XCTAssertEqual(f.state.unauthorized, 0)
    }
    func testOldDetailDisappearanceDoesNotCancelNewHeldRead() async throws {
        let f = try fixture(), list = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action: list.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: list)
        let old = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: old.offer()!)
        f.navigation.selection = nil
        f.navigation.selection = .init(id: "synthetic-claim")
        let fresh = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        f.recorder.hold = true; f.navigation.scheduleDetail(fresh, claimId: "synthetic-claim")
        try await wait("new detail held") { f.recorder.waiting.count == 1 }
        f.navigation.detailDisappeared(old)
        XCTAssertTrue(f.navigation.detailPermit === fresh); XCTAssertTrue(fresh.isLive)
        f.recorder.releaseAll()
        try await wait("new detail completes") { f.browser.detail?.item?.claimId == "synthetic-claim" }
        XCTAssertEqual(f.state.unauthorized, 0)
    }
    func testOldPackageDisappearanceDoesNotCancelNewHeldRead() async throws {
        let f = try fixture(), list = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action: list.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: list)
        let detail = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: detail.offer()!)
        f.navigation.openPackage(presentation: detail)
        let old = try XCTUnwrap(f.navigation.packageAppeared(claimId: "synthetic-claim"))
        f.navigation.showsPackage = false
        let reopenedDetail = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: reopenedDetail.offer()!)
        f.navigation.openPackage(presentation: reopenedDetail)
        let fresh = try XCTUnwrap(f.navigation.packageAppeared(claimId: "synthetic-claim"))
        f.recorder.hold = true; f.navigation.schedulePackage(fresh, claimId: "synthetic-claim")
        try await wait("new package held") { f.recorder.waiting.count == 1 }
        f.navigation.packageDisappeared(old)
        XCTAssertTrue(f.navigation.packagePermit === fresh); XCTAssertTrue(fresh.isLive)
        f.recorder.releaseAll()
        try await wait("new package completes") { f.browser.packageBrowser?.phase == .unavailable }
        XCTAssertEqual(f.state.unauthorized, 0)
    }
    func testVisibleAppearanceClosesBeforeFirstRedrawAndCannotRevive() async throws {
        let f = try fixture(), visible = WorkshopOwnedViewAppearance()
        let permit = try XCTUnwrap(visible.appear { f.navigation.listAppeared() })
        let queued = try XCTUnwrap(f.navigation.offerList(permit))
        visible.disappear { f.navigation.listDisappeared($0) }
        await queued()
        XCTAssertTrue(f.recorder.paths.isEmpty); XCTAssertNil(f.navigation.listPermit)
        XCTAssertNil(visible.appear { f.navigation.listAppeared() })
        let next = WorkshopOwnedViewAppearance()
        let fresh = try XCTUnwrap(next.appear { f.navigation.listAppeared() })
        visible.disappear { f.navigation.listDisappeared($0) }
        XCTAssertTrue(f.navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
    }
    func testBackBindingRetiresQueuedDetailAndPackageBeforeDisappearance() async throws {
        let f = try fixture(), list = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action: list.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: list)
        let detail = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        let queuedDetail = try XCTUnwrap(f.navigation.offerDetail(detail, claimId: "synthetic-claim"))
        f.navigation.selection = nil; await queuedDetail()
        XCTAssertEqual(f.recorder.paths.count, 1); XCTAssertFalse(detail.isLive)
        XCTAssertNil(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        f.navigation.selection = .init(id: "synthetic-claim")
        let fresh = try XCTUnwrap(f.navigation.detailAppeared(claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: fresh.offer()!)
        f.navigation.openPackage(presentation: fresh)
        let package = try XCTUnwrap(f.navigation.packageAppeared(claimId: "synthetic-claim"))
        let queuedPackage = try XCTUnwrap(f.navigation.offerPackage(package, claimId: "synthetic-claim"))
        f.navigation.showsPackage = false; await queuedPackage()
        XCTAssertEqual(f.recorder.paths.count, 2); XCTAssertFalse(package.isLive)
        XCTAssertNil(f.navigation.packageAppeared(claimId: "synthetic-claim"))
    }
    func testCurrentDisappearanceSuppressesHeld401WhileCurrent401StillExpiresSession() async throws {
        let f = try fixture(), old = try XCTUnwrap(f.navigation.listAppeared())
        f.recorder.hold = true; f.navigation.scheduleList(old)
        try await wait("old list held") { f.recorder.waiting.count == 1 }
        f.navigation.listDisappeared(old); f.recorder.unauthorized = true
        f.recorder.releaseAll()
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(f.state.unauthorized, 0)
        f.recorder.hold = false
        let fresh = try XCTUnwrap(f.navigation.listAppeared())
        await f.browser.load(action: fresh.offer()!)
        XCTAssertEqual(f.state.unauthorized, 1)
    }

    func testBackBeforeOldDisappearanceUsesNewRouteBoxAndOldCallbacksCannotClearIt() async throws {
        let f = try fixture(), oldListBox = f.navigation.listAppearance
        let oldList = try XCTUnwrap(f.navigation.listViewAppeared(oldListBox))
        await f.browser.load(action: oldList.offer()!)
        f.navigation.select(claimId: "synthetic-claim", presentation: oldList)
        let oldDetailBox = f.navigation.detailAppearance
        let oldDetail = try XCTUnwrap(f.navigation.detailViewAppeared(oldDetailBox, claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: oldDetail.offer()!)
        f.navigation.openPackage(presentation: oldDetail)
        let oldPackageBox = f.navigation.packageAppearance
        _ = try XCTUnwrap(f.navigation.packageViewAppeared(oldPackageBox, claimId: "synthetic-claim"))
        // No old onDisappear has fired. Returning still receives a fresh route-owned box.
        f.navigation.showsPackage = false
        let freshDetailBox = f.navigation.detailAppearance
        let freshDetail = try XCTUnwrap(f.navigation.detailViewAppeared(freshDetailBox, claimId: "synthetic-claim"))
        XCTAssertFalse(freshDetailBox === oldDetailBox)
        f.navigation.detailViewDisappeared(oldDetailBox)
        f.navigation.packageViewDisappeared(oldPackageBox)
        XCTAssertTrue(f.navigation.detailPermit === freshDetail); XCTAssertTrue(freshDetail.isLive)
        XCTAssertNil(f.navigation.detailViewAppeared(oldDetailBox, claimId: "synthetic-claim"))
        f.navigation.selection = nil
        let freshListBox = f.navigation.listAppearance
        let freshList = try XCTUnwrap(f.navigation.listViewAppeared(freshListBox))
        XCTAssertFalse(freshListBox === oldListBox)
        f.navigation.listViewDisappeared(oldListBox)
        f.navigation.detailViewDisappeared(freshDetailBox)
        XCTAssertTrue(f.navigation.listPermit === freshList); XCTAssertTrue(freshList.isLive)
        XCTAssertNil(f.navigation.listViewAppeared(oldListBox))
        await f.browser.load(action: freshList.offer()!)
        XCTAssertEqual(f.browser.rows.count, 1)
    }

}


extension WorkshopOwnedNavigationPresentationTests {
    func testRouteReturnRequiresRealVisibilityAndFalseToTrueEligibility() {
        var visibility = WorkshopVisibleRouteReturn(), resumed = 0
        visibility.returned(wasEligible: false, isEligible: true) { resumed += 1 }
        XCTAssertEqual(resumed, 0)
        visibility.appear()
        visibility.returned(wasEligible: true, isEligible: true) { resumed += 1 }
        visibility.returned(wasEligible: true, isEligible: false) { resumed += 1 }
        visibility.returned(wasEligible: false, isEligible: false) { resumed += 1 }
        XCTAssertEqual(resumed, 0)
        visibility.returned(wasEligible: false, isEligible: true) { resumed += 1 }
        XCTAssertEqual(resumed, 1)
        visibility.disappear()
        visibility.returned(wasEligible: false, isEligible: true) { resumed += 1 }
        XCTAssertEqual(resumed, 1)
        XCTAssertFalse(visibility.isVisible)
    }

    func testVisibleRouteBackWithoutAnotherAppearanceIssuesFreshPermitsAndRejectsOldCallbacks() async throws {
        let f = try fixture(), oldListBox = f.navigation.listAppearance
        var listVisibility = WorkshopVisibleRouteReturn(), detailVisibility = WorkshopVisibleRouteReturn()
        listVisibility.appear()
        let oldList = try XCTUnwrap(f.navigation.listViewAppeared(oldListBox))
        await f.browser.load(action: try XCTUnwrap(oldList.offer()))
        f.navigation.select(claimId: "synthetic-claim", presentation: oldList)
        let oldDetailBox = f.navigation.detailAppearance
        detailVisibility.appear()
        let oldDetail = try XCTUnwrap(f.navigation.detailViewAppeared(oldDetailBox, claimId: "synthetic-claim"))
        await f.browser.open(claimId: "synthetic-claim", action: try XCTUnwrap(oldDetail.offer()))
        f.navigation.openPackage(presentation: oldDetail)
        let oldPackageBox = f.navigation.packageAppearance
        let oldPackage = try XCTUnwrap(f.navigation.packageViewAppeared(oldPackageBox, claimId: "synthetic-claim"))
        await f.browser.packageBrowser!.load(claimId: "synthetic-claim", action: try XCTUnwrap(oldPackage.offer()))
        f.navigation.showsPackage = false
        let detailBox = f.navigation.detailAppearance
        XCTAssertNil(detailBox.permit)
        // Match the observed host sequence: no second real detail onAppear after Back.
        detailVisibility.returned(wasEligible: false, isEligible: true) {
            guard f.navigation.selection?.id == "synthetic-claim" && !f.navigation.showsPackage, detailBox.permit == nil else { return }
            f.navigation.scheduleDetail(f.navigation.detailViewAppeared(detailBox, claimId: "synthetic-claim"), claimId: "synthetic-claim")
        }
        try await wait("retained visible detail resumes") { f.navigation.detailPermit != nil && f.browser.detail != nil && f.recorder.paths.count == 4 }
        let detail = try XCTUnwrap(f.navigation.detailPermit)
        XCTAssertFalse(detail === oldDetail); XCTAssertFalse(oldDetail.isLive); XCTAssertFalse(oldPackage.isLive)
        f.navigation.detailViewDisappeared(oldDetailBox); f.navigation.packageViewDisappeared(oldPackageBox)
        XCTAssertTrue(f.navigation.detailPermit === detail); XCTAssertTrue(detail.isLive)
        XCTAssertNil(f.navigation.detailViewAppeared(oldDetailBox, claimId: "synthetic-claim"))
        // An already-issued current box must not offer a duplicate read.
        detailVisibility.returned(wasEligible: false, isEligible: true) {
            guard detailBox.permit == nil else { return }
            XCTFail("already-issued detail must not resume twice")
        }
        f.navigation.selection = nil
        let listBox = f.navigation.listAppearance
        listVisibility.returned(wasEligible: false, isEligible: true) {
            guard f.navigation.selection == nil, listBox.permit == nil else { return }
            f.navigation.scheduleList(f.navigation.listViewAppeared(listBox))
        }
        try await wait("retained visible list resumes") { f.navigation.listPermit != nil && f.browser.phase == .ready && f.recorder.paths.count == 5 }
        let list = try XCTUnwrap(f.navigation.listPermit)
        XCTAssertFalse(list === oldList); XCTAssertFalse(oldList.isLive); XCTAssertFalse(detail.isLive)
        f.navigation.listViewDisappeared(oldListBox); f.navigation.detailViewDisappeared(detailBox)
        XCTAssertTrue(f.navigation.listPermit === list); XCTAssertTrue(list.isLive)
        XCTAssertNil(f.navigation.listViewAppeared(oldListBox))
        // Manual retirement changes only the box, not eligibility: it cannot self-revive.
        f.navigation.listViewDisappeared(listBox)
        let retiredReplacement = f.navigation.listAppearance
        listVisibility.returned(wasEligible: true, isEligible: true) { XCTFail("manual retirement cannot resume") }
        XCTAssertNil(f.navigation.listPermit); XCTAssertNil(retiredReplacement.permit)
        listVisibility.disappear()
        listVisibility.returned(wasEligible: false, isEligible: true) { XCTFail("hidden list cannot resume") }
        XCTAssertTrue(f.navigation.listAppearance === retiredReplacement)
        XCTAssertEqual(f.recorder.paths.count, 5); XCTAssertEqual(f.state.unauthorized, 0)
    }
}


extension WorkshopOwnedNavigationPresentationTests {
    func testHostedListManualRetirementDoesNotRemountOrReissuePermit() async throws {
        let f = try fixture()
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser: f.browser, navigation: f.navigation) })
        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        try await wait("mounted list is ready") { f.browser.phase == .ready && f.navigation.listPermit != nil }
        XCTAssertTrue(host.view.window === window)
        let oldBox = f.navigation.listAppearance, oldPermit = try XCTUnwrap(f.navigation.listPermit)
        let calls = f.recorder.paths.count
        f.navigation.listViewDisappeared(oldBox)
        let inactive = f.navigation.listAppearance
        XCTAssertFalse(inactive === oldBox); XCTAssertFalse(oldPermit.isLive)
        XCTAssertNil(f.navigation.offerList(oldPermit)); XCTAssertTrue(f.browser.rows.isEmpty)
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(host.view.window === window)
            XCTAssertTrue(f.navigation.listAppearance === inactive)
            XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.listPermit)
            XCTAssertEqual(f.recorder.paths.count, calls)
        }
        f.navigation.listViewDisappeared(oldBox)
        XCTAssertTrue(f.navigation.listAppearance === inactive)
        XCTAssertNil(f.navigation.listViewAppeared(oldBox))
        XCTAssertNil(f.navigation.listPermit); XCTAssertEqual(f.recorder.paths.count, calls)
        XCTAssertEqual(f.state.unauthorized, 0)
    }
}


extension WorkshopOwnedNavigationPresentationTests {
    func testHostedDetailManualRetirementDoesNotRemountOrReissuePermit() async throws {
        let f = try fixture()
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser: f.browser, navigation: f.navigation) })
        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        try await wait("mounted list is ready for detail retirement") { f.browser.phase == .ready && f.navigation.listPermit != nil }
        f.navigation.select(claimId: "synthetic-claim", presentation: f.navigation.listPermit)
        try await wait("mounted detail is ready for retirement") { f.browser.detail?.item?.claimId == "synthetic-claim" && f.navigation.detailPermit != nil }
        XCTAssertTrue(host.view.window === window)
        let oldBox = f.navigation.detailAppearance, oldPermit = try XCTUnwrap(f.navigation.detailPermit)
        let calls = f.recorder.paths.count
        f.navigation.detailViewDisappeared(oldBox)
        let inactive = f.navigation.detailAppearance
        XCTAssertFalse(inactive === oldBox); XCTAssertFalse(oldPermit.isLive)
        XCTAssertNil(f.navigation.offerDetail(oldPermit, claimId: "synthetic-claim")); XCTAssertNil(f.browser.detail)
        XCTAssertEqual(f.navigation.selection?.id, "synthetic-claim"); XCTAssertFalse(f.navigation.showsPackage)
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(host.view.window === window)
            XCTAssertTrue(f.navigation.detailAppearance === inactive)
            XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.detailPermit)
            XCTAssertEqual(f.recorder.paths.count, calls)
        }
        f.navigation.detailViewDisappeared(oldBox)
        XCTAssertTrue(f.navigation.detailAppearance === inactive)
        XCTAssertNil(f.navigation.detailViewAppeared(oldBox, claimId: "synthetic-claim"))
        XCTAssertNil(f.navigation.detailPermit); XCTAssertEqual(f.recorder.paths.count, calls)
        f.navigation.selection = nil
        try await wait("real Back after manual detail retirement restores list") { f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil }
        XCTAssertEqual(f.state.unauthorized, 0)
    }
}


extension WorkshopOwnedNavigationPresentationTests {
    func testHostedPackageReopenAndManualRetirementKeepPermitsScopedWithoutRemount() async throws {
        let f = try fixture()
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser: f.browser, navigation: f.navigation) })
        let sceneWindow = try HostedNavigationSceneWindow(), window = sceneWindow.window
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { sceneWindow.retire() }
        try await wait("mounted list ready for package reopen") { f.browser.phase == .ready && f.navigation.listPermit != nil }
        f.navigation.select(claimId: "synthetic-claim", presentation: f.navigation.listPermit)
        try await wait("mounted detail ready for package reopen") { f.browser.detail?.item?.claimId == "synthetic-claim" && f.navigation.detailPermit != nil }
        f.navigation.openPackage(presentation: f.navigation.detailPermit)
        try await wait("first hosted package ready") { f.browser.packageBrowser?.phase == .unavailable && f.navigation.packagePermit != nil }
        let firstBox = f.navigation.packageAppearance, firstPermit = try XCTUnwrap(f.navigation.packagePermit)
        f.navigation.showsPackage = false
        try await wait("first package Back restores detail") { f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil }
        XCTAssertFalse(firstPermit.isLive)
        f.navigation.openPackage(presentation: f.navigation.detailPermit)
        try await wait("second hosted package ready with fresh permit") { f.browser.packageBrowser?.phase == .unavailable && f.navigation.packagePermit != nil }
        let secondBox = f.navigation.packageAppearance, secondPermit = try XCTUnwrap(f.navigation.packagePermit)
        XCTAssertFalse(secondBox === firstBox); XCTAssertFalse(secondPermit === firstPermit)
        f.navigation.packageViewDisappeared(firstBox)
        XCTAssertTrue(f.navigation.packagePermit === secondPermit); XCTAssertTrue(secondPermit.isLive)
        XCTAssertNil(f.navigation.packageViewAppeared(firstBox, claimId: "synthetic-claim"))
        let calls = f.recorder.paths.count
        f.navigation.packageViewDisappeared(secondBox)
        let inactive = f.navigation.packageAppearance
        XCTAssertFalse(inactive === secondBox); XCTAssertFalse(secondPermit.isLive)
        XCTAssertNil(f.navigation.offerPackage(secondPermit, claimId: "synthetic-claim"))
        XCTAssertNil(f.browser.packageBrowser?.value); XCTAssertEqual(f.browser.packageBrowser?.phase, .idle)
        XCTAssertTrue(f.navigation.showsPackage); XCTAssertEqual(f.navigation.selection?.id, "synthetic-claim")
        for _ in 0..<5 {
            try await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertTrue(host.view.window === window)
            XCTAssertTrue(f.navigation.packageAppearance === inactive)
            XCTAssertNil(inactive.permit); XCTAssertNil(f.navigation.packagePermit)
            XCTAssertEqual(f.recorder.paths.count, calls)
        }
        f.navigation.packageViewDisappeared(firstBox); f.navigation.packageViewDisappeared(secondBox)
        XCTAssertTrue(f.navigation.packageAppearance === inactive)
        XCTAssertNil(f.navigation.packageViewAppeared(secondBox, claimId: "synthetic-claim"))
        XCTAssertNil(f.navigation.packagePermit); XCTAssertEqual(f.recorder.paths.count, calls)
        f.navigation.showsPackage = false
        try await wait("second package Back after retirement restores detail") { f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil }
        f.navigation.selection = nil
        try await wait("package reopen round trip returns to list") { f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil }
        XCTAssertEqual(f.state.unauthorized, 0)
    }
}
