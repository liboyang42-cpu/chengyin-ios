import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class MerchantReviewReceiptCompletionTests: XCTestCase {
    private func seed(_ h: Harness) throws -> MerchantBusinessIntent {
        let mutation = MerchantBusinessMutation.review(id: try .init(63001), version: 0, action: .reply, content: "Synthetic")
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(h.owner.scope), merchantID: 610,
            target: "review:63001", requestID: "mb-original", reviewOriginal: MerchantReviewReplyOriginal(mutation: mutation))
        try h.journal.reserve(intent); return intent
    }
    func testReadPermissionAloneCannotCompleteJournal() async throws {
        let h = try Harness(); let intent = try seed(h)
        let readOnly = MerchantReviewOriginalReceiptReader(configuration: h.configuration, transport: h.wire,
            reader: h.owner, journal: h.journal, currentSession: { h.session }, enabled: { true })
        await expect(.disabled) { _ = try await readOnly.complete(intent) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        let receipt = try await readOnly.read(intent)
        XCTAssertEqual(receipt.state, .applied); XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testAppliedAndFreshCurrentProjectionCompleteOnlyExactIntent() async throws {
        let h = try Harness(); let intent = try seed(h)
        let other = MerchantBusinessIntent(scope: try XCTUnwrap(h.owner.scope), merchantID: 610,
            target: "review:63002", requestID: "other-original")
        try h.journal.reserve(other)
        let result = try await h.reader.complete(intent)
        XCTAssertTrue(result.journalCompleted); XCTAssertEqual(result.receipt.intent, intent)
        guard case .current(let row) = result.current else { return XCTFail("Expected current facts") }
        XCTAssertEqual(row.fields["merchantReply"], .null, "Current state need not match historical applied action")
        XCTAssertEqual(try h.journal.intents(), [other]); XCTAssertEqual(h.owner.snapshots, 1)
    }
    func testMissingCurrentRowDoesNotEraseOriginalAppliedEvidenceOrInventCurrentReply() async throws {
        let h = try Harness(); let intent = try seed(h); h.owner.rowID = 63002
        let result = try await h.reader.complete(intent)
        XCTAssertEqual(result.receipt.state, .applied)
        XCTAssertEqual(result.current, .notInLoadedPages(hasMore: false))
        XCTAssertTrue(result.journalCompleted); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testUnknownNeverCompletesAndDoesNotReadCurrentState() async throws {
        let h = try Harness(); let intent = try seed(h); h.wire.state = "UNKNOWN"
        let result = try await h.reader.complete(intent)
        XCTAssertFalse(result.journalCompleted); XCTAssertNil(result.current)
        XCTAssertEqual(h.owner.snapshots, 0); XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testCurrentReadFailureRetainsIntentDespiteAppliedReceipt() async throws {
        let h = try Harness(); let intent = try seed(h); h.owner.snapshotFailure = true
        await expect(.unknown) { _ = try await h.reader.complete(intent) }
        XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testRevocationDuringCurrentReadPreventsCompletion() async throws {
        let h = try Harness(); let intent = try seed(h)
        h.owner.onSnapshot = { h.owner.authorizationGeneration = UUID() }
        await expect(.stale) { _ = try await h.reader.complete(intent) }
        XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testPreviouslyReturnedReceiptCannotBypassFreshOriginalRead() async throws {
        let h = try Harness(); let intent = try seed(h)
        let old = try await h.reader.read(intent); XCTAssertEqual(old.state, .applied)
        h.wire.state = "UNKNOWN"
        let result = try await h.reader.complete(intent)
        XCTAssertEqual(result.receipt.state, .unknown); XCTAssertFalse(result.journalCompleted)
        XCTAssertEqual(h.wire.requests.count, 4); XCTAssertEqual(try h.journal.intents(), [intent])
    }
    private func expect(_ issue: MerchantBusinessFailure, _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(issue)") }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, issue) }
    }
    @MainActor private final class Harness {
        let configuration: APIConfiguration
        var session: MerchantBusinessSession?
        var enabled = true, completion = true
        let owner: Owner
        let journal = MerchantBusinessMemoryIntentStore(), wire = Wire()
        lazy var reader = MerchantReviewOriginalReceiptReader(configuration: configuration, transport: wire,
            reader: owner, journal: journal, currentSession: { [unowned self] in session }, enabled: { [unowned self] in enabled }, completionEnabled: { [unowned self] in completion })
        init() throws {
            configuration = try .init(baseURL: URL(string: "https://example.com")!)
            session = try .init(accountID: 21, epoch: 1, token: "synthetic-token")
            owner = Owner(scope: .init(realm: configuration.baseURL.absoluteString, accountID: 21, epoch: 1))
        }
    }
    @MainActor private final class Owner: MerchantBusinessReading {
        var scope: MerchantBusinessScope?
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
        var authorizationGeneration: UUID? = UUID()
        var onExecute: (() throws -> Void)?
        var rowID = 63001, snapshots = 0
        var snapshotFailure = false
        var onSnapshot: (() -> Void)?
        init(scope: MerchantBusinessScope) { self.scope = scope }
        func access() async throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                       "roleCode": .string("MERCHANT_OWNER"), "permissions": .array([.string("merchant:basic:read"), .string("merchant:marketing:write")])])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            snapshots += 1; onSnapshot?()
            if snapshotFailure { throw MerchantBusinessFailure.unknown }
            let row: MerchantBusinessObject = ["id": .int(rowID), "version": .int(0), "rating": .int(4),
                "imageUrls": .array([]), "verifiedRedemption": .bool(true), "status": .string("VISIBLE"),
                "merchantReply": .null, "canReply": .bool(true), "canReport": .bool(true), "canEditReply": .bool(false)]
            let document = try MerchantBusinessDocument(query: query, payload: .object([
                "mode": .string("manage"), "pageNum": .int(1), "pageSize": .int(20), "total": .int(1),
                "hasMore": .bool(false), "items": .array([.object(row)])]))
            return .init(access: try await access(), document: document)
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            try onExecute?(); throw MerchantBusinessFailure.unknown
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var permissions = ["merchant:basic:read", "merchant:marketing:write"]
        var action = "MERCHANT_REVIEW_REPLIED", state = "APPLIED"
        var override: (String, String)?, onReceipt: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let body: [String: Any]
            if request.url?.path == "/api/merchant/access/me" {
                body = ["active": true, "merchant": ["id": 610], "roleCode": "MERCHANT_OWNER", "permissions": permissions]
            } else {
                XCTAssertEqual(request.url?.path, "/api/merchant/reviews/reply/receipt")
                var receipt = ["reviewId": "63001", "action": action, "requestId": "mb-original", "state": state]
                if let override { receipt[override.0] = override.1 }
                body = receipt; onReceipt?()
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
        }
    }
}
