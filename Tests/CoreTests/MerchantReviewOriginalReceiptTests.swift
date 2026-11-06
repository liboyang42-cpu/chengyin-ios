import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class MerchantReviewOriginalReceiptTests: XCTestCase {
    private func mutation(_ action: MerchantReviewReplyAction = .reply) throws -> MerchantBusinessMutation {
        .review(id: try .init(63001), version: 0, action: action, content: "Synthetic reply")
    }
    private func makeIntent(_ h: Harness, action: MerchantReviewReplyAction = .reply, legacy: Bool = false) throws -> MerchantBusinessIntent {
        .init(scope: try XCTUnwrap(h.owner.scope), merchantID: 610, target: "review:63001", requestID: "mb-original",
              reviewOriginal: legacy ? nil : MerchantReviewReplyOriginal(mutation: try mutation(action)))
    }
    func testDefaultClosedBeforeAnyAccessOrReceiptRequest() async throws {
        let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
        let closed = MerchantReviewOriginalReceiptReader(configuration: h.configuration, transport: h.wire,
            reader: h.owner, journal: h.journal, currentSession: { h.session })
        await expect(.disabled) { _ = try await closed.read(intent) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testHistoricalJournalNeverAcquiresActionFromCurrentReview() async throws {
        let h = try Harness(); let old = try makeIntent(h, legacy: true); try h.journal.reserve(old)
        let decoded = try JSONDecoder().decode(MerchantBusinessIntent.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.reviewOriginal)
        await expect(.unknown) { _ = try await h.reader.read(decoded) }
        XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertEqual(try h.journal.intents(), [old])
    }
    func testAppliedReceiptBindsOriginalAndNeverCompletesOrWrites() async throws {
        for action: MerchantReviewReplyAction in [.reply, .update, .delete] {
            let h = try Harness(); let intent = try makeIntent(h, action: action); try h.journal.reserve(intent)
            h.wire.action = try XCTUnwrap(intent.reviewOriginal).action.rawValue
            let receipt = try await h.reader.read(intent)
            XCTAssertEqual(receipt.state, .applied); XCTAssertEqual(receipt.intent, intent)
            XCTAssertEqual(try h.journal.intents(), [intent])
            XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/api/merchant/access/me", "/api/merchant/reviews/reply/receipt"])
            let request = try XCTUnwrap(h.wire.requests.last)
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body, ["reviewId": "63001", "action": h.wire.action, "requestId": "mb-original"])
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertFalse(request.httpShouldHandleCookies)
        }
    }
    func testUnknownIsNotPermissionToClearOrRetry() async throws {
        let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
        h.wire.state = "UNKNOWN"
        let result = try await h.reader.read(intent)
        XCTAssertEqual(result.state, .unknown); XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testMismatchedOrUnexpectedReceiptNeverBecomesApplied() async throws {
        for field in ["reviewId", "action", "requestId", "state"] {
            let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
            h.wire.override = (field, "wrong")
            await expect(.malformed) { _ = try await h.reader.read(intent) }
            XCTAssertEqual(try h.journal.intents(), [intent])
        }
    }
    func testRevocationDuringReceiptAndOwnerMismatchCannotPublish() async throws {
        let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
        h.wire.onReceipt = { h.owner.authorizationGeneration = UUID() }
        await expect(.stale) { _ = try await h.reader.read(intent) }
        XCTAssertEqual(try h.journal.intents(), [intent])
        let foreign = try Harness(); let foreignIntent = try makeIntent(foreign); try foreign.journal.reserve(foreignIntent)
        foreign.session = try .init(accountID: 22, epoch: 1, token: "synthetic-token")
        await expect(.stale) { _ = try await foreign.reader.read(foreignIntent) }
        XCTAssertTrue(foreign.wire.requests.isEmpty)
    }
    func testReadRequiresSameMarketingPermissionAsServer() async throws {
        let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
        h.wire.permissions = ["merchant:basic:read"]
        await expect(.denied) { _ = try await h.reader.read(intent) }
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(try h.journal.intents(), [intent])
    }
    func testVersionedMetadataSurvivesEncodingButUnknownVersionCannotRead() async throws {
        let h = try Harness(); let intent = try makeIntent(h)
        let bytes = try JSONEncoder().encode(intent)
        XCTAssertEqual(try JSONDecoder().decode(MerchantBusinessIntent.self, from: bytes), intent)
        var object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        object["reviewOriginal"] = ["version": 2, "action": "MERCHANT_REVIEW_REPLIED"]
        let unknown = try JSONDecoder().decode(MerchantBusinessIntent.self,
            from: JSONSerialization.data(withJSONObject: object))
        try h.journal.reserve(unknown)
        await expect(.unknown) { _ = try await h.reader.read(unknown) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertNil(MerchantReviewReplyOriginal(mutation: try mutation(.report)))
    }
    func testRealCoordinatorReservesOriginalActionBeforeUnknownDispatch() async throws {
        let h = try Harness()
        let coordinator = MerchantBusinessCoordinator(reader: h.owner, journal: h.journal)
        await coordinator.load(.reviews(page: 1))
        coordinator.prepare(try mutation())
        let review = try XCTUnwrap(coordinator.confirmation)
        h.owner.onExecute = {
            let row = try XCTUnwrap(h.journal.intents().first)
            XCTAssertEqual(row.requestID, review.requestID)
            XCTAssertEqual(row.reviewOriginal?.version, 1)
            XCTAssertEqual(row.reviewOriginal?.action, .reply)
        }
        await coordinator.confirm(review)
        XCTAssertEqual(coordinator.failure, .unknown)
        XCTAssertEqual(try h.journal.intents().first?.reviewOriginal?.action, .reply)
    }
    func testGateWithdrawalOrJournalChangeDuringReadRejectsLateReceipt() async throws {
        for removeJournal in [false, true] {
            let h = try Harness(); let intent = try makeIntent(h); try h.journal.reserve(intent)
            h.wire.onReceipt = {
                if removeJournal { try? h.journal.complete(intent) }
                else { h.enabled = false }
            }
            await expect(.stale) { _ = try await h.reader.read(intent) }
            if !removeJournal { XCTAssertEqual(try h.journal.intents(), [intent]) }
        }
    }
    private func expect(_ issue: MerchantBusinessFailure, _ body: () async throws -> Void) async {
        do { try await body(); XCTFail("Expected \(issue)") }
        catch { XCTAssertEqual(error as? MerchantBusinessFailure, issue) }
    }
    @MainActor private final class Harness {
        let configuration: APIConfiguration
        var session: MerchantBusinessSession?
        var enabled = true
        let owner: Owner
        let journal = MerchantBusinessMemoryIntentStore(), wire = Wire()
        lazy var reader = MerchantReviewOriginalReceiptReader(configuration: configuration, transport: wire,
            reader: owner, journal: journal, currentSession: { [unowned self] in session }, enabled: { [unowned self] in enabled })
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
        init(scope: MerchantBusinessScope) { self.scope = scope }
        func access() async throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                       "roleCode": .string("MERCHANT_OWNER"), "permissions": .array([.string("merchant:basic:read"), .string("merchant:marketing:write")])])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            let row: MerchantBusinessObject = ["id": .int(63001), "version": .int(0), "rating": .int(4),
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
