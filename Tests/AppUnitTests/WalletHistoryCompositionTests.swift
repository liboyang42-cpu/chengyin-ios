import XCTest
@testable import Questify

/// Real AppSession factories and the outer transport, with synthetic HTTP only.
@MainActor final class WalletHistoryCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func root(_ wire: Wire, _ grants: Grants, _ vault: Vault, invite: InviteGrants? = nil) throws -> AppCompositionRoot {
        let suite = "wallet-history-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.wallet-history", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, walletHistoryReadApproval: { grants.select($0) },
            profileInviteHistoryReadAccess: { invite?.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testIncomeDetailUsesNormalReadLeaseAndRetiresWhenRevokedOrRoleChanges() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession()
        await login(session); wire.requests = []
        let reader = session.walletHistoryReader, pager = WalletLedgerPager()
        await pager.load(reader: reader, kind: .income(.all))
        let selection = try XCTUnwrap(pager.incomeDetail(rowID: 61, reader: reader))
        let count = wire.requests.count
        XCTAssertEqual(pager.incomeDetailRow(selection, reader: reader)?.id, 61)
        XCTAssertEqual(wire.requests.count, count) // Detail is an existing server row, never a write or guessed endpoint.
        grants.retained?.revoke()
        XCTAssertNil(pager.incomeDetailRow(selection, reader: reader))
        grants.retained = nil
        let fresh = session.walletHistoryReader
        XCTAssertNil(pager.incomeDetailRow(selection, reader: fresh))
        let beforeFreshRead = wire.requests.count
        await pager.load(reader: fresh, kind: .income(.all))
        XCTAssertEqual(wire.requests.count, beforeFreshRead + 1)
        let second = try XCTUnwrap(pager.incomeDetail(rowID: 61, reader: fresh))
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNil(pager.incomeDetailRow(second, reader: fresh))
    }

    func testWalletInvitationEntryUsesIndependentReaderWithoutLoading() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession()
        await login(session); wire.requests = []
        let access = WalletInvitationHistoryAccess(session: session)
        XCTAssertEqual(access.reader.identity, session.profileInviteHistoryReader.identity)
        XCTAssertFalse(access.reader.isConfigured) // Wallet approval does not grant invitation reads.
        XCTAssertTrue(wire.requests.isEmpty)
        do {
            _ = try await access.reader.invitationHistory(page: 1)
            XCTFail("Missing invitation approval must not use wallet authority")
        } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testWalletInvitationEntrySignedOutDoesNotIssueRequests() throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession()
        let access = WalletInvitationHistoryAccess(session: session)
        XCTAssertNil(access.reader.identity.accountID)
        XCTAssertFalse(access.reader.isConfigured)
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testWalletInvitationEntryLoadsExistingMonthAndRewardProjection() async throws {
        let wire = Wire(), grants = Grants(), invite = InviteGrants()
        let session = try root(wire, grants, Vault(), invite: invite).makeSession()
        await login(session); wire.requests = []
        let access = WalletInvitationHistoryAccess(session: session)
        XCTAssertTrue(wire.requests.isEmpty)
        let model = SocialInviteHistoryModel()
        await model.appear(access.reader)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [201])
        XCTAssertEqual(model.timeline(access.reader)?.months.map(\.id), ["2026-10"])
        XCTAssertEqual(ProfileInviteRewardReview(scan: model.scan).cumulativePoints, Decimal(string: "2.5"))
        XCTAssertEqual(wire.requests.compactMap { $0.url?.lastPathComponent }, ["invite_list", "list"])
        model.suspend()
        await model.appear(access.reader)?.value
        XCTAssertEqual(model.pagination.members.map(\.id), [201])
        XCTAssertEqual(wire.requests.count, 4)
    }

    func testWalletInvitationGrantDoesNotBorrowWalletLeaseAndRevocationHidesResults() async throws {
        let wire = Wire(), grants = Grants(), invite = InviteGrants()
        let session = try root(wire, grants, Vault(), invite: invite).makeSession()
        await login(session)
        _ = session.walletHistoryReader.isConfigured
        let access = WalletInvitationHistoryAccess(session: session), model = SocialInviteHistoryModel()
        grants.retained?.revoke(); grants.enabled = false
        XCTAssertTrue(access.reader.isConfigured)
        await model.appear(access.reader)?.value
        XCTAssertNotNil(model.timeline(access.reader))
        invite.retained?.revoke()
        XCTAssertFalse(access.reader.isConfigured)
        XCTAssertNil(model.timeline(access.reader))
        wire.requests = []
        do { _ = try await access.reader.invitationHistory(page: 1); XCTFail() } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testNormalFactoryReadsOnlyVisibleHistoryRoutes() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session); wire.requests = []
        let reader = session.walletHistoryReader
        _ = try await reader.read { try await $0.stages(token: $1) }
        _ = try await reader.read { try await $0.ledger(.balance, token: $1) }
        _ = try await reader.read { try await $0.ledger(.assetPoints, token: $1) }
        let income = try await reader.read { try await $0.ledger(.income(.create), page: 2, token: $1) }
        XCTAssertEqual(income.rows.map(\.id), [61]); XCTAssertEqual(income.page, 2)
        _ = try await reader.read { try await $0.withdrawals(token: $1) }
        _ = try await reader.read { try await $0.withdrawalBalance(memberID: 7, token: $1) }
        XCTAssertEqual(Set(wire.requests.compactMap { WalletHistoryReadRoute(request: $0, baseURL: base, accountID: 7)?.path }), WalletHistoryReadRoute.paths)
        let count = wire.requests.count
        do { _ = try await reader.read { try await $0.withdrawalBalance(memberID: 8, token: $1) }; XCTFail() } catch {}
        do { _ = try await reader.read { try await $0.pointsTasks(token: $1) }; XCTFail() } catch {}
        do { _ = try await reader.read { try await $0.ledger(.points, token: $1) }; XCTFail() } catch {}
        do { _ = try await reader.read { try await $0.products(token: $1) }; XCTFail() } catch {}
        do { _ = try await reader.checkout(cartIDs: [1]); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, count)
    }
    func testDefaultNilAndInnerApprovalCannotBypassOuterFence() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let composition = try root(wire, grants, Vault()), session = composition.makeSession()
        do { _ = try await session.walletHistoryReader.read { try await $0.stages(token: $1) }; XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty); await login(session); wire.requests = []
        XCTAssertFalse(session.walletHistoryReader.isConfigured)
        let inner = try OperationEndpointApproval(baseURL: base, namespace: XCTUnwrap(composition.reviewed?.storageScope.service), accountID: 7, paths: WalletHistoryReadRoute.paths)
        do { _ = try await session.makeWalletCommerceReader(readApproval: inner).read { try await $0.stages(token: $1) }; XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testLoadedReaderDoesNotAdoptReplacementLeaseOrRoleABA() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let old = session.walletHistoryReader, pager = WalletLedgerPager()
        await pager.load(reader: old, kind: .income(.all)); XCTAssertEqual(pager.rows.count, 1)
        let identity = session.walletHistoryViewIdentity, durableScope = session.walletCommerceScope
        let bankReader = session.walletCommerceReader, bankReaderScope = bankReader.scope
        grants.retained?.revoke(); grants.enabled = false
        XCTAssertNil(old.scope); XCTAssertNotEqual(identity, session.walletHistoryViewIdentity)
        await pager.load(reader: old, kind: .income(.all)); XCTAssertTrue(pager.rows.isEmpty)
        grants.retained = nil; grants.enabled = true
        XCTAssertNil(old.scope); let fresh = session.walletHistoryReader
        XCTAssertNotNil(fresh.scope); XCTAssertEqual(session.walletCommerceScope, durableScope)
        XCTAssertTrue(bankReader === session.walletCommerceReader); XCTAssertEqual(bankReader.scope, bankReaderScope)
        await pager.load(reader: fresh, kind: .income(.all)); XCTAssertEqual(pager.rows.count, 1)
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNil(fresh.scope); XCTAssertNotEqual(fresh.scope, session.walletHistoryReader.scope)
        XCTAssertEqual(session.walletCommerceScope, durableScope)
        XCTAssertTrue(bankReader === session.walletCommerceReader); XCTAssertEqual(bankReader.scope, bankReaderScope)
    }
    func testLateResultsAndErrorsCannotSurviveContextOrLeaseChanges() async throws {
        for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "cancel"] {
            for code in [200, 401, -1] {
                let wire = Wire(), grants = Grants(), vault = Vault(), session = try root(wire, grants, vault).makeSession(); await login(session)
                let reader = session.walletHistoryReader, paused = expectation(description: "history suspended")
                wire.pause = true; wire.onPaused = { paused.fulfill() }
                let task = Task { try await reader.read { try await $0.ledger(.income(.all), token: $1) } }
                await fulfillment(of: [paused], timeout: 2)
                switch transition {
                case "owner": await session.logout(); wire.account = 8; await login(session)
                case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                case "sessionABA": await session.logout(); await login(session)
                case "revoke": grants.retained?.revoke(); grants.enabled = false
                case "reissue": grants.retained?.revoke(); grants.retained = nil; _ = session.walletHistoryViewIdentity
                case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
                default: task.cancel()
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError || error as? WalletCommerceSafetyError == .staleSession) }
                XCTAssertEqual(session.account?.id, wire.account); XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
            }
        }
    }
    func testCurrent401ExpiresSessionAndUnknownJournalSurvives() async throws {
        let wire = Wire(), grants = Grants(), vault = Vault(), composition = try root(wire, grants, vault), session = composition.makeSession(); await login(session)
        let scope = try XCTUnwrap(session.walletCommerceScope), journal = composition.storage.operationJournal()
        let owner = "wallet:\(scope.namespace.utf8.count):\(scope.namespace):\(scope.accountID)"
        let record = OperationPendingRecord(ownerKey: owner, targetKey: "cart-and-redemption"); try journal.write(record)
        wire.code = 401
        do { _ = try await session.walletHistoryReader.read { try await $0.stages(token: $1) }; XCTFail() } catch {}
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: "cart-and-redemption"), record)
    }
    func testExactShapesClonesOwnerScopeAndMutationDenial() async throws {
        let wire = Wire(), grants = Grants(), transport = try root(wire, grants, Vault()).transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        let clone = transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(form("api/user/balance/list", ["pageNum":"1", "pageSize":"20"]))
        var invalid = [URLRequest]()
        for path in ["api/wallet/withdraw", "api/withdrawal/create", "api/withdrawal/delete", "api/cart/order/settlement", "api/cart/add", "api/cart/cart/add", "api/cart/update", "api/cart/delete", "api/cart/settlement", "api/product/list", "api/points/result_list", "api/user/points/list", "api/payment/create", "api/refund/create", "api/transfer/create"] { invalid.append(try form(path, [:])) }
        for fields in [["pageNum":"0","pageSize":"20"], ["pageNum":"10001","pageSize":"20"], ["pageNum":"01","pageSize":"20"], ["pageNum":"1","pageSize":"200"], ["pageNum":"1","pageSize":"20","member_id":"8"], ["pageNum":"1","pageSize":"20","eventType":"3"]] { invalid.append(try form("api/user/balance/list", fields)) }
        invalid.append(try form("api/user/info", ["member_id":"8"]))
        let valid = try form("api/user/balance/list", ["pageNum":"1", "pageSize":"20"])
        for url in ["https://evil.test/native/api/user/balance/list", "https://example.test/other/api/user/balance/list", "https://example.test/native/api/user/balance/list?x=1", "https://example.test/native/api/user/balance/list#x", "https://example.test/native/api/user/%62alance/list", "https://example.test/native/api/user/../user/balance/list"] { var request = valid; request.url = URL(string: url); invalid.append(request) }
        var request = valid; request.httpMethod = "GET"; invalid.append(request)
        request = valid; request.httpBody?.append(Data("extra".utf8)); invalid.append(request)
        request = valid; request.setValue("other", forHTTPHeaderField: "Authorization"); invalid.append(request)
        let count = wire.requests.count
        for request in invalid { do { _ = try await clone.send(request); XCTFail() } catch {} }
        grants.freeze = true
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"), .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"), .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"), .init(epoch: 1, accountID: nil, role: nil, token: nil)] {
            transport.current = { identity }; do { _ = try await clone.send(valid); XCTFail() } catch {}
        }
        XCTAssertEqual(wire.requests.count, count)
    }
    func testClonedTransportRejectsLateLeaseChangesAndTokenRotation() async throws {
        for transition in ["revoke", "replace", "expiry", "token", "roleABA"] {
            for code in [200, -1] {
                let wire = Wire(), grants = Grants(), root = try root(wire, grants, Vault()).transport()
                root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
                let clone = root.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
                wire.pause = true; let paused = expectation(description: "clone suspended"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await clone.send(form("api/user/balance/list", ["pageNum":"1", "pageSize":"20"])) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.retained)
                switch transition {
                case "revoke": lease.revoke()
                case "replace": grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "expiry": lease.expireIfNeeded(now: lease.expiresAt)
                case "token": root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "rotated", viewerRevision: 1) }
                default: root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3) }
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            }
        }
    }
    func testUnavailableTaskBoundaryDoesNotTurnTransportOrBusinessErrorsIntoUnavailable() {
        XCTAssertTrue(WalletReadFailurePresentation.isUnavailable(APIError.notConfigured))
        XCTAssertTrue(WalletReadFailurePresentation.isUnavailable(WalletCommerceSafetyError.unavailable))
        XCTAssertFalse(WalletReadFailurePresentation.isUnavailable(APIError.httpStatus(503)))
        XCTAssertFalse(WalletReadFailurePresentation.isUnavailable(APIError.businessCode(409)))
        XCTAssertFalse(WalletReadFailurePresentation.isUnavailable(APIError.unauthorized))
        XCTAssertFalse(WalletReadFailurePresentation.isUnavailable(CancellationError()))
    }
    func testAssetScreenLoadingThenResultUsesCurrentScope() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletFundsStages>()
        wire.pause = true; let paused = expectation(description: "asset read suspended"); wire.onPaused = { paused.fulfill() }
        let task = Task { await screen.load(reader) { try await $0.stages(token: $1) } }
        await fulfillment(of: [paused], timeout: 2)
        XCTAssertTrue(screen.loading); XCTAssertNil(screen.value); XCTAssertFalse(screen.failed)
        wire.finish(code: 200); await task.value
        XCTAssertFalse(screen.loading); XCTAssertFalse(screen.failed)
        XCTAssertEqual(screen.value?.withdrawable.value, 3); XCTAssertEqual(screen.loadedScope, reader.scope)
    }
    func testAssetScreenDistinguishesDeniedAndTransientThenRecovers() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletFundsStages>()
        await screen.load(reader) { _, _ in throw APIError.notConfigured }
        XCTAssertTrue(reader.isConfigured); XCTAssertTrue(screen.failed); XCTAssertTrue(screen.unavailable)
        XCTAssertFalse(screen.requiresLogin); XCTAssertNil(screen.value)
        await screen.load(reader) { _, _ in throw APIError.httpStatus(503) }
        XCTAssertTrue(screen.failed); XCTAssertFalse(screen.unavailable); XCTAssertFalse(screen.requiresLogin)
        await screen.load(reader) { try await $0.stages(token: $1) }
        XCTAssertFalse(screen.failed); XCTAssertFalse(screen.unavailable); XCTAssertNotNil(screen.value)
    }
    func testAssetScreenCancelledLateResultCannotOverwriteReopenedRead() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletFundsStages>()
        wire.pause = true; let paused = expectation(description: "old asset read"); wire.onPaused = { paused.fulfill() }
        let old = Task { await screen.load(reader) { try await $0.stages(token: $1) } }
        await fulfillment(of: [paused], timeout: 2)
        screen.cancel(); screen.clear(); wire.pause = false
        await screen.load(reader) { _, _ in throw APIError.httpStatus(503) }
        wire.finish(code: 200); await old.value
        XCTAssertNil(screen.value); XCTAssertTrue(screen.failed); XCTAssertFalse(screen.loading)
        await screen.load(reader) { try await $0.stages(token: $1) }
        XCTAssertNotNil(screen.value); XCTAssertFalse(screen.failed)
    }
    func testAssetScreenNewestRefreshWinsOverNonCooperativeOlderRead() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletFundsStages>()
        wire.pause = true; let paused = expectation(description: "older refresh"); wire.onPaused = { paused.fulfill() }
        let old = Task { await screen.load(reader) { try await $0.stages(token: $1) } }
        await fulfillment(of: [paused], timeout: 2)
        wire.pause = false; await screen.load(reader) { _, _ in throw APIError.notConfigured }
        wire.finish(code: 200); await old.value
        XCTAssertNil(screen.value); XCTAssertTrue(screen.unavailable); XCTAssertFalse(screen.loading)
    }
    func testAssetScreenScopeSwitchCannotRefillOldResult() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletFundsStages>()
        wire.pause = true; let paused = expectation(description: "old scope read"); wire.onPaused = { paused.fulfill() }
        let old = Task { await screen.load(reader) { try await $0.stages(token: $1) } }
        await fulfillment(of: [paused], timeout: 2)
        grants.retained?.revoke(); grants.enabled = false; screen.clear()
        XCTAssertNil(reader.scope)
        wire.finish(code: 200); await old.value
        XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope); XCTAssertFalse(screen.loading)
    }
    func testWithdrawalScreenDenialAnd401AreNotEmptySuccess() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<WalletPage<WalletWithdrawalRecord>>()
        await screen.load(reader) { _, _ in throw APIError.notConfigured }
        XCTAssertTrue(screen.unavailable); XCTAssertFalse(screen.requiresLogin)
        XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope); XCTAssertFalse(screen.loading)
        // Use a reader without session teardown to prove the presentation flag itself.
        let active = try XCTUnwrap(reader.scope)
        let isolated = WalletCommerceReader(service: WalletCommerceService(configuration: try APIConfiguration(baseURL: base), transport: wire)) { (active, "synthetic") }
        await screen.load(isolated) { _, _ in throw APIError.unauthorized }
        XCTAssertTrue(screen.requiresLogin); XCTAssertFalse(screen.unavailable)
        XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope); XCTAssertFalse(screen.loading)
        await screen.load(isolated) { try await $0.withdrawals(token: $1) }
        XCTAssertFalse(screen.failed); XCTAssertEqual(screen.value?.rows.count, 0)
        XCTAssertEqual(screen.loadedScope, active)
    }
    func testScreenTaskCancellationRejectsNonCooperatingLateSuccess() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<Int>()
        let started = expectation(description: "screen operation suspended")
        var pending: CheckedContinuation<Int, Never>?
        let task = Task { await screen.load(reader) { _, _ in
            await withCheckedContinuation { pending = $0; started.fulfill() }
        } }
        await fulfillment(of: [started], timeout: 2)
        task.cancel() // No screen.cancel(): exercise structured task cancellation.
        pending?.resume(returning: 1); await task.value
        XCTAssertFalse(screen.loading); XCTAssertFalse(screen.failed)
        XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope)
        await screen.load(reader) { _, _ in 2 }
        XCTAssertEqual(screen.value, 2); XCTAssertFalse(screen.loading)
    }
    func testOldScreenCompletionCannotClearNewInflightLoading() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<Int>()
        let firstStarted = expectation(description: "old screen read"), nextStarted = expectation(description: "new screen read")
        var first: CheckedContinuation<Int, Never>?, next: CheckedContinuation<Int, Never>?
        let old = Task { await screen.load(reader) { _, _ in
            await withCheckedContinuation { first = $0; firstStarted.fulfill() }
        } }
        await fulfillment(of: [firstStarted], timeout: 2)
        screen.cancel()
        let newer = Task { await screen.load(reader) { _, _ in
            await withCheckedContinuation { next = $0; nextStarted.fulfill() }
        } }
        await fulfillment(of: [nextStarted], timeout: 2)
        first?.resume(returning: 1); await old.value
        XCTAssertTrue(screen.loading); XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope)
        XCTAssertFalse(screen.failed)
        next?.resume(returning: 2); await newer.value
        XCTAssertFalse(screen.loading); XCTAssertEqual(screen.value, 2)
        XCTAssertEqual(screen.loadedScope, reader.scope)
    }
    func testScreenScopeChangeWithoutExplicitClearCannotStickLoading() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let reader = session.walletHistoryReader, screen = WalletScreen<Int>()
        await screen.load(reader) { _, _ in
            grants.retained?.revoke(); grants.enabled = false
            return 1
        }
        XCTAssertFalse(screen.loading); XCTAssertFalse(screen.failed)
        XCTAssertNil(screen.value); XCTAssertNil(screen.loadedScope)
        grants.retained = nil; grants.enabled = true
        let fresh = session.walletHistoryReader
        await screen.load(fresh) { _, _ in 2 }
        XCTAssertEqual(screen.value, 2); XCTAssertEqual(screen.loadedScope, fresh.scope)
    }
    private func form(_ path: String, _ fields: [String: String]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(path), fields: fields, token: "synthetic-7", boundary: "wallet-test")
    }
    @MainActor private final class InviteGrants {
        var retained: ProfileInviteHistoryReadAccess?
        func select(_ context: RuntimeDependencyContext) -> ProfileInviteHistoryReadAccess? {
            if retained == nil {
                let approval = try? OperationEndpointApproval(baseURL: context.baseURL,
                    namespace: context.session.namespace, accountID: context.session.accountID,
                    paths: ProfileInviteHistoryReadRoute.paths)
                if let approval { retained = try? .init(context: context, approval: approval) }
            }
            return retained
        }
    }
    @MainActor private final class Grants {
        var enabled = true, freeze = false; var retained: WalletHistoryReadApproval?
        func select(_ context: RuntimeDependencyContext) -> WalletHistoryReadApproval? {
            guard enabled else { return nil }
            if !freeze, retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600))
            }
            return retained
        }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], account = 7, role = "player", code = 200, pause = false, onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, pendingJSON = "{}"
        func finish(code: Int) { let saved = pending; pending = nil; if code == -1 { saved?.resume(throwing: APIError.httpStatus(503)); return }; saved?.resume(returning: (Data((code == 200 ? pendingJSON : "{\"code\":\(code)}").utf8), 200)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path, json: String
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/user/invite_list") { json = #"{"code":200,"data":{"rows":[{"id":201,"nickname":"Synthetic invite","createTime":"2026-10-01 00:30:00"}],"total":1}}"# }
            else if path.hasSuffix("/user/points/list") { json = #"{"code":200,"data":{"rows":[{"eventType":5,"eventId":"201","changePoints":"2.5","createTime":"2026-10-02 10:00:00"}],"total":1}}"# }
            else if path.hasSuffix("/wallet/stages") { json = "{\"code\":\(code),\"data\":{\"pendingSettlement\":1,\"disputed\":2,\"withdrawable\":3,\"complaintPeriod\":[]}}" }
            else if path.hasSuffix("/user/balance/list") { json = "{\"code\":\(code),\"data\":{\"rows\":[{\"id\":61,\"changeBalance\":12}],\"total\":1}}" }
            else if path.hasSuffix("/user/info") { json = "{\"code\":\(code),\"data\":{\"id\":\(account),\"balance\":12}}" }
            else { json = "{\"code\":\(code),\"data\":[]}" }
            if !path.hasSuffix("/phone"), !path.hasSuffix("/userInfo"), !path.hasSuffix("/logout"), pause {
                pendingJSON = json; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            return (Data(json.utf8), 200)
        }
    }
}
