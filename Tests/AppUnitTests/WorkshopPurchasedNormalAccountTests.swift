import XCTest
import Observation
import SwiftUI
import UIKit
@testable import Questify

@MainActor enum WorkshopPurchasedAppFixture {
    static let item: [String: Any] = ["licenseId":"w18-paid-11","moduleId":"synthetic-module","purchasedVersionId":"synthetic-version","contentHash":String(repeating:"a",count:64),"status":"ACTIVE","acquiredAt":"2026-10-05T00:00:00Z","termsVersion":"terms-1","termsHash":String(repeating:"b",count:64),"commercialUse":"PROHIBITED","adaptation":"LOCAL_ADAPTATION","translation":"PROHIBITED","updates":"EXACT_PURCHASED_VERSION","redistribution":"PROHIBITED","allowedRegions":["synthetic-region"],"themeLimit":["unlimited":false,"maximum":1],"merchantLimit":["unlimited":false,"maximum":0],"runLimit":["unlimited":false,"maximum":10],"acquisition":"PAID","buyerKind":"INDIVIDUAL","useDuration":"PERPETUAL_PURCHASED_VERSION","contentUseStatus":"PAID_INSTALL_AUTHORITY_UNAVAILABLE","purchaseActionStatus":"CHANNEL_APPROVAL_REQUIRED"]
    static let header: [String: Any] = ["schema":"workshop-purchased-owned-v1","scope":"PAID_INDIVIDUAL_PURCHASED_VERSION_METADATA_ONLY","checkedAt":"2026-10-05T00:00:00Z"]
    static func page(_ rows: [[String:Any]] = [item], next: Int64? = nil) -> [String:Any] { var data=header;data["items"]=rows;data["hasMore"]=next != nil;data["nextBeforeOrderLineId"]=next.map{$0 as Any} ?? NSNull();return data }
    static func detail(_ value:[String:Any] = item)->[String:Any]{var data=header;data["item"]=value;return data}
    static func envelope(_ object:[String:Any]) throws -> Data {try JSONSerialization.data(withJSONObject:["code":200,"data":object])}
}

@MainActor final class WorkshopPurchasedNormalAccountTests: XCTestCase {
    func testNormalRootGuestAndSignedInRemainUnavailableWithoutSeparateApproval() async throws {
        let h = try Harness(); defer { h.clean() }
        XCTAssertNil(h.session.workshopPurchasedBrowser)
        await h.login()
        XCTAssertTrue(h.session.isSignedIn); XCTAssertNil(h.session.workshopPurchasedBrowser)
        XCTAssertEqual(h.wire.owned.count, 0)
        XCTAssertNil(AppSession(composition: .init()).workshopPurchasedBrowser)
    }
    func testApprovedNormalAccountListDetailAndReopenUseOneBrowserAndExactOwnerToken() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        XCTAssertTrue(browser === h.session.workshopPurchasedBrowser); XCTAssertEqual(h.wire.owned.count, 0)
        await browser.load(action: try listAction(browser)); XCTAssertEqual(browser.phase, .ready)
        await browser.open(licenseId: "w18-paid-11", action: try detailAction(browser)); XCTAssertEqual(browser.detail?.item.licenseId, "w18-paid-11")
        XCTAssertEqual(h.wire.owned.map { $0.url!.lastPathComponent }, ["list", "detail"])
        XCTAssertEqual(h.wire.owned[0].httpBody, Data())
        XCTAssertEqual(h.wire.owned[1].httpBody, Data("license_id=w18-paid-11".utf8))
        XCTAssertTrue(h.wire.owned.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" && WorkshopPurchasedReadRoute(request: $0, baseURL: h.base) != nil })
        browser.closeList(); XCTAssertNil(browser.detail); XCTAssertTrue(browser.rows.isEmpty)
        XCTAssertTrue(browser === h.session.workshopPurchasedBrowser)
        await browser.load(action: try listAction(browser)); XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 3)
    }
    func testRoleABAInvalidatesBeforeAccountPublishesAndRejectsLateSuccessAndBoth401Forms() async throws {
        for reply in [Wire.listReply, (Data(), 401), (Data(#"{"code":401}"#.utf8), 200)] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let old = try XCTUnwrap(h.session.workshopPurchasedBrowser), issued = h.approval
            h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }
            await h.wire.waitForPending()
            h.wire.role = "merchant"; await h.session.refreshOwnAccount()
            XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(h.session.workshopPurchasedBrowser)
            h.wire.role = "player"; await h.session.refreshOwnAccount()
            XCTAssertEqual(h.approval?.revision, issued?.revision)
            let replacement = try XCTUnwrap(h.session.workshopPurchasedBrowser)
            XCTAssertFalse(replacement === old)
            h.wire.resume(reply); await task.value
            XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.session.account?.effectiveRole, "player")
            XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty); XCTAssertNil(old.detail)
            XCTAssertEqual(replacement.phase, .idle); XCTAssertEqual(h.vault.token, "synthetic-7")
        }
    }
    func testOwnerTokenEpochReplacementAndLogoutCannotBeExpiredByOldResponse() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopPurchasedBrowser), epoch = h.session.sessionRevision
        h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }; await h.wire.waitForPending()
        await h.session.logout(); XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(h.session.workshopPurchasedBrowser)
        h.wire.accountID = 8; h.wire.token = "synthetic-8"; await h.login(); try h.approve()
        let replacement = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        XCTAssertGreaterThan(h.session.sessionRevision, epoch)
        h.wire.resume((Data(), 401)); await task.value
        XCTAssertEqual(h.session.account?.id, 8); XCTAssertEqual(h.vault.token, "synthetic-8")
        XCTAssertEqual(replacement.phase, .idle); XCTAssertEqual(old.phase, .invalidated)
    }
    func testConfigurationABAInvalidatesBeforeMutationAndOld401HasNoSideEffect() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopPurchasedBrowser), issued = h.approval
        h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }; await h.wire.waitForPending()
        h.session.withWorkshopReadConfigurationChange {
            XCTAssertEqual(old.phase, .invalidated); h.approval = nil
        }
        XCTAssertNil(h.session.workshopPurchasedBrowser)
        h.session.withWorkshopReadConfigurationChange { h.approval = issued; XCTAssertNil(h.session.workshopPurchasedBrowser) }
        let replacement = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        XCTAssertFalse(replacement === old)
        h.wire.resume((Data(), 401)); await task.value
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(replacement.phase, .idle)
    }
    func testRootRemovalRetiresLoadedProjectionAndReentryDoesNotResurrectIt() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopPurchasedBrowser); await old.load(action: try listAction(old)); await old.open(licenseId: "w18-paid-11", action: try detailAction(old))
        h.session.setWorkshopOwnedPresentationActive(false)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty); XCTAssertNil(old.detail)
        XCTAssertNil(h.session.workshopPurchasedBrowser)
        h.session.setWorkshopOwnedPresentationActive(true)
        let fresh = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        XCTAssertFalse(fresh === old); XCTAssertEqual(fresh.phase, .idle)
    }
    func testCurrent401ExpiresMatchingSessionButCancelledRequestDoesNot() async throws {
        for cancel in [false, true] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
            h.wire.delaysOwned = true; let action = try listAction(browser); let task = Task { await browser.load(action: action) }; await h.wire.waitForPending()
            if cancel { task.cancel() }
            h.wire.resume((Data(), 401)); await task.value
            XCTAssertEqual(h.session.isSignedIn, cancel)
            if cancel { XCTAssertEqual(h.vault.token, "synthetic-7") }
            else { XCTAssertNil(h.vault.token); XCTAssertEqual(browser.phase, .invalidated) }
        }
    }
    func testSameOwnerReauthenticationWithNewTokenRetiresOldBrowser() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        await h.session.logout(); h.wire.token = "synthetic-7-new"; await h.login()
        XCTAssertEqual(h.session.account?.id, 7); XCTAssertNil(h.session.workshopPurchasedBrowser)
        XCTAssertEqual(old.phase, .invalidated)
        try h.approve(); let fresh = try XCTUnwrap(h.session.workshopPurchasedBrowser); await fresh.load(action: try listAction(fresh))
        XCTAssertEqual(h.wire.owned.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7-new")
    }
    func testMismatchedOrExpiredApprovalNeverMountsOrDispatches() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        let good = try h.context()
        let variants = try [h.context(account: 8), h.context(role: "merchant"), h.context(token: "other"),
            h.context(epoch: h.session.sessionRevision + 1), h.context(namespace: "other"),
            h.context(base: URL(string: "https://other.example.com/native")!), h.context(market: .unitedStates)]
        for context in variants {
            let grant = try? WorkshopPurchasedReadApproval(context: context, expiresAt: .distantFuture)
            h.session.withWorkshopReadConfigurationChange { h.approval = grant }
            XCTAssertNil(h.session.workshopPurchasedBrowser)
        }
        h.approval = try WorkshopPurchasedReadApproval(context: good, expiresAt: .distantPast)
        XCTAssertNil(h.session.workshopPurchasedBrowser); XCTAssertEqual(h.wire.owned.count, 0)
    }

    func testDefaultOffNormalAccountReadsDoNotEmitObservationChanges() async throws {
        let h = try Harness(); defer { h.clean() }
        for signedIn in [false, true] {
            if signedIn { await h.login() }
            XCTAssertNil(h.session.workshopPurchasedBrowser)
            let changed = expectation(description: "Read-only disabled binding stays unchanged")
            changed.isInverted = true
            _ = withObservationTracking { h.session.workshopPurchasedBrowser } onChange: { changed.fulfill() }
            for _ in 0..<12 { XCTAssertNil(h.session.workshopPurchasedBrowser) }
            await fulfillment(of: [changed], timeout: 0.1)
            XCTAssertEqual(h.wire.owned.count, 0)
        }
    }
    func testRealInvalidationStillPublishesAndSubsequentDisabledReadsStayQuiet() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let original = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        let changed = expectation(description: "Actual permission revocation publishes")
        _ = withObservationTracking { h.session.workshopPurchasedBrowser } onChange: { changed.fulfill() }
        h.session.withWorkshopReadConfigurationChange { h.approval = nil }
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(original.phase, .invalidated); XCTAssertNil(h.session.workshopPurchasedBrowser)
        let repeated = expectation(description: "Repeated disabled reads do not invalidate again")
        repeated.isInverted = true
        _ = withObservationTracking { h.session.workshopPurchasedBrowser } onChange: { repeated.fulfill() }
        for _ in 0..<12 { XCTAssertNil(h.session.workshopPurchasedBrowser) }
        await fulfillment(of: [repeated], timeout: 0.1)
        XCTAssertEqual(h.wire.owned.count, 0)
        try h.approve(); let replacement = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        XCTAssertFalse(original === replacement)
    }

    func testRouteReturnBeforeOldDisappearHasFreshBoxAndCannotBeCancelledByOldPage() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        let navigation = WorkshopPurchasedNavigationState(browser: browser)
        let oldListBox = navigation.listAppearance
        let list = try XCTUnwrap(navigation.listViewAppeared(oldListBox))
        await browser.load(action: list.offer()!)
        navigation.select(licenseId: "w18-paid-11", presentation: list)
        let oldDetailBox = navigation.detailAppearance
        let detail = try XCTUnwrap(navigation.detailViewAppeared(oldDetailBox, licenseId: "w18-paid-11"))
        await browser.open(licenseId: "w18-paid-11", action: detail.offer()!)
        // Back arrives before either departed View received onDisappear.
        navigation.selection = nil
        let newListBox = navigation.listAppearance
        let fresh = try XCTUnwrap(navigation.listViewAppeared(newListBox))
        XCTAssertFalse(newListBox === oldListBox)
        navigation.listViewDisappeared(oldListBox); navigation.detailViewDisappeared(oldDetailBox)
        XCTAssertTrue(navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
        XCTAssertNil(navigation.listViewAppeared(oldListBox))
        await browser.load(action: fresh.offer()!)
        navigation.select(licenseId: "w18-paid-11", presentation: fresh)
        let newDetailBox = navigation.detailAppearance
        let next = try XCTUnwrap(navigation.detailViewAppeared(newDetailBox, licenseId: "w18-paid-11"))
        navigation.detailViewDisappeared(oldDetailBox)
        XCTAssertTrue(navigation.detailPermit === next); XCTAssertTrue(next.isLive)
        XCTAssertNil(navigation.detailViewAppeared(oldDetailBox, licenseId: "w18-paid-11"))
        await browser.open(licenseId: "w18-paid-11", action: next.offer()!)
        XCTAssertEqual(browser.detail?.item.licenseId, "w18-paid-11")
    }
    // Synthetic appearance callbacks issue permits synchronously, outside every queued Task.
    private func listAction(_ browser: WorkshopPurchasedBrowser) throws -> WorkshopPurchasedActionPermit {
        try XCTUnwrap(browser.presentList()?.offer())
    }
    private func detailAction(_ browser: WorkshopPurchasedBrowser) throws -> WorkshopPurchasedActionPermit {
        try XCTUnwrap(browser.presentDetail(licenseId: "w18-paid-11")?.offer())
    }
    func testQueuedListAfterBackAndReopenCannotDispatchOrReplaceFreshRows() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        let navigation = WorkshopPurchasedNavigationState(browser: browser)
        let previous = try XCTUnwrap(navigation.listAppeared())
        let queued = try XCTUnwrap(navigation.offerList(previous))
        navigation.listDisappeared(previous) // Back runs before the already-captured action starts.
        XCTAssertNil(previous.offer()); XCTAssertEqual(h.wire.owned.count, 0)
        XCTAssertTrue(browser === h.session.workshopPurchasedBrowser)
        let reopened = try XCTUnwrap(navigation.listAppeared())
        let current = try XCTUnwrap(navigation.offerList(reopened)); await current()
        XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 1)
        await queued()
        XCTAssertEqual(h.wire.owned.count, 1); XCTAssertEqual(browser.rows.first?.licenseId, "w18-paid-11")
        XCTAssertFalse(browser.rows.first?.permitsContentUse ?? true)
    }
    func testQueuedDetailAfterBackCannotDispatchAndFreshReopenUsesExactClaim() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        let navigation = WorkshopPurchasedNavigationState(browser: browser)
        let list = try XCTUnwrap(navigation.listAppeared())
        let read = try XCTUnwrap(navigation.offerList(list)); await read()
        navigation.select(licenseId: "w18-paid-11", presentation: list)
        let detail = try XCTUnwrap(navigation.detailAppeared(licenseId: "w18-paid-11"))
        let queued = try XCTUnwrap(navigation.offerDetail(detail, licenseId: "w18-paid-11"))
        navigation.selection = nil; XCTAssertNil(detail.offer(), "Back binding synchronously retires queued detail"); navigation.detailDisappeared(detail)
        XCTAssertNil(detail.offer())
        let reopened = try XCTUnwrap(navigation.listAppeared())
        let refresh = try XCTUnwrap(navigation.offerList(reopened)); await refresh(); await queued()
        XCTAssertEqual(h.wire.owned.map { $0.url!.lastPathComponent }, ["list", "list"])
        XCTAssertNil(browser.detail)
        navigation.select(licenseId: "w18-paid-11", presentation: reopened)
        let fresh = try XCTUnwrap(navigation.detailAppeared(licenseId: "w18-paid-11"))
        let open = try XCTUnwrap(navigation.offerDetail(fresh, licenseId: "w18-paid-11")); await open()
        XCTAssertEqual(browser.detail?.item.licenseId, "w18-paid-11")
        XCTAssertEqual(h.wire.owned.last?.httpBody, Data("license_id=w18-paid-11".utf8))
        XCTAssertEqual(h.wire.owned.count, 3)
    }
    func testQueuedReadAcrossRoleOrApprovalABACannotBorrowRestoredAuthority() async throws {
        for roleChange in [true, false] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let old = try XCTUnwrap(h.session.workshopPurchasedBrowser), issued = h.approval
            let navigation = WorkshopPurchasedNavigationState(browser: old)
            let permit = try XCTUnwrap(navigation.listAppeared())
            let queued = try XCTUnwrap(navigation.offerList(permit))
            if roleChange {
                h.wire.role = "merchant"; await h.session.refreshOwnAccount()
                h.wire.role = "player"; await h.session.refreshOwnAccount()
            } else {
                h.session.withWorkshopReadConfigurationChange { h.approval = nil }
                h.session.withWorkshopReadConfigurationChange { h.approval = issued }
            }
            XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(permit.offer())
            let fresh = try XCTUnwrap(h.session.workshopPurchasedBrowser)
            XCTAssertFalse(fresh === old)
            await fresh.load(action: try listAction(fresh)); let before = h.wire.owned.count
            await queued()
            XCTAssertEqual(h.wire.owned.count, before); XCTAssertEqual(fresh.phase, .ready)
            XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.vault.token, "synthetic-7")
        }
    }
    func testNewVisibleOfferRetiresOld401BeforeNewRequestCompletes() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser)
        let navigation = WorkshopPurchasedNavigationState(browser: browser)
        let permit = try XCTUnwrap(navigation.listAppeared())
        let first = try XCTUnwrap(navigation.offerList(permit))
        h.wire.delaysOwned = true; let old = Task { await first() }; await h.wire.waitForPending()
        let replacement = try XCTUnwrap(navigation.offerList(permit)) // synchronously retires old request
        h.wire.resume((Data(), 401)); await old.value
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.vault.token, "synthetic-7")
        h.wire.delaysOwned = false; await replacement()
        XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 2)
    }

    private func wait(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 { if condition() { return }; try await Task.sleep(nanoseconds:20_000_000) }
        XCTAssertTrue(condition()); if !condition() { throw WorkshopPurchasedIssue.unavailable }
    }
    func testNormalHostedPurchasedEntryPreservesCanonicalContextForMerchantAndClubAndBackReopen() async throws {
        for role in ["merchant","club"] {
            let h=try Harness();defer{h.clean()};h.wire.role=role;await h.login();try h.approve();h.strictExpectedContext=try h.context()
            let browser=try XCTUnwrap(h.session.workshopPurchasedBrowser),navigation=WorkshopPurchasedNavigationState(browser:browser)
            XCTAssertNil(h.session.workshopOwnedBrowser,"Paid approval cannot enable FREE library")
            let host=UIHostingController(rootView:NavigationStack{WorkshopPurchasedLibraryView(browser:browser,navigation:navigation)})
            let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible();defer{window.isHidden=true;window.rootViewController=nil}
            try await wait{browser.phase == .ready && navigation.listPermit != nil}
            navigation.select(licenseId:"w18-paid-11",presentation:navigation.listPermit);try await wait{browser.detail != nil && navigation.detailPermit != nil}
            XCTAssertEqual(browser.detail?.item.purchasedVersionId,"synthetic-version");XCTAssertFalse(browser.detail?.item.permitsPurchase ?? true)
            navigation.selection=nil;try await wait{navigation.listPermit != nil && browser.phase == .ready}
            XCTAssertNil(browser.detail);XCTAssertTrue(browser === h.session.workshopPurchasedBrowser)
            XCTAssertGreaterThanOrEqual(h.selectorContexts.count,5);for context in h.selectorContexts.suffix(5){XCTAssertEqual(context,h.strictExpectedContext);XCTAssertEqual(context.session.role,"player")}
        }
    }
    func testInvalidPaginationOfferCannotRetireCurrentVisibleRead() async throws {
        let h=try Harness();defer{h.clean()};await h.login();try h.approve();let browser=try XCTUnwrap(h.session.workshopPurchasedBrowser),navigation=WorkshopPurchasedNavigationState(browser:browser)
        let permit=try XCTUnwrap(navigation.listAppeared()),valid=try XCTUnwrap(navigation.offerList(permit))
        XCTAssertNil(navigation.offerList(permit,before:99));await valid();XCTAssertEqual(browser.phase,.ready);XCTAssertEqual(h.wire.owned.count,1)
    }
    func testLateOldListDisappearCannotCancelNewScheduledTransportRead() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
        let old = try XCTUnwrap(navigation.listAppeared())
        navigation.listDisappeared(old)
        let fresh = try XCTUnwrap(navigation.listAppeared())
        h.wire.delaysOwned = true; navigation.scheduleList(fresh); await h.wire.waitForPending()
        navigation.listDisappeared(old)
        XCTAssertTrue(navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
        XCTAssertEqual(browser.phase, .loading)
        h.wire.resume(Wire.listReply)
        try await wait { browser.phase == .ready }
        XCTAssertEqual(browser.rows.count, 1); XCTAssertEqual(h.wire.owned.count, 1)
    }
    func testLateOldDetailDisappearCannotCancelReopenedSameLicenseRead() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
        let list = try XCTUnwrap(navigation.listAppeared()); await browser.load(action: try XCTUnwrap(list.offer()))
        navigation.select(licenseId: "w18-paid-11", presentation: list)
        let old = try XCTUnwrap(navigation.detailAppeared(licenseId: "w18-paid-11"))
        navigation.selection = nil
        let nextList = try XCTUnwrap(navigation.listAppeared()); await browser.load(action: try XCTUnwrap(nextList.offer()))
        navigation.select(licenseId: "w18-paid-11", presentation: nextList)
        let fresh = try XCTUnwrap(navigation.detailAppeared(licenseId: "w18-paid-11"))
        h.wire.delaysOwned = true; navigation.scheduleDetail(fresh, licenseId: "w18-paid-11"); await h.wire.waitForPending()
        navigation.detailDisappeared(old)
        XCTAssertTrue(navigation.detailPermit === fresh); XCTAssertTrue(fresh.isLive); XCTAssertTrue(browser.detailLoading)
        h.wire.resume(Wire.envelope(WorkshopPurchasedAppFixture.detail()))
        try await wait { browser.detail?.item.id == "w18-paid-11" }
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.wire.owned.count, 3)
    }
    func testRealViewAppearanceBoxCapturesPermitBeforeFirstRedrawAndCannotReappearAfterClose() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
        let appearance = WorkshopPurchasedViewAppearance()
        XCTAssertNil(appearance.permit)
        let permit = try XCTUnwrap(appearance.appear { navigation.listAppeared() })
        let queued = try XCTUnwrap(navigation.offerList(permit))
        appearance.disappear { navigation.listDisappeared($0) }
        XCTAssertNil(navigation.listPermit); XCTAssertFalse(permit.isLive)
        XCTAssertNil(appearance.appear { XCTFail("Closed appearance cannot mint a replacement permit"); return navigation.listAppeared() })
        await queued(); XCTAssertTrue(h.wire.owned.isEmpty)
    }
    func testOldListViewCallbackAfterPushBackAndNewAppearanceKeepsNewRows() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
        let oldView = WorkshopPurchasedViewAppearance(), newView = WorkshopPurchasedViewAppearance()
        let old = try XCTUnwrap(oldView.appear { navigation.listAppeared() })
        await browser.load(action: try XCTUnwrap(old.offer()))
        navigation.select(licenseId: "w18-paid-11", presentation: old); navigation.selection = nil
        let fresh = try XCTUnwrap(newView.appear { navigation.listAppeared() })
        let current = try XCTUnwrap(navigation.offerList(fresh)); await current()
        oldView.disappear { navigation.listDisappeared($0) }
        XCTAssertTrue(navigation.listPermit === fresh); XCTAssertTrue(fresh.isLive)
        XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(browser.rows.count, 1)
    }
    func testOldDetailViewCallbackCannotClearNewAppearanceOrItsOfferedRead() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
        let list = try XCTUnwrap(navigation.listAppeared()); await browser.load(action: try XCTUnwrap(list.offer()))
        navigation.select(licenseId: "w18-paid-11", presentation: list)
        let oldView = WorkshopPurchasedViewAppearance(), newView = WorkshopPurchasedViewAppearance()
        let old = try XCTUnwrap(oldView.appear { navigation.detailAppeared(licenseId: "w18-paid-11") })
        navigation.selection = nil
        let returned = try XCTUnwrap(navigation.listAppeared())
        navigation.select(licenseId: "w18-paid-11", presentation: returned)
        let fresh = try XCTUnwrap(newView.appear { navigation.detailAppeared(licenseId: "w18-paid-11") })
        let queued = try XCTUnwrap(navigation.offerDetail(fresh, licenseId: "w18-paid-11"))
        oldView.disappear { navigation.detailDisappeared($0) }
        XCTAssertFalse(old.isLive); XCTAssertTrue(navigation.detailPermit === fresh); XCTAssertTrue(fresh.isLive)
        await queued(); XCTAssertEqual(browser.detail?.item.id, "w18-paid-11")
    }
    func testCurrentCapturedDisappearStillBlocksLate401ForListAndDetail() async throws {
        for detail in [false, true] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let browser = try XCTUnwrap(h.session.workshopPurchasedBrowser), navigation = WorkshopPurchasedNavigationState(browser: browser)
            let list = try XCTUnwrap(navigation.listAppeared())
            let permit: WorkshopPurchasedPresentationPermit
            if detail {
                await browser.load(action: try XCTUnwrap(list.offer()))
                navigation.select(licenseId: "w18-paid-11", presentation: list)
                permit = try XCTUnwrap(navigation.detailAppeared(licenseId: "w18-paid-11"))
            } else { permit = list }
            h.wire.delaysOwned = true
            if detail { navigation.scheduleDetail(permit, licenseId: "w18-paid-11") } else { navigation.scheduleList(permit) }
            await h.wire.waitForPending()
            if detail { navigation.detailDisappeared(permit) } else { navigation.listDisappeared(permit) }
            h.wire.resume((Data(), 401))
            for _ in 0..<20 { await Task.yield() }
            XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.vault.token, "synthetic-7")
            XCTAssertFalse(permit.isLive); XCTAssertNil(browser.detail)
        }
    }

    @MainActor private final class Harness {
        let wire = Wire(), vault = Vault(), base = URL(string: "https://example.com/native")!
        let suite = "workshop-normal-" + UUID().uuidString
        let deployment: ReviewedAppDeployment
        var approval: WorkshopPurchasedReadApproval?
        var session: AppSession!
        var selectorContexts: [RuntimeDependencyContext] = []
        var strictExpectedContext: RuntimeDependencyContext?
        private func selectApproval(_ context: RuntimeDependencyContext) -> WorkshopPurchasedReadApproval? {
            selectorContexts.append(context)
            if let expected = strictExpectedContext { XCTAssertEqual(context,expected); guard context==expected else{return nil} }
            guard let approval, approval.matches(context) else{return nil};return approval
        }
        init() throws {
            deployment = try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
                verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.workshop.normal", realm: "synthetic")
            session = AppCompositionRoot(deployment: .reviewed(deployment),
                storage: .init(defaults: UserDefaults(suiteName: suite)!, tokenStore: { [vault] _ in vault }),
                makeTransport: { [wire] in wire }, workshopPurchasedReadApproval: { [weak self] context in self?.selectApproval(context) }).makeSession()
        }
        func context(account: Int? = nil, role: String? = nil, token: String? = nil, epoch: UInt64? = nil,
                     namespace: String? = nil, base: URL? = nil, market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
            .init(market: market, baseURL: base ?? self.base, role: role ?? wire.role,
                session: try .init(accountID: account ?? wire.accountID, epoch: epoch ?? session.sessionRevision,
                    namespace: namespace ?? deployment.storageScope.service, token: token ?? wire.token))
        }
        func approve() throws {
            let issued = try WorkshopPurchasedReadApproval(context: context(), expiresAt: .distantFuture)
            session.withWorkshopReadConfigurationChange { approval = issued }
        }
        func login() async { await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
        func clean() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var accountID = 7, role = "player", token = "synthetic-7", delaysOwned = false
        var requests: [URLRequest] = []
        var owned: [URLRequest] { requests.filter { $0.url?.path.contains("/workshop/purchased/") == true } }
        var pending: CheckedContinuation<(Data, Int), Never>?
        func waitForPending() async { for _ in 0..<500 { if pending != nil { return }; await Task.yield() }; XCTFail("synthetic transport did not start") }
        func resume(_ reply: (Data, Int)) { let continuation = pending; pending = nil; continuation?.resume(returning: reply) }
        static let item = WorkshopPurchasedAppFixture.item
        static let header = WorkshopPurchasedAppFixture.header
        static var listReply: (Data, Int) { envelope(WorkshopPurchasedAppFixture.page()) }
        static func envelope(_ data: [String: Any]) -> (Data, Int) { (try! JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.contains("/workshop/purchased/") == true {
                if delaysOwned { return await withCheckedContinuation { pending = $0 } }
                if request.url?.lastPathComponent == "list" { return Self.listReply }
                var detail = Self.header; detail["item"] = Self.item; return Self.envelope(detail)
            }
            let json: String
            switch request.url?.lastPathComponent {
            case "phone": json = "{\"code\":200,\"token\":\"\(token)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}"
            case "userInfo": json = "{\"code\":200,\"appUser\":{\"userId\":\(accountID),\"role\":\"\(role)\"}}"
            case "logout": json = #"{"code":200}"#
            default: throw APIError.invalidRequest
            }
            return (Data(json.utf8), 200)
        }
    }
}
