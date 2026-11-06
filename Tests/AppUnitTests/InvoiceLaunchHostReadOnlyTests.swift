import XCTest
@testable import Questify

/// Review candidate for READ-ONLY-PROPOSAL.patch plus the separately delivered InvoiceLaunch UI/Core.
/// Uses real composition/login/refresh/logout and an injected memory journal. Never real Keychain or HTTP.
@MainActor final class InvoiceLaunchHostReadOnlyTests: XCTestCase {
    func testDefaultClosedBeforeAndAfterRealLoginDoesNotConstructJournalOrSendInvoiceRead() async throws {
        let h = try Harness(injectSelector: false); defer { h.clean() }
        XCTAssertNil(h.session.makeInvoiceLaunchPresentation())
        await h.login()
        XCTAssertEqual(h.session.account?.id, 7)
        for _ in 0..<3 { XCTAssertNil(h.session.makeInvoiceLaunchPresentation()) }
        XCTAssertEqual(h.memory.factoryCalls, 0); XCTAssertTrue(h.wire.invoiceRequests.isEmpty)
        XCTAssertTrue(h.memory.values.isEmpty)
    }

    func testActualApprovalsForThreeRolesReadOnlyAndReuseOnePresentation() async throws {
        for role in ["player", "merchant", "club"] {
            let h = try Harness(role: role); defer { h.clean() }; await h.login(); try h.approve()
            let model = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
            XCTAssertTrue(model === h.session.makeInvoiceLaunchPresentation())
            await model.refresh()
            XCTAssertEqual(model.overview?.titles.first?.titleName, "Synthetic title")
            XCTAssertEqual(h.wire.invoiceRequests.map { $0.url!.path },
                           ["/native/api/invoice/titles", "/native/api/invoice/orders/eligible", "/native/api/invoice/list"])
            XCTAssertTrue(h.wire.invoiceRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == h.wire.token })
            for action in [InvoiceLaunchUIAction.apply, .saveTitle, .deleteTitle, .cancel] { XCTAssertFalse(model.allows(action)) }
            let count = h.wire.invoiceRequests.count
            await expect(.disabled) { _ = try await model.coordinator.apply(InvoiceLaunchApply(titleId: 11, orderIds: [21])) }
            await expect(.disabled) { _ = try await model.coordinator.saveTitle(InvoiceLaunchTitleDraft(titleType: "PERSONAL", titleName: "Synthetic")) }
            await expect(.disabled) { try await model.coordinator.deleteTitle(id: 11) }
            await expect(.disabled) { _ = try await model.coordinator.cancel(id: 51) }
            XCTAssertEqual(h.wire.invoiceRequests.count, count); XCTAssertNil(try model.coordinator.store.load())
            XCTAssertEqual(h.memory.factoryCalls, 1)
        }
    }

    func testRealRoleABAImmediatelyClearsOldPrivateProjectionAndCannotReviveService() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); await old.refresh()
        let oldRevision = old.identityRevision
        h.wire.role = "merchant"; await h.session.refreshOwnAccount()
        XCTAssertEqual(h.session.account?.effectiveRole, "merchant")
        XCTAssertNil(old.overview); XCTAssertNotEqual(old.identityRevision, oldRevision)
        XCTAssertNil(h.session.makeInvoiceLaunchPresentation()) // player grant cannot approve merchant.
        await expect(.staleSession) { _ = try await old.coordinator.service.titles() }
        h.wire.role = "player"; await h.session.refreshOwnAccount()
        try h.approve()
        let fresh = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        XCTAssertFalse(fresh === old)
        await expect(.staleSession) { _ = try await old.coordinator.service.titles() }
        XCTAssertTrue(h.session.isSignedIn)
    }

    func testGrantRevokeAndSameGrantReissueKeepOldServiceRevoked() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let issued = h.selection.value
        let old = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); await old.refresh()
        h.session.withInvoiceLaunchConfigurationChange { h.selection.value = nil }
        XCTAssertNil(old.overview); XCTAssertNil(h.session.makeInvoiceLaunchPresentation())
        h.session.withInvoiceLaunchConfigurationChange { h.selection.value = issued }
        let fresh = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        XCTAssertFalse(fresh === old)
        let count = h.wire.invoiceRequests.count
        await expect(.staleSession) { _ = try await old.coordinator.service.titles() }
        XCTAssertEqual(h.wire.invoiceRequests.count, count)
        await fresh.refresh(); XCTAssertNotNil(fresh.overview)
    }

    func testLogoutForeignAccountAndOriginalOwnerReauthenticationPreserveJournal() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let old = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        let pending = InvoiceLaunchPending(kind: .apply,
            apply: try InvoiceLaunchApply(requestId: "synthetic-original", titleId: 11, orderIds: [21]),
            originalApplicationReceipt: true)
        try old.coordinator.store.save(pending)
        let savedBytes = h.memory.values
        await h.session.logout()
        XCTAssertNil(h.session.makeInvoiceLaunchPresentation()); XCTAssertEqual(h.memory.values, savedBytes)
        h.wire.accountID = 8; h.wire.token = "synthetic-owner-8"; await h.login()
        XCTAssertNil(h.session.makeInvoiceLaunchPresentation()) // old grant remains bound to owner 7.
        try h.approve()
        let foreign = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        XCTAssertNil(try foreign.coordinator.store.load()); XCTAssertEqual(h.memory.values, savedBytes)
        await expect(.staleSession) { _ = try await old.coordinator.service.titles() }
        await h.session.logout()
        h.wire.accountID = 7; h.wire.token = "synthetic-owner-7-new"; await h.login(); try h.approve()
        let restored = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        XCTAssertEqual(try restored.coordinator.store.load(), pending)
        XCTAssertEqual(h.memory.values, savedBytes); XCTAssertEqual(h.memory.removals, 0)
    }

    func testReceiptReadsRequireSeparateApprovalAndNotFoundRetainsOriginal() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
        let initial = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
        let pending = InvoiceLaunchPending(kind: .apply,
            apply: try InvoiceLaunchApply(requestId: "synthetic-original", titleId: 11, orderIds: [21]),
            originalApplicationReceipt: true)
        try initial.coordinator.store.save(pending)
        await initial.refresh()
        XCTAssertTrue(initial.unresolved)
        XCTAssertFalse(h.wire.invoiceRequests.contains { $0.url?.path.hasSuffix("/request") == true })
        try h.approve(originalReceipts: true)
        let approved = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); await approved.refresh()
        let requests = h.wire.invoiceRequests.filter { $0.url?.path == "/native/api/invoice/request" }
        XCTAssertEqual(requests.count, 1)
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as! [String: Any]
        XCTAssertEqual(body["requestId"] as? String, "synthetic-original")
        XCTAssertEqual(try approved.coordinator.store.load(), pending); XCTAssertTrue(approved.unresolved)
        XCTAssertEqual(h.memory.removals, 0)
        XCTAssertFalse(h.wire.invoiceRequests.contains { ["apply", "save", "save-request", "delete", "cancel"].contains($0.url?.lastPathComponent ?? "") })
    }

    func testLate401AfterGrantRevocationCannotExpireAccountOrRestorePrivateData() async throws {
        for reply in [(Data(), 401), (Data(#"{"code":401}"#.utf8), 200)] {
            let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve()
            let old = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation())
            h.wire.delayNextInvoice = true
            let work = Task { await old.refresh() }
            await h.wire.waitForPending()
            h.session.withInvoiceLaunchConfigurationChange { h.selection.value = nil }
            h.wire.resume(reply); await work.value
            XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.vault.token, "synthetic-owner-7")
            XCTAssertNil(old.overview); XCTAssertNil(old.detail)
            XCTAssertNil(h.session.makeInvoiceLaunchPresentation())
        }
    }

    private func expect(_ expected: InvoiceLaunchIssue, _ body: () async throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected \(expected)", file: file, line: line) }
        catch { XCTAssertEqual(error as? InvoiceLaunchIssue, expected, file: file, line: line) }
    }
    @MainActor private final class Selection { var value: InvoiceLaunchReadApproval? }
    @MainActor private final class Harness {
        let suite: String
        let wire: Wire
        let memory: Memory
        let selection: Selection
        let vault: Vault
        let session: AppSession
        init(role: String = "player", injectSelector: Bool = true) throws {
            let suite = "invoice-host-read-only-" + UUID().uuidString
            let wire = Wire(role: role), memory = Memory(), selection = Selection(), vault = Vault()
            self.suite = suite; self.wire = wire; self.memory = memory; self.selection = selection; self.vault = vault
            let base = "https://example.test/native"
            let deployment = try ReviewedAppDeployment(market: .china, baseURL: base,
                approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.invoice-host", realm: "synthetic")
            let storage = AppScopedStorageFactory(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                tokenStore: { _ in vault }, invoiceJournal: { _ in memory.factoryCalls += 1; return memory })
            if injectSelector {
                session = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage,
                    makeTransport: { wire }, invoiceLaunchReadApproval: { _ in selection.value }).makeSession()
            } else {
                session = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage,
                    makeTransport: { wire }).makeSession() // Exercise the actual default-nil selector.
            }
        }
        func login() async {
            session.authChannels.cancel()
            await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            XCTAssertEqual(session.account?.id, wire.accountID)
        }
        func approve(originalReceipts: Bool = false) throws {
            let actual = try XCTUnwrap(session.currentRuntimeDependencyContext)
            let grant = try InvoiceLaunchReadApproval(context: actual, originalReceipts: originalReceipts)
            session.withInvoiceLaunchConfigurationChange { selection.value = grant }
        }
        func clean() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Memory: InvoiceLaunchStorage {
        var values: [String: Data] = [:]
        var factoryCalls = 0, removals = 0
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { removals += 1; values.removeValue(forKey: key) }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role: String, accountID = 7, token = "synthetic-owner-7"
        var requests: [URLRequest] = []
        var invoiceRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/invoice/") == true } }
        var delayNextInvoice = false
        var pending: CheckedContinuation<(Data, Int), Never>?
        init(role: String) { self.role = role }
        func waitForPending() async {
            for _ in 0..<500 { if pending != nil { return }; await Task.yield() }
            XCTFail("Synthetic invoice read did not start")
        }
        func resume(_ value: (Data, Int)) { let continuation = pending; pending = nil; continuation?.resume(returning: value) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url?.path ?? ""
            if path.contains("/api/invoice/"), delayNextInvoice {
                delayNextInvoice = false
                return await withCheckedContinuation { pending = $0 }
            }
            let body: [String: Any]
            switch path {
            case "/native/api/invoice/titles":
                body = ["code": 200, "data": [["id": "11", "titleType": "PERSONAL", "titleName": "Synthetic title", "isDefault": false]]]
            case "/native/api/invoice/orders/eligible", "/native/api/invoice/list": body = ["code": 200, "data": []]
            case "/native/api/invoice/request": body = ["code": 500, "errorCode": "INVOICE_NOT_FOUND"]
            default:
                if path.hasSuffix("/phone") { body = ["code": 200, "token": token, "data": ["id": accountID, "role": role]] }
                else if path.hasSuffix("/userInfo") { body = ["code": 200, "appUser": ["userId": accountID, "role": role]] }
                else if path.hasSuffix("/logout") { body = ["code": 200] }
                else { XCTFail("Unexpected route: \(path)"); throw APIError.notConfigured }
            }
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
    }
}
