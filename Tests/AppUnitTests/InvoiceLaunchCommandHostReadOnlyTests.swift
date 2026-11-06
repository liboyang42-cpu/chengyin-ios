import XCTest
import Foundation
@testable import Questify

/// Synthetic host integration only. Real deployment/approvals are not issued by this test source.
@MainActor final class InvoiceLaunchCommandHostReadOnlyTests: XCTestCase {
    private func seed(_ model: InvoiceLaunchPresentation) throws -> InvoiceLaunchPending {
        let pending = InvoiceLaunchPending(kind: .deleteTitle, targetID: 12, commandRequestID: "synthetic-delete-original")
        try model.coordinator.store.save(pending); return pending
    }
    private var receipt: [String: Any] {
        ["requestId": "synthetic-delete-original", "operation": "DELETE_TITLE", "targetId": "12", "outcome": "DELETED"]
    }
    func testShippedDefaultNeverConstructsInvoiceHostOrRequestsNewRoute() async throws {
        let h = try Harness(injectSelector: false); defer { h.clean() }; await h.login()
        XCTAssertNil(h.session.makeInvoiceLaunchPresentation()); XCTAssertEqual(h.memory.factoryCalls, 0)
        XCTAssertTrue(h.wire.invoiceRequests.isEmpty); XCTAssertTrue(h.memory.values.isEmpty)
    }
    func testOldOriginalReceiptApprovalDoesNotGrantCommandRead() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(originalReceipts: true)
        let model = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()), pending = try seed(model)
        await model.refresh()
        XCTAssertTrue(model.unresolved); XCTAssertEqual(try model.coordinator.store.load(), pending)
        XCTAssertEqual(h.memory.removals, 0)
        XCTAssertFalse(h.wire.invoiceRequests.contains { $0.url!.path.hasSuffix("/commands/request") })
        XCTAssertEqual(h.wire.invoiceRequests.map { $0.url!.lastPathComponent }, ["titles", "eligible", "list"])
    }
    func testExplicitSyntheticCommandReadResolvesOriginalWithoutGrantingWrites() async throws {
        for role in ["player", "merchant", "club"] {
            let h = try Harness(role: role); defer { h.clean() }; await h.login(); try h.approve(commandReceiptRead: true)
            let model = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); _ = try seed(model)
            h.wire.commandResult = receipt; await model.refresh()
            XCTAssertFalse(model.unresolved); XCTAssertNil(try model.coordinator.store.load()); XCTAssertEqual(h.memory.removals, 1)
            XCTAssertTrue(h.wire.invoiceRequests.first!.url!.path.hasSuffix("/commands/request"))
            let body = try JSONSerialization.jsonObject(with: h.wire.invoiceRequests[0].httpBody!) as! [String: Any]
            XCTAssertEqual(Set(body.keys), ["requestId"]); XCTAssertEqual(body["requestId"] as? String, "synthetic-delete-original")
            XCTAssertTrue(h.wire.invoiceRequests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == h.wire.token })
            for action in [InvoiceLaunchUIAction.apply, .saveTitle, .deleteTitle, .cancel] { XCTAssertFalse(model.allows(action)) }
            let count = h.wire.invoiceRequests.count
            await expect(.disabled) { try await model.coordinator.deleteTitle(id: 12) }
            await expect(.disabled) { _ = try await model.coordinator.cancel(id: 51) }
            XCTAssertEqual(h.wire.invoiceRequests.count, count)
            XCTAssertFalse(h.wire.invoiceRequests.contains { $0.url!.path.hasSuffix("delete-request") || $0.url!.path.hasSuffix("cancel-request") })
        }
    }
    func testMissingCommandReceiptLeavesUIUnresolvedAndOriginalJournalIntact() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(commandReceiptRead: true)
        let model = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()), pending = try seed(model)
        await model.refresh(); XCTAssertTrue(model.unresolved); XCTAssertEqual(try model.coordinator.store.load(), pending)
        XCTAssertEqual(h.memory.removals, 0); XCTAssertFalse(model.allows(.deleteTitle))
        XCTAssertEqual(h.wire.invoiceRequests.filter { $0.url!.path.hasSuffix("/commands/request") }.count, 1)
    }
    func testWithdrawalDuringOriginalReadDoesNotClearOrReviveOldHost() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(commandReceiptRead: true)
        let model = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()), pending = try seed(model)
        let approval = h.selection.value; h.wire.delayNextInvoice = true
        let refresh = Task { await model.refresh() }; await h.wire.waitForPending()
        h.session.withInvoiceLaunchConfigurationChange { h.selection.value = nil }
        h.wire.resume((try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]), 200)); await refresh.value
        XCTAssertNil(model.overview); XCTAssertEqual(try model.coordinator.store.load(), pending); XCTAssertEqual(h.memory.removals, 0)
        h.session.withInvoiceLaunchConfigurationChange { h.selection.value = approval }
        let fresh = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); XCTAssertFalse(fresh === model)
        await expect(.staleSession) { _ = try await model.coordinator.service.commandReceipt(requestId: "synthetic-delete-original", operation: .deleteTitle, targetID: 12) }
    }
    func testForeignLoginCannotUseOriginalOwnersPendingCommand() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approve(commandReceiptRead: true)
        let original = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); _ = try seed(original)
        let bytes = h.memory.values; await h.session.logout()
        h.wire.accountID = 8; h.wire.token = "synthetic-owner-8"; await h.login(); try h.approve(commandReceiptRead: true)
        let other = try XCTUnwrap(h.session.makeInvoiceLaunchPresentation()); await other.refresh()
        XCTAssertFalse(other.unresolved); XCTAssertEqual(h.memory.values, bytes); XCTAssertEqual(h.memory.removals, 0)
        XCTAssertFalse(h.wire.invoiceRequests.contains { $0.url!.path.hasSuffix("/commands/request") })
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
            let suite = "invoice-command-host-read-only-" + UUID().uuidString
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
        func approve(originalReceipts: Bool = false, commandReceiptRead: Bool = false) throws {
            let actual = try XCTUnwrap(session.currentRuntimeDependencyContext)
            let grant = try InvoiceLaunchReadApproval(context: actual, originalReceipts: originalReceipts, commandReceiptRead: commandReceiptRead)
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
        var commandResult: [String: Any]?
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
            case "/native/api/invoice/commands/request":
                if let commandResult { body = ["code": 200, "data": commandResult] }
                else { body = ["code": 500, "errorCode": "INVOICE_NOT_FOUND"] }
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
