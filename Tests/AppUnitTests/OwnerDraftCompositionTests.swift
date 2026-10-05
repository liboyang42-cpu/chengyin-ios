import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class OwnerDraftCompositionTests: XCTestCase {
    private func signIn(_ session: AppSession, recorder: OwnerDraftFixtureTransport, expectSuccess: Bool = true,
                        file: StaticString = #filePath, line: UInt = #line) async {
        session.authChannels.cancel()
        let before = recorder.requests.count
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        guard expectSuccess else { return }
        XCTAssertNotNil(session.account, "Synthetic login must succeed before feature assertions", file: file, line: line)
        XCTAssertTrue(session.authChannels.state.signedIn, file: file, line: line)
        XCTAssertEqual(recorder.requests.dropFirst(before).map { $0.url?.path },
            ["/native/api/login/phone", "/native/api/userInfo"], file: file, line: line)
    }
    private func deployment(realm: String = "synthetic") throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: "https://draft-browser.example/native",
            approvedBaseURLs: [.china: ["https://draft-browser.example/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.questify.owner-draft", realm: realm)
    }
    private func approval(_ deployment: ReviewedAppDeployment, epoch: UInt64 = 1) throws -> OwnerDraftReadApproval {
        let context = RuntimeDependencyContext(market: .china, baseURL: try XCTUnwrap(deployment.regional.apiConfiguration).baseURL, role: "player",
            session: try .init(accountID: 7, epoch: epoch, namespace: deployment.storageScope.service, token: "synthetic-7"))
        return try .init(grant: .init(context: context, ownerMemberID: 7, scope: .personal,
                                     routes: [.list, .restore], expiresAt: .distantFuture))
    }
    private func root(_ recorder: OwnerDraftFixtureTransport, enabled: Bool = true,
                      grantDeployment: ReviewedAppDeployment? = nil) throws -> AppCompositionRoot {
        let deployment = try deployment(), approved = try approval(grantDeployment ?? deployment)
        let suite = "owner-draft-app-" + UUID().uuidString, vault = OwnerDraftFixtureVault()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { recorder }, ownerDraftReadApproval: { _ in enabled ? approved : nil })
    }
    func testNormalAccountEntryUsesSameSessionBrowserAndExactOwnerReads() async throws {
        let recorder = OwnerDraftFixtureTransport(mode: "ready"), session = try root(recorder).makeSession()
        await signIn(session, recorder: recorder)
        XCTAssertEqual(recorder.requests.prefix(2).map { $0.url?.lastPathComponent }, ["phone", "userInfo"])
        let browser = try XCTUnwrap(session.ownerDraftBrowser)
        XCTAssertTrue(browser === session.ownerDraftBrowser)
        let account = try XCTUnwrap(session.account)
        let host = UIHostingController(rootView: AccountView(account: account).environmentObject(session))
        host.loadViewIfNeeded()
        let link = OwnerDraftAccountLink(browser: session.ownerDraftBrowser); _ = link.body
        await browser.load(); await browser.restore(id: 11)
        XCTAssertEqual(browser.rows.count, 2); XCTAssertEqual(browser.detail?.id, 11)
        let requests = recorder.requests.filter { $0.url?.path.contains("content-draft") == true }
        XCTAssertEqual(requests.map(\.httpBody), [Data("scope=".utf8), Data("draft_id=11&scope=".utf8)])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
        XCTAssertEqual(recorder.mutationCalls, 0)
    }
    func testGuestUnconfiguredAndAuthenticatedNoGrantMakeZeroDraftCalls() async throws {
        let recorder = OwnerDraftFixtureTransport(mode: "ready"), session = try root(recorder, enabled: false).makeSession()
        XCTAssertNil(session.ownerDraftBrowser); _ = OwnerDraftGuestView().body
        await signIn(session, recorder: recorder)
        XCTAssertNil(session.ownerDraftBrowser); _ = OwnerDraftDestination(browser: nil).body
        XCTAssertEqual(recorder.listCalls, 0); XCTAssertEqual(recorder.restoreCalls, 0)
    }
    func testWrongRealmApprovalCannotActivateOwnerBrowser() async throws {
        let r = OwnerDraftFixtureTransport(mode: "ready"), session = try root(r, grantDeployment: deployment(realm: "other")).makeSession()
        await signIn(session, recorder: r); XCTAssertNil(session.ownerDraftBrowser); XCTAssertEqual(r.listCalls, 0)
    }
    func testRoleABASynchronouslyRevokesOldBrowserWithSameLoginEpoch() async throws {
        let r = OwnerDraftFixtureTransport(mode: "ready"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let original = try XCTUnwrap(session.ownerDraftBrowser)
        await original.load(); let revision = session.sessionRevision
        r.role = "merchant"; await session.refreshOwnAccount()
        XCTAssertEqual(original.phase, .invalidated); XCTAssertTrue(original.rows.isEmpty); XCTAssertNil(session.ownerDraftBrowser)
        r.role = "player"; await session.refreshOwnAccount()
        XCTAssertEqual(session.sessionRevision, revision)
        let replacement = try XCTUnwrap(session.ownerDraftBrowser); XCTAssertFalse(original === replacement)
        let count = r.listCalls; await original.load(); XCTAssertEqual(r.listCalls, count)
        await replacement.load(); XCTAssertEqual(replacement.rows.count, 2)
    }
    func testRootLifetimeABAClearsDetailAndCannotRebuildWhileInactive() async throws {
        let r = OwnerDraftFixtureTransport(mode: "ready"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let old = try XCTUnwrap(session.ownerDraftBrowser)
        await old.load(); await old.restore(id: 11)
        session.setOwnerDraftPresentationActive(false)
        XCTAssertNil(old.detail); XCTAssertTrue(old.rows.isEmpty); XCTAssertNil(session.ownerDraftBrowser)
        session.setOwnerDraftPresentationActive(true)
        let fresh = try XCTUnwrap(session.ownerDraftBrowser); XCTAssertFalse(old === fresh)
        await fresh.load(); XCTAssertEqual(fresh.phase, .ready)
    }
    func testLate401AfterLogoutCannotExpireNewLogin() async throws {
        let r = OwnerDraftFixtureTransport(mode: "loading"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let old = try XCTUnwrap(session.ownerDraftBrowser)
        let started = expectation(description: "read suspended"); r.onPaused = { started.fulfill() }
        let task = Task { await old.load() }; await fulfillment(of: [started], timeout: 2)
        await session.logout(); await signIn(session, recorder: r)
        let revision = session.sessionRevision
        try r.release(code: 401); await task.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.sessionRevision, revision)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty)
    }
    func testLateSuccessAfterRoleABACannotPopulateOldRows() async throws {
        let r = OwnerDraftFixtureTransport(mode: "loading"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let old = try XCTUnwrap(session.ownerDraftBrowser)
        let started = expectation(description: "read suspended"); r.onPaused = { started.fulfill() }
        let task = Task { await old.load() }; await fulfillment(of: [started], timeout: 2)
        r.role = "merchant"; await session.refreshOwnAccount(); r.role = "player"; await session.refreshOwnAccount()
        try r.release(); await task.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty)
    }
    func testCurrent401ExpiresOnlyMatchingSessionAndClearsDisplay() async throws {
        let r = OwnerDraftFixtureTransport(mode: "unauthorized"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let browser = try XCTUnwrap(session.ownerDraftBrowser)
        await browser.load(); XCTAssertNil(session.account); XCTAssertEqual(browser.phase, .invalidated)
    }
    func testTransportRejectsWritesPaginationDuplicateFieldsAndForeignScope() async throws {
        let r = OwnerDraftFixtureTransport(mode: "ready"), root = try self.root(r), transport = root.transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        for (path, body) in [("save", "scope="), ("delete", "scope="), ("publish", "scope="), ("list", "scope=&page=1"),
                            ("list", "scope=MERCHANT"), ("list", "scope=&scope="), ("restore", "draft_id=01&scope="),
                            ("restore", "draft_id=11&scope=&ownerMemberId=8")] {
            var request = URLRequest(url: URL(string: "https://draft-browser.example/native/api/content-draft/\(path)")!)
            request.httpMethod = "POST"; request.httpBody = Data(body.utf8)
            request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            do { _ = try await transport.send(request); XCTFail("Accepted \(path): \(body)") } catch {}
        }
        XCTAssertTrue(r.requests.isEmpty)
    }
    func testRevokedApprovalDropsLateReadBefore401CanEscapeTransport() async throws {
        let r = OwnerDraftFixtureTransport(mode: "loading"), deployment = try deployment()
        let approved = try approval(deployment); var enabled = true
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: r,
            ownerDraftReadApproval: { _ in enabled ? approved : nil })
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        var request = URLRequest(url: URL(string: "https://draft-browser.example/native/api/content-draft/list")!)
        request.httpMethod = "POST"; request.httpBody = Data("scope=".utf8)
        request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let started = expectation(description: "approval read suspended"); r.onPaused = { started.fulfill() }
        let task = Task { try await transport.send(request) }; await fulfillment(of: [started], timeout: 2)
        enabled = false; try r.release(code: 401)
        do { _ = try await task.value; XCTFail("Revoked read escaped") } catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }
    func testCompositionIdentityUsesRoleBytesAndRevisionForABA() {
        let a = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "caf\u{00e9}", token: "synthetic", viewerRevision: 1)
        let b = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "cafe\u{0301}", token: "synthetic", viewerRevision: 1)
        let later = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "caf\u{00e9}", token: "synthetic", viewerRevision: 3)
        XCTAssertNotEqual(a, b); XCTAssertNotEqual(a, later)
    }
    func testShippingCompositionHasNoOwnerReadApproval() throws {
        let deployment = try deployment(), context = try approval(deployment).grant.context
        XCTAssertNil(AppCompositionRoot().ownerDraftReadApproval(context))
    }
    func testReceiptSummaryTravelsThroughExactOwnerRestoreWithoutMutations() async throws {
        let r = OwnerDraftFixtureTransport(mode: "receipts-stale"), session = try root(r).makeSession()
        await signIn(session, recorder: r)
        let browser = try XCTUnwrap(session.ownerDraftBrowser)
        await browser.load(); XCTAssertTrue(browser.rows.allSatisfy { $0.installedReceipts == nil })
        await browser.restore(id: 11)
        let summary = try XCTUnwrap(browser.detail?.installedReceipts)
        XCTAssertEqual(summary.state, .historical); XCTAssertEqual(summary.rows.first?.binding, .stale)
        _ = OwnerDraftReceiptSummaryView(summary: summary).body
        let request = try XCTUnwrap(r.requests.last)
        XCTAssertEqual(request.httpBody, Data("draft_id=11&scope=".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        XCTAssertEqual(r.mutationCalls, 0)
    }
    func testReceiptAvailabilityVariantsRemainDistinctInComposition() async throws {
        for (mode, state) in [("ready", OwnerDraftInstalledReceipts.State.omitted),
            ("receipts-empty", .historical), ("receipts-notEnabled", .notEnabled),
            ("receipts-ownerOnly", .ownerOnly), ("receipts-invalid", .invalid), ("receipts-unverifiable", .historical)] {
            let r = OwnerDraftFixtureTransport(mode: mode), session = try root(r).makeSession()
            await signIn(session, recorder: r); let browser = try XCTUnwrap(session.ownerDraftBrowser)
            await browser.load(); await browser.restore(id: 11)
            XCTAssertEqual(browser.detail?.installedReceipts?.state, state, mode)
            XCTAssertEqual(r.mutationCalls, 0)
        }
    }
    func testLateReceiptRestoreAfterRoleABACannotRepopulateOldBrowser() async throws {
        let r = OwnerDraftFixtureTransport(mode: "receipts-stale"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let browser = try XCTUnwrap(session.ownerDraftBrowser)
        await browser.load(); r.pauseRestore = true
        let started = expectation(description: "receipt restore suspended"); r.onPaused = { started.fulfill() }
        let task = Task { await browser.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
        r.role = "merchant"; await session.refreshOwnAccount(); r.role = "player"; await session.refreshOwnAccount()
        r.releaseRestore(); await task.value
        XCTAssertEqual(browser.phase, .invalidated); XCTAssertNil(browser.detail)
        XCTAssertEqual(r.mutationCalls, 0)
    }
    func testReceiptRestoreCancellationAndBackCannotRetainDisplay() async throws {
        for cancel in [false, true] {
            let r = OwnerDraftFixtureTransport(mode: "receipts-stale"), session = try root(r).makeSession()
            await signIn(session, recorder: r); let browser = try XCTUnwrap(session.ownerDraftBrowser)
            await browser.load(); r.pauseRestore = true
            let started = expectation(description: "receipt cancellation"); r.onPaused = { started.fulfill() }
            let task = Task { await browser.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
            if cancel { task.cancel() } else { browser.closeDetail() }
            r.releaseRestore(); await task.value
            XCTAssertNil(browser.detail); XCTAssertFalse(browser.detailLoading); XCTAssertEqual(r.mutationCalls, 0)
        }
    }

    func testLateReceiptAfterLogoutAndSameAccountReloginCannotReachNewSession() async throws {
        let r = OwnerDraftFixtureTransport(mode: "receipts-stale"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let old = try XCTUnwrap(session.ownerDraftBrowser)
        await old.load(); r.pauseRestore = true
        let started = expectation(description: "old session receipt"); r.onPaused = { started.fulfill() }
        let task = Task { await old.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
        await session.logout(); await signIn(session, recorder: r)
        let revision = session.sessionRevision
        r.releaseRestore(); await task.value
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.sessionRevision, revision)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.detail)
        // The one-epoch fixture approval cannot authorize the new login.
        XCTAssertNil(session.ownerDraftBrowser); XCTAssertEqual(r.mutationCalls, 0)
    }
    func testRootLifetimeReplacementKeepsFreshReceiptStateAfterLateOldRestore() async throws {
        let r = OwnerDraftFixtureTransport(mode: "receipts-stale"), session = try root(r).makeSession()
        await signIn(session, recorder: r); let old = try XCTUnwrap(session.ownerDraftBrowser)
        await old.load(); r.pauseRestore = true
        let started = expectation(description: "retired root receipt"); r.onPaused = { started.fulfill() }
        let task = Task { await old.restore(id: 11) }; await fulfillment(of: [started], timeout: 2)
        session.setOwnerDraftPresentationActive(false); session.setOwnerDraftPresentationActive(true)
        let fresh = try XCTUnwrap(session.ownerDraftBrowser); XCTAssertFalse(old === fresh)
        r.pauseRestore = false; r.mode = "receipts-empty"
        await fresh.load(); await fresh.restore(id: 11)
        r.releaseRestore(); await task.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.detail)
        XCTAssertEqual(fresh.detail?.installedReceipts?.state, .historical)
        XCTAssertTrue(try XCTUnwrap(fresh.detail?.installedReceipts?.rows).isEmpty)
        XCTAssertEqual(r.mutationCalls, 0)
    }

}
