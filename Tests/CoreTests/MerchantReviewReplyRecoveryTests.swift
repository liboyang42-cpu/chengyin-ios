import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class MerchantReviewReplyRecoveryTests: XCTestCase {
    private let url = URL(string: "https://example.com")!
    private func session(_ epoch: UInt64 = 1, account: Int = 21) throws -> MerchantBusinessSession {
        try .init(accountID: account, epoch: epoch, token: "synthetic-token")
    }
    private func reader(_ wire: Wire, current: @escaping () -> MerchantBusinessSession?) throws -> MerchantBusinessSessionReader {
        .init(service: .init(configuration: try .init(baseURL: url), readTransport: wire, testingMutationTransport: wire), currentSession: current)
    }
    private func intent(merchant: Int = 610, account: Int = 21, realm: String? = nil, target: String = "review:63001") -> MerchantBusinessIntent {
        .init(scope: .init(realm: realm ?? url.absoluteString, accountID: account, epoch: 0), merchantID: merchant, target: target, requestID: "mb-original-request")
    }
    private func store(_ intent: MerchantBusinessIntent) throws -> MerchantBusinessMemoryIntentStore {
        let store = MerchantBusinessMemoryIntentStore(); try store.reserve(intent); return store
    }
    func testLostReplyThenRelaunchReadsCurrentRowWithoutRetryOrCompletingIntent() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("intents.json")
        defer { try? FileManager.default.removeItem(at: path.deletingLastPathComponent()) }
        let wire = Wire(), current = try session()
        let actual = try reader(wire, current: { current })
        let original = MerchantBusinessCoordinator(reader: actual, journal: MerchantBusinessFileIntentStore(url: path))
        await original.load(.reviews(page: 1))
        original.prepare(.review(id: try .init(63001), version: 0, action: .reply, content: "Original reply"))
        let review = try XCTUnwrap(original.confirmation)
        await original.confirm(review)
        XCTAssertEqual(original.failure, .unknown); XCTAssertTrue(original.isLocked)
        XCTAssertNil(original.receipt); XCTAssertEqual(wire.writes, 1)

        let reopenedStore = MerchantBusinessFileIntentStore(url: path)
        let relaunched = try reader(wire, current: { try? self.session(2) })
        let recovery = MerchantReviewReplyRecovery(reader: relaunched, journal: reopenedStore)
        let access = try await relaunched.access()
        let pending = try XCTUnwrap(recovery.pending(access: access).first)
        XCTAssertEqual(pending.intent.requestID, review.requestID)
        let before = wire.requests.count
        await recovery.refresh(pending, access: access)
        guard case .current(let row) = recovery.result else { return XCTFail("Expected authoritative current row") }
        XCTAssertEqual(row.fields["merchantReply"], .string("Original reply"))
        XCTAssertEqual(row.fields["version"], .int(1))
        XCTAssertEqual(try reopenedStore.intents(), [pending.intent])
        XCTAssertEqual(wire.writes, 1)
        XCTAssertEqual(wire.requests.dropFirst(before).compactMap { $0.url?.path }, ["/api/merchant/access/me", "/api/merchant/reviews/manage"])
        XCTAssertTrue(wire.requests.dropFirst(before).allSatisfy { $0.httpBody == nil })
        let coordinator = MerchantBusinessCoordinator(reader: relaunched, journal: reopenedStore)
        await coordinator.load(.reviews(page: 1))
        XCTAssertTrue(coordinator.isLocked)
    }
    func testOriginalIntentIsolationAndMalformedTargetsNeverIssueReads() async throws {
        let wire = Wire(), actual = try reader(wire, current: { try? self.session() })
        let access = try await actual.access()
        for intent in [intent(merchant: 611), intent(account: 22), intent(realm: "https://other.example.com"),
                       intent(target: "review:0"), intent(target: "review:063001"), intent(target: "review:63001|other"), intent(target: "customer:63001")] {
            let recovery = MerchantReviewReplyRecovery(reader: actual, journal: try store(intent))
            XCTAssertTrue(try recovery.pending(access: access).isEmpty)
        }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testReadBeyondFivePagesRequiresExplicitContinueAndNeverCompletesJournal() async throws {
        let wire = Wire(); wire.pageCount = 7; wire.targetPage = 7
        let actual = try reader(wire, current: { try? self.session() }), journal = try store(intent())
        let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
        let pending = try XCTUnwrap(recovery.pending(access: access).first)
        await recovery.refresh(pending, access: access)
        XCTAssertEqual(recovery.result, .notInLoadedPages(hasMore: true)); XCTAssertEqual(wire.pages, [1, 2, 3, 4, 5])
        await recovery.loadMore()
        guard case .current = recovery.result else { return XCTFail() }
        XCTAssertEqual(wire.pages, [1, 2, 3, 4, 5, 6, 7]); XCTAssertEqual(wire.writes, 0)
        XCTAssertEqual(try journal.intents(), [pending.intent])
    }
    func testMissingRowIsNotFailureReceiptAndRefreshStartsAtPageOne() async throws {
        let wire = Wire(); wire.pageCount = 2; wire.targetPage = nil
        let actual = try reader(wire, current: { try? self.session() }), journal = try store(intent())
        let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
        let pending = try XCTUnwrap(recovery.pending(access: access).first)
        await recovery.refresh(pending, access: access)
        XCTAssertEqual(recovery.result, .notInLoadedPages(hasMore: false))
        await recovery.loadMore(); XCTAssertEqual(wire.pages, [1, 2])
        wire.targetPage = 1
        await recovery.refresh(pending, access: access)
        XCTAssertEqual(wire.pages, [1, 2, 1]); XCTAssertEqual(try journal.intents(), [pending.intent])
    }
    func testAccountEpochAndJournalChangesImmediatelyHidePublishedResult() async throws {
        let wire = Wire(); var current = try session()
        let actual = try reader(wire, current: { current }), journal = try store(intent())
        let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
        let pending = try XCTUnwrap(recovery.pending(access: access).first)
        await recovery.refresh(pending, access: access); XCTAssertNotNil(recovery.result)
        current = try session(2); XCTAssertNil(recovery.result)
        await recovery.refresh(pending, access: access); XCTAssertNotNil(recovery.result)
        try journal.complete(pending.intent); XCTAssertNil(recovery.result)
        XCTAssertEqual(wire.writes, 0)
    }
    func testMerchantAndPermissionChangesDuringReadDoNotPublishRows() async throws {
        for changePermission in [false, true] {
            let wire = Wire(), actual = try reader(wire, current: { try? self.session() }), journal = try store(intent())
            let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
            let pending = try XCTUnwrap(recovery.pending(access: access).first)
            if changePermission { wire.permissions = [] } else { wire.merchant = 611 }
            await recovery.refresh(pending, access: access)
            XCTAssertNil(recovery.result); XCTAssertEqual(recovery.failure, .stale)
            XCTAssertEqual(try journal.intents(), [pending.intent]); XCTAssertEqual(wire.writes, 0)
        }
    }
    func testDismissalAndAccountReplacementDuringHTTPDoNotPublishOrContinue() async throws {
        for dismiss in [false, true] {
            let wire = Wire(); var current = try session()
            let actual = try reader(wire, current: { current }), journal = try store(intent())
            let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
            let pending = try XCTUnwrap(recovery.pending(access: access).first)
            wire.beforePage = { if dismiss { recovery.invalidate() } else { current = try! self.session(2, account: 22) } }
            await recovery.refresh(pending, access: access)
            XCTAssertNil(recovery.result); XCTAssertFalse(recovery.isBusy)
            XCTAssertEqual(wire.pages, [1]); XCTAssertEqual(try journal.intents(), [pending.intent])
        }
    }
    func testReadFailureRetainsJournalAndExplicitRetryReadsOnly() async throws {
        let wire = Wire(), actual = try reader(wire, current: { try? self.session() }), journal = try store(intent())
        let recovery = MerchantReviewReplyRecovery(reader: actual, journal: journal), access = try await actual.access()
        let pending = try XCTUnwrap(recovery.pending(access: access).first)
        wire.pageStatus = 503
        await recovery.refresh(pending, access: access)
        XCTAssertNil(recovery.result); XCTAssertNotNil(recovery.failure)
        wire.pageStatus = 200
        await recovery.refresh(pending, access: access)
        XCTAssertNotNil(recovery.result); XCTAssertEqual(wire.writes, 0)
        XCTAssertEqual(try journal.intents(), [pending.intent])
    }
    func testCorruptDurableJournalStopsBeforeRecoveryRead() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("corrupt".utf8).write(to: path)
        let wire = Wire(), actual = try reader(wire, current: { try? self.session() }), access = try await actual.access()
        let recovery = MerchantReviewReplyRecovery(reader: actual, journal: MerchantBusinessFileIntentStore(url: path))
        XCTAssertThrowsError(try recovery.pending(access: access))
        XCTAssertEqual(wire.requests.count, 1)
    }
    @MainActor private final class Wire: MerchantBusinessTestTransport {
        var requests: [URLRequest] = []
        var pages: [Int] = []
        var writes = 0
        var merchant = 610
        var permissions = ["merchant:basic:read", "merchant:marketing:write"]
        var pageCount = 1
        var targetPage: Int? = 1
        var pageStatus = 200
        var beforePage: (() -> Void)?
        var reply: String?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let body: [String: Any]
            switch request.url?.path {
            case "/api/merchant/access/me":
                body = ["active": true, "merchant": ["id": merchant], "roleCode": "MERCHANT_OWNER", "permissions": permissions]
            case "/api/merchant/reviews/manage":
                let page = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "pageNum" }!.value!)!
                pages.append(page); beforePage?()
                if pageStatus != 200 { return (Data(), pageStatus) }
                let rows: [[String: Any]] = (0..<20).map { index in
                    ["id": targetPage == page && index == 0 ? 63001 : 80000 + page * 20 + index,
                     "rating": 4, "imageUrls": [], "verifiedRedemption": true, "status": "VISIBLE",
                     "merchantReply": reply as Any? ?? NSNull(), "version": reply == nil ? 0 : 1,
                     "canReply": reply == nil, "canReport": true, "canEditReply": reply != nil]
                }
                body = ["mode": "manage", "pageNum": page, "pageSize": 20, "total": pageCount * 20, "hasMore": page < pageCount, "items": rows]
            case "/api/merchant/reviews/reply":
                writes += 1
                let fields = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                reply = fields["content"] as? String
                throw URLError(.timedOut)
            default: throw URLError(.unsupportedURL)
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
        }
    }
}
