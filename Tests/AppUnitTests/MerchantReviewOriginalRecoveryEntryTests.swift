import Foundation
import XCTest
@testable import Questify

/// Actual read-only model and original receipt reader, with a synthetic wire.
/// No backend, UI device, original completion, or review writer is exercised.
@MainActor final class MerchantReviewOriginalRecoveryEntryTests: XCTestCase {
    func testMissingHostGrantIssuesNoHTTPAndKeepsIntent() async throws {
        let h = try Harness(); let ticket = h.model.begin()
        await h.model.refresh(ticket: ticket, makeAccess: { _ in nil })
        XCTAssertEqual(h.model.failure, .disabled); XCTAssertNil(h.model.receipt)
        XCTAssertTrue(h.wire.requests.isEmpty); try h.assertUnchanged()
    }
    func testAllThreeOriginalActionsReadExactReceiptWithoutCompleting() async throws {
        for action: MerchantReviewReplyAction in [.reply, .update, .delete] {
            let h = try Harness(action: action); await h.read()
            XCTAssertEqual(h.model.receipt?.state, .applied)
            XCTAssertEqual(h.model.receipt?.intent, h.intent)
            XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/reviews/reply/receipt"])
            let request = try XCTUnwrap(h.wire.requests.last)
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: String]
            XCTAssertEqual(body, ["reviewId": "63001", "action": h.wire.action, "requestId": "mb-entry-original"])
            try h.assertUnchanged()
        }
    }
    func testUnknownDoesNotBecomeCurrentStateOrReleaseLock() async throws {
        let h = try Harness(); h.wire.state = "UNKNOWN"; await h.read()
        XCTAssertEqual(h.model.receipt?.state, .unknown); try h.assertUnchanged()
    }
    func testReadFailureRetryDoesNotWriteOrReuseOldAppliedResult() async throws {
        let h = try Harness(); await h.read(); XCTAssertEqual(h.model.receipt?.state, .applied)
        h.wire.receiptStatus = 503; await h.read()
        XCTAssertNil(h.model.receipt); XCTAssertNotNil(h.model.failure)
        h.wire.receiptStatus = 200; await h.read(); XCTAssertEqual(h.model.receipt?.state, .applied)
        XCTAssertEqual(h.wire.requests.count, 6); try h.assertUnchanged()
    }
    func testDepartureDuringAccessPreventsReceiptDispatchAndLatePublication() async throws {
        let h = try Harness(); h.wire.onAccess = { h.model.retire() }; await h.read()
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertNil(h.model.receipt)
        XCTAssertNil(h.model.failure); try h.assertUnchanged()
    }
    func testDepartureDuringReceiptCannotAffectReopenedVisit() async throws {
        let h = try Harness(); h.wire.onReceipt = { _ = h.model.begin() }; await h.read()
        XCTAssertNil(h.model.receipt); XCTAssertNil(h.model.failure)
        h.wire.onReceipt = nil; await h.read(); XCTAssertEqual(h.model.receipt?.state, .applied)
        try h.assertUnchanged()
    }
    func testGrantRevocationHidesExistingResultAndNewVisitRequiresFreshRead() async throws {
        let h = try Harness(); await h.read(); XCTAssertNotNil(h.model.receipt)
        h.enabled = false; XCTAssertNil(h.model.receipt)
        h.model.retire(); h.enabled = true; XCTAssertNil(h.model.receipt)
        await h.read(); XCTAssertNotNil(h.model.receipt); XCTAssertEqual(h.wire.requests.count, 4)
        try h.assertUnchanged()
    }
    func testChangedAccountAuthorizationOrJournalCannotBorrowOriginalView() async throws {
        for change in 0..<3 {
            let h = try Harness()
            if change == 0 { h.owner.scope = .init(realm: h.configuration.baseURL.absoluteString, accountID: 99, epoch: 2) }
            if change == 1 { h.owner.authorizationGeneration = UUID() }
            if change == 2 { h.journal.rows = [] }
            await h.read(); XCTAssertNil(h.model.receipt); XCTAssertTrue(h.wire.requests.isEmpty)
            XCTAssertEqual(h.journal.completions, 0); XCTAssertEqual(h.owner.writes, 0)
        }
    }
    func testHistoricalOrDuplicateIntentNeverConstructsReadCapability() async throws {
        for legacy in [true, false] {
            let h = try Harness(legacy: legacy)
            if !legacy { h.journal.rows.append(h.intent) }
            var factories = 0; let ticket = h.model.begin()
            await h.model.refresh(ticket: ticket) { current in factories += 1; return h.capability(current) }
            XCTAssertEqual(factories, 0); XCTAssertTrue(h.wire.requests.isEmpty)
            XCTAssertNil(h.model.receipt); XCTAssertEqual(h.journal.completions, 0)
        }
    }
    func testServerPermissionDenialCannotShowAppliedAndRetainsIntent() async throws {
        let h = try Harness(); h.wire.permissions = ["merchant:basic:read"]; await h.read()
        XCTAssertEqual(h.model.failure, .denied); XCTAssertNil(h.model.receipt)
        XCTAssertEqual(h.wire.requests.count, 1); try h.assertUnchanged()
    }
    func testSourceOwnerIdentityAndRetiredQueuedReadAreFenced() async throws {
        let h = try Harness(), other = try Harness()
        XCTAssertTrue(h.model.belongs(to: h.owner, journal: h.journal))
        XCTAssertFalse(h.model.belongs(to: other.owner, journal: h.journal))
        XCTAssertFalse(h.model.belongs(to: h.owner, journal: other.journal))
        let ticket = h.model.begin(); h.model.retire()
        await h.model.refresh(ticket: ticket, makeAccess: h.capability)
        XCTAssertTrue(h.wire.requests.isEmpty); try h.assertUnchanged()
    }
    @MainActor private final class Harness {
        let configuration: APIConfiguration, owner: Owner, intent: MerchantBusinessIntent
        let journal: Journal, wire: Wire
        let model: MerchantReviewOriginalRecoveryModel
        let session: MerchantBusinessSession
        var enabled = true
        init(action: MerchantReviewReplyAction = .reply, legacy: Bool = false) throws {
            let configuration = try APIConfiguration(baseURL: URL(string: "https://example.invalid")!)
            let session = try MerchantBusinessSession(accountID: 21, epoch: 1, token: "synthetic-token")
            let owner = Owner(scope: .init(realm: configuration.baseURL.absoluteString, accountID: 21, epoch: 1))
            let journal = Journal(), wire = Wire()
            let mutation = MerchantBusinessMutation.review(id: try .init(63001), version: 0, action: action, content: "Synthetic")
            let intent = MerchantBusinessIntent(scope: try XCTUnwrap(owner.scope), merchantID: 610, target: "review:63001", requestID: "mb-entry-original",
                                               reviewOriginal: legacy ? nil : MerchantReviewReplyOriginal(mutation: mutation))
            journal.rows = [intent]; wire.action = intent.reviewOriginal?.action.rawValue ?? "MERCHANT_REVIEW_REPLIED"
            self.configuration = configuration; self.session = session; self.owner = owner
            self.journal = journal; self.wire = wire; self.intent = intent
            model = .init(reader: owner, journal: journal, access: try owner.accessValue(), intent: intent)
        }
        func capability(_ current: @escaping () -> Bool) -> MerchantReviewOriginalRecoveryAccess? {
            let available = { [weak self] in self?.enabled == true && current() }
            guard available() else { return nil }
            let reader = MerchantReviewOriginalReceiptReader(configuration: configuration, transport: wire,
                reader: owner, journal: journal, currentSession: { [weak self] in self?.session }, enabled: available)
            return .init(reader: reader, isCurrent: available)
        }
        func read() async { await model.refresh(ticket: model.begin(), makeAccess: capability) }
        func assertUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(journal.rows, [intent], file: file, line: line)
            XCTAssertEqual(journal.completions, 0, file: file, line: line)
            XCTAssertEqual(journal.reserves, 0, file: file, line: line)
            XCTAssertEqual(owner.writes, 0, file: file, line: line)
            XCTAssertEqual(owner.snapshots, 0, file: file, line: line)
        }
    }
    @MainActor private final class Journal: MerchantBusinessIntentStore {
        var rows: [MerchantBusinessIntent] = [], completions = 0, reserves = 0
        func intents() throws -> [MerchantBusinessIntent] { rows }
        func reserve(_ intent: MerchantBusinessIntent) throws { reserves += 1; XCTFail("No new intent") }
        func complete(_ intent: MerchantBusinessIntent) throws { completions += 1; XCTFail("No completion") }
    }
    @MainActor private final class Owner: MerchantBusinessReading {
        var scope: MerchantBusinessScope?, authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var writes = 0, snapshots = 0
        init(scope: MerchantBusinessScope) { self.scope = scope }
        func accessValue() throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]), "roleCode": .string("MERCHANT_OWNER"),
                       "permissions": .array([.string("merchant:marketing:write")])])
        }
        func access() async throws -> MerchantBusinessAccess { try accessValue() }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            snapshots += 1; throw MerchantBusinessFailure.disabled
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            writes += 1; throw MerchantBusinessFailure.disabled
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var permissions = ["merchant:marketing:write"]
        var action = "MERCHANT_REVIEW_REPLIED", state = "APPLIED", receiptStatus = 200
        var onAccess: (() -> Void)?, onReceipt: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let body: [String: Any], status: Int
            if request.url?.path == "/api/merchant/access/me" {
                body = ["active": true, "merchant": ["id": 610], "roleCode": "MERCHANT_OWNER", "permissions": permissions]
                status = 200; onAccess?()
            } else {
                XCTAssertEqual(request.url?.path, "/api/merchant/reviews/reply/receipt")
                body = ["reviewId": "63001", "action": action, "requestId": "mb-entry-original", "state": state]
                status = receiptStatus; onReceipt?()
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), status)
        }
    }
}
