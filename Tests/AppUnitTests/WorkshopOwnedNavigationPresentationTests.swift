import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class WorkshopOwnedNavigationPresentationTests: XCTestCase {
    private final class Recorder: HTTPTransport {
        var paths: [String] = []
        var unauthorized = false
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = request.url!.path; paths.append(path)
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
    private func wait(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition()); if !condition() { throw WorkshopOwnedIssue.unavailable }
    }
    /// Actual SwiftUI NavigationStack appearance/disappearance and destination binding, not only
    /// direct browser calls. Button handlers use these exact navigation-state actions in production.
    func testHostedListDetailPackageBackAndReopenIssueFreshPermits() async throws {
        let f = try fixture()
        let host = UIHostingController(rootView: NavigationStack { WorkshopOwnedLibraryView(browser:f.browser,navigation:f.navigation) })
        let window = UIWindow(frame:UIScreen.main.bounds); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await wait { f.browser.phase == .ready && f.navigation.listPermit != nil }
        let listPermit = try XCTUnwrap(f.navigation.listPermit)
        f.navigation.select(claimId:"synthetic-claim",presentation:f.navigation.listPermit)
        try await wait { f.browser.detail?.item?.claimId == "synthetic-claim" && f.navigation.detailPermit != nil }
        XCTAssertNil(f.navigation.listPermit); XCTAssertEqual(f.browser.rows.count,1)
        let detailPermit = try XCTUnwrap(f.navigation.detailPermit)
        f.navigation.openPackage(presentation:f.navigation.detailPermit)
        try await wait { f.browser.packageBrowser?.phase == .unavailable && f.navigation.packagePermit != nil }
        XCTAssertNil(f.navigation.detailPermit); XCTAssertNotNil(f.browser.detail)
        f.navigation.showsPackage = false
        try await wait { f.navigation.detailPermit != nil && f.browser.detail != nil && f.navigation.packagePermit == nil }
        XCTAssertFalse(f.navigation.detailPermit === detailPermit)
        f.navigation.selection = nil
        try await wait { f.navigation.listPermit != nil && f.browser.phase == .ready && f.navigation.detailPermit == nil }
        XCTAssertFalse(f.navigation.listPermit === listPermit)
        XCTAssertTrue(f.recorder.paths.contains("/native/api/workshop/owned/package")); XCTAssertEqual(f.state.unauthorized,0)
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
        f.navigation.listDisappeared(); f.recorder.unauthorized = true
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
}
