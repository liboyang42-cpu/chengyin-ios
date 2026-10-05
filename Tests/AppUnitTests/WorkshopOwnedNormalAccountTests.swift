import XCTest
@testable import Questify

@MainActor final class WorkshopOwnedNormalAccountTests: XCTestCase {
    func testNormalRootGuestAndSignedInRemainUnavailableWithoutSeparateApproval() async throws {
        let h = try Harness(); defer { h.clean() }
        XCTAssertNil(h.session.workshopOwnedBrowser)
        await h.login()
        XCTAssertTrue(h.session.isSignedIn); XCTAssertNil(h.session.workshopOwnedBrowser)
        XCTAssertEqual(h.wire.owned.count, 0)
        XCTAssertNil(AppSession(composition: .init()).workshopOwnedBrowser)
    }
    func testApprovedNormalAccountListDetailAndReopenUseOneBrowserAndExactOwnerToken() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopOwnedBrowser)
        XCTAssertTrue(browser === h.session.workshopOwnedBrowser); XCTAssertEqual(h.wire.owned.count, 0)
        await browser.load(action: try listAction(browser)); XCTAssertEqual(browser.phase, .ready)
        await browser.open(claimId: "synthetic-claim", action: try detailAction(browser)); XCTAssertEqual(browser.detail?.item?.claimId, "synthetic-claim")
        XCTAssertEqual(h.wire.owned.map { $0.url!.lastPathComponent }, ["list", "detail"])
        XCTAssertEqual(h.wire.owned[0].httpBody, Data())
        XCTAssertEqual(h.wire.owned[1].httpBody, Data("claim_id=synthetic-claim".utf8))
        XCTAssertTrue(h.wire.owned.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" && WorkshopOwnedReadRoute(request: $0, baseURL: h.base) != nil })
        browser.closeList(); XCTAssertNil(browser.detail); XCTAssertTrue(browser.rows.isEmpty)
        XCTAssertTrue(browser === h.session.workshopOwnedBrowser)
        await browser.load(action: try listAction(browser)); XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 3)
    }
    func testRoleABAInvalidatesBeforeAccountPublishesAndRejectsLateSuccessAndBoth401Forms() async throws {
        for reply in [Wire.listReply, (Data(), 401), (Data(#"{"code":401}"#.utf8), 200)] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let old = try XCTUnwrap(h.session.workshopOwnedBrowser), issued = h.approval
            h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }
            await h.wire.waitForPending()
            h.wire.role = "merchant"; await h.session.refreshOwnAccount()
            XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(h.session.workshopOwnedBrowser)
            h.wire.role = "player"; await h.session.refreshOwnAccount()
            XCTAssertEqual(h.approval?.revision, issued?.revision)
            let replacement = try XCTUnwrap(h.session.workshopOwnedBrowser)
            XCTAssertFalse(replacement === old)
            h.wire.resume(reply); await task.value
            XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.session.account?.effectiveRole, "player")
            XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty); XCTAssertNil(old.detail)
            XCTAssertEqual(replacement.phase, .idle); XCTAssertEqual(h.vault.token, "synthetic-7")
        }
    }
    func testOwnerTokenEpochReplacementAndLogoutCannotBeExpiredByOldResponse() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopOwnedBrowser), epoch = h.session.sessionRevision
        h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }; await h.wire.waitForPending()
        await h.session.logout(); XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(h.session.workshopOwnedBrowser)
        h.wire.accountID = 8; h.wire.token = "synthetic-8"; await h.login(); try h.approve()
        let replacement = try XCTUnwrap(h.session.workshopOwnedBrowser)
        XCTAssertGreaterThan(h.session.sessionRevision, epoch)
        h.wire.resume((Data(), 401)); await task.value
        XCTAssertEqual(h.session.account?.id, 8); XCTAssertEqual(h.vault.token, "synthetic-8")
        XCTAssertEqual(replacement.phase, .idle); XCTAssertEqual(old.phase, .invalidated)
    }
    func testConfigurationABAInvalidatesBeforeMutationAndOld401HasNoSideEffect() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopOwnedBrowser), issued = h.approval
        h.wire.delaysOwned = true; let action = try listAction(old); let task = Task { await old.load(action: action) }; await h.wire.waitForPending()
        h.session.withWorkshopReadConfigurationChange {
            XCTAssertEqual(old.phase, .invalidated); h.approval = nil
        }
        XCTAssertNil(h.session.workshopOwnedBrowser)
        h.session.withWorkshopReadConfigurationChange { h.approval = issued; XCTAssertNil(h.session.workshopOwnedBrowser) }
        let replacement = try XCTUnwrap(h.session.workshopOwnedBrowser)
        XCTAssertFalse(replacement === old)
        h.wire.resume((Data(), 401)); await task.value
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(replacement.phase, .idle)
    }
    func testRootRemovalRetiresLoadedProjectionAndReentryDoesNotResurrectIt() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.workshopOwnedBrowser); await old.load(action: try listAction(old)); await old.open(claimId: "synthetic-claim", action: try detailAction(old))
        h.session.setWorkshopOwnedPresentationActive(false)
        XCTAssertEqual(old.phase, .invalidated); XCTAssertTrue(old.rows.isEmpty); XCTAssertNil(old.detail)
        XCTAssertNil(h.session.workshopOwnedBrowser)
        h.session.setWorkshopOwnedPresentationActive(true)
        let fresh = try XCTUnwrap(h.session.workshopOwnedBrowser)
        XCTAssertFalse(fresh === old); XCTAssertEqual(fresh.phase, .idle)
    }
    func testCurrent401ExpiresMatchingSessionButCancelledRequestDoesNot() async throws {
        for cancel in [false, true] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let browser = try XCTUnwrap(h.session.workshopOwnedBrowser)
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
        let old = try XCTUnwrap(h.session.workshopOwnedBrowser)
        await h.session.logout(); h.wire.token = "synthetic-7-new"; await h.login()
        XCTAssertEqual(h.session.account?.id, 7); XCTAssertNil(h.session.workshopOwnedBrowser)
        XCTAssertEqual(old.phase, .invalidated)
        try h.approve(); let fresh = try XCTUnwrap(h.session.workshopOwnedBrowser); await fresh.load(action: try listAction(fresh))
        XCTAssertEqual(h.wire.owned.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7-new")
    }
    func testMismatchedOrExpiredApprovalNeverMountsOrDispatches() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        let good = try h.context()
        let variants = try [h.context(account: 8), h.context(role: "merchant"), h.context(token: "other"),
            h.context(epoch: h.session.sessionRevision + 1), h.context(namespace: "other"),
            h.context(base: URL(string: "https://other.example.com/native")!), h.context(market: .unitedStates)]
        for context in variants {
            let grant = try? WorkshopOwnedReadApproval(context: context, expiresAt: .distantFuture)
            h.session.withWorkshopReadConfigurationChange { h.approval = grant }
            XCTAssertNil(h.session.workshopOwnedBrowser)
        }
        h.approval = try WorkshopOwnedReadApproval(context: good, expiresAt: .distantPast)
        XCTAssertNil(h.session.workshopOwnedBrowser); XCTAssertEqual(h.wire.owned.count, 0)
    }

    // Synthetic appearance callbacks issue permits synchronously, outside every queued Task.
    private func listAction(_ browser: WorkshopOwnedBrowser) throws -> WorkshopOwnedActionPermit {
        try XCTUnwrap(browser.presentList()?.offer())
    }
    private func detailAction(_ browser: WorkshopOwnedBrowser) throws -> WorkshopOwnedActionPermit {
        try XCTUnwrap(browser.presentDetail(claimId: "synthetic-claim")?.offer())
    }
    func testQueuedListAfterBackAndReopenCannotDispatchOrReplaceFreshRows() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopOwnedBrowser)
        let navigation = WorkshopOwnedNavigationState(browser: browser)
        let previous = try XCTUnwrap(navigation.listAppeared())
        let queued = try XCTUnwrap(navigation.offerList(previous))
        navigation.listDisappeared() // Back runs before the already-captured action starts.
        XCTAssertNil(previous.offer()); XCTAssertEqual(h.wire.owned.count, 0)
        XCTAssertTrue(browser === h.session.workshopOwnedBrowser)
        let reopened = try XCTUnwrap(navigation.listAppeared())
        let current = try XCTUnwrap(navigation.offerList(reopened)); await current()
        XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 1)
        await queued()
        XCTAssertEqual(h.wire.owned.count, 1); XCTAssertEqual(browser.rows.first?.claimId, "synthetic-claim")
        XCTAssertNil(browser.packageBrowser, "Owned metadata approval cannot enable package content")
    }
    func testQueuedDetailAfterBackCannotDispatchAndFreshReopenUsesExactClaim() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopOwnedBrowser)
        let navigation = WorkshopOwnedNavigationState(browser: browser)
        let list = try XCTUnwrap(navigation.listAppeared())
        let read = try XCTUnwrap(navigation.offerList(list)); await read()
        navigation.select(claimId: "synthetic-claim", presentation: list)
        let detail = try XCTUnwrap(navigation.detailAppeared(claimId: "synthetic-claim"))
        let queued = try XCTUnwrap(navigation.offerDetail(detail, claimId: "synthetic-claim"))
        navigation.selection = nil; navigation.detailDisappeared()
        XCTAssertNil(detail.offer())
        let reopened = try XCTUnwrap(navigation.listAppeared())
        let refresh = try XCTUnwrap(navigation.offerList(reopened)); await refresh(); await queued()
        XCTAssertEqual(h.wire.owned.map { $0.url!.lastPathComponent }, ["list", "list"])
        XCTAssertNil(browser.detail)
        navigation.select(claimId: "synthetic-claim", presentation: reopened)
        let fresh = try XCTUnwrap(navigation.detailAppeared(claimId: "synthetic-claim"))
        let open = try XCTUnwrap(navigation.offerDetail(fresh, claimId: "synthetic-claim")); await open()
        XCTAssertEqual(browser.detail?.item?.claimId, "synthetic-claim")
        XCTAssertEqual(h.wire.owned.last?.httpBody, Data("claim_id=synthetic-claim".utf8))
        XCTAssertEqual(h.wire.owned.count, 3)
    }
    func testQueuedReadAcrossRoleOrApprovalABACannotBorrowRestoredAuthority() async throws {
        for roleChange in [true, false] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let old = try XCTUnwrap(h.session.workshopOwnedBrowser), issued = h.approval
            let navigation = WorkshopOwnedNavigationState(browser: old)
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
            let fresh = try XCTUnwrap(h.session.workshopOwnedBrowser)
            XCTAssertFalse(fresh === old)
            await fresh.load(action: try listAction(fresh)); let before = h.wire.owned.count
            await queued()
            XCTAssertEqual(h.wire.owned.count, before); XCTAssertEqual(fresh.phase, .ready)
            XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.vault.token, "synthetic-7")
        }
    }
    func testNewVisibleOfferRetiresOld401BeforeNewRequestCompletes() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let browser = try XCTUnwrap(h.session.workshopOwnedBrowser)
        let navigation = WorkshopOwnedNavigationState(browser: browser)
        let permit = try XCTUnwrap(navigation.listAppeared())
        let first = try XCTUnwrap(navigation.offerList(permit))
        h.wire.delaysOwned = true; let old = Task { await first() }; await h.wire.waitForPending()
        let replacement = try XCTUnwrap(navigation.offerList(permit)) // synchronously retires old request
        h.wire.resume((Data(), 401)); await old.value
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.vault.token, "synthetic-7")
        h.wire.delaysOwned = false; await replacement()
        XCTAssertEqual(browser.phase, .ready); XCTAssertEqual(h.wire.owned.count, 2)
    }

    @MainActor private final class Harness {
        let wire = Wire(), vault = Vault(), base = URL(string: "https://example.com/native")!
        let suite = "workshop-normal-" + UUID().uuidString
        let deployment: ReviewedAppDeployment
        var approval: WorkshopOwnedReadApproval?
        var session: AppSession!
        init() throws {
            deployment = try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
                verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.workshop.normal", realm: "synthetic")
            session = AppCompositionRoot(deployment: .reviewed(deployment),
                storage: .init(defaults: UserDefaults(suiteName: suite)!, tokenStore: { [vault] _ in vault }),
                makeTransport: { [wire] in wire }, workshopOwnedReadApproval: { [weak self] _ in self?.approval }).makeSession()
        }
        func context(account: Int? = nil, role: String? = nil, token: String? = nil, epoch: UInt64? = nil,
                     namespace: String? = nil, base: URL? = nil, market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
            .init(market: market, baseURL: base ?? self.base, role: role ?? wire.role,
                session: try .init(accountID: account ?? wire.accountID, epoch: epoch ?? session.sessionRevision,
                    namespace: namespace ?? deployment.storageScope.service, token: token ?? wire.token))
        }
        func approve() throws {
            let issued = try WorkshopOwnedReadApproval(context: context(), expiresAt: .distantFuture)
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
        var owned: [URLRequest] { requests.filter { $0.url?.path.contains("/workshop/owned/") == true } }
        var pending: CheckedContinuation<(Data, Int), Never>?
        func waitForPending() async { for _ in 0..<500 { if pending != nil { return }; await Task.yield() }; XCTFail("synthetic transport did not start") }
        func resume(_ reply: (Data, Int)) { let continuation = pending; pending = nil; continuation?.resume(returning: reply) }
        static let item: [String: Any] = ["claimId": "synthetic-claim", "acquisition": "FREE", "buyerKind": "INDIVIDUAL",
            "acquiredAt": "2026-10-04T00:00:00Z", "validUntil": "2026-11-04T00:00:00Z", "storedStatus": "ACTIVE", "status": "ACTIVE", "publicationStatus": "LISTED"]
        static let header: [String: Any] = ["schema": "workshop-owned-v1", "scope": "FREE_INDIVIDUAL_ONLY", "availability": "FREE_CLAIMS_ONLY",
            "purchasedLibraryStatus": "NOT_AVAILABLE", "contentUseStatus": "UNAVAILABLE", "checkedAt": "2026-10-05T00:00:00Z"]
        static var listReply: (Data, Int) { var data = header; data["items"] = [item]; data["hasMore"] = false; return envelope(data) }
        static func envelope(_ data: [String: Any]) -> (Data, Int) { (try! JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.contains("/workshop/owned/") == true {
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
