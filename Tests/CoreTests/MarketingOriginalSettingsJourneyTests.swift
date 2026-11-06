import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class MarketingJourneyWire: HTTPTransport {
    var requests: [URLRequest] = []
    var currentChoice = false, recordWrites = true, dropPostReply = false, oppositeCurrent = false, failList = false
    var httpStatus = 200, code = 200
    var afterSend: ((URLRequest) -> Void)?
    var receiptEdit: ((inout [String: Any]) -> Void)?
    var recorded: [String: Bool] = [:]
    static func row(_ choice: Bool) -> [String: Any] {
        ["merchantRowId": 41, "merchantOwnerMemberId": 7, "merchantName": "Synthetic shop", "inAppOptedIn": choice, "couponOptedIn": false]
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); defer { afterSend?(request) }
        var value: Any
        if request.httpMethod == "POST" {
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            let id = body["requestId"] as! String, choice = body["optedIn"] as! Bool
            if recordWrites { recorded[id] = choice }
            currentChoice = oppositeCurrent ? !choice : choice
            if dropPostReply { throw URLError(.timedOut) }
            value = [:]
        } else if request.url!.lastPathComponent == "result" {
            let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let id = q.first { $0.name == "requestId" }!.value!
            var receipt: [String: Any] = ["receiptVersion": 1, "actorId": 71, "merchantRowId": 41, "merchantOwnerMemberId": 7,
                "channel": q.first { $0.name == "channel" }!.value!, "requestId": id, "outcome": recorded[id] == nil ? "NOT_OBSERVED" : "RECORDED"]
            if let choice = recorded[id] { receipt["consentId"] = 23; receipt["eventType"] = choice ? "OPT_IN" : "OPT_OUT"; receipt["recordedAt"] = 1 }
            receiptEdit?(&receipt); value = receipt
        } else {
            if failList { throw URLError(.notConnectedToInternet) }
            value = [Self.row(currentChoice)]
        }
        return (try JSONSerialization.data(withJSONObject: ["code": code, "data": value], options: .sortedKeys), httpStatus)
    }
}
@MainActor private final class MarketingJourneyAuth: AuthChannelServing {
    func sendSMSCode(phone: String) async throws { XCTFail("Marketing must not send SMS") }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class MarketingJourneyEffects: ComplianceRoamEffects {
    func stopTracking() async throws { XCTFail("Marketing must not alter roam") }
    func clearMapPrivacy() async throws { XCTFail("Marketing must not alter roam") }
    func invalidateMapPrivacyCaches() { XCTFail("Marketing must not alter roam") }
}
@MainActor private final class MarketingJourneyFixture {
    let url = URL(string: "https://marketing.example.test/native")!
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("pending.json")
    let wire = MarketingJourneyWire()
    var context: RuntimeDependencyContext
    var session: ComplianceSession? = .init(accountID: 71, epoch: 1, market: "CN", namespace: "synthetic-marketing")
    var approval: MerchantMarketingConsentOriginalApproval?
    var client: MerchantMarketingConsentOriginalClient?
    var unauthorized = 0
    lazy var journal = ComplianceFileJournal(url: file)
    lazy var service = AccountComplianceService(configuration: try! .init(baseURL: url), transport: wire, journal: journal,
        current: { self.session }, token: { self.context.session.token }, marketingOriginal: { self.client })
    lazy var flow = AccountComplianceCoordinator(service: service, auth: MarketingJourneyAuth(), effects: MarketingJourneyEffects(),
        current: { self.session }, invalidateSession: { _ in XCTFail("Not account deletion") })
    init(writes: Bool = true, scoped: Bool = false) throws {
        context = .init(market: .china, baseURL: URL(string: "https://marketing.example.test/native")!, role: "player",
            session: try .init(accountID: 71, epoch: 1, namespace: "synthetic-marketing", token: "synthetic-token", role: "player"))
        try install(writes: writes, scoped: scoped)
    }
    func install(writes: Bool = true, scoped: Bool = false) throws {
        let grants: Set<MerchantMarketingConsentOriginalGrant> = writes ? [try .init(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: true), try .init(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: false)] : []
        let a = try MerchantMarketingConsentOriginalApproval(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID, grants: grants)
        approval = a; let captured = context
        let transport: any HTTPTransport
        if scoped { transport = MerchantMarketingConsentScopedTransport(context: captured, approval: a, underlying: wire, current: { self.context }, stillApproved: { self.approval == a }) }
        else { transport = wire }
        client = .init(context: captured, approval: a, transport: transport, current: { self.context }, stillApproved: { self.approval == a }, onUnauthorized: { self.unauthorized += 1 })
    }
    func cleanup() { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    func pending(id: String = "original-choice", choice: Bool? = true, realm: String? = nil) -> CompliancePendingOperation {
        .init(scope: session!.journalScope, operation: "marketing|41|7|IN_APP", requestID: id, epoch: 1,
              marketingOptedIn: choice, marketingRealm: realm ?? url.absoluteString)
    }
    func review() async throws -> ComplianceMarketingReview {
        await flow.loadMarketing()
        let row = try XCTUnwrap(flow.state.marketing.first)
        return try XCTUnwrap(flow.reviewMarketing(row, channel: .inApp, optedIn: !row.inAppOptedIn))
    }
}

/// Independent original-contract specimens, not edits to any historical fixture or assertions.
@MainActor final class MarketingOriginalSettingsJourneyTests: XCTestCase {
    private func fixture(writes: Bool = true, scoped: Bool = false) throws -> MarketingJourneyFixture {
        let f = try MarketingJourneyFixture(writes: writes, scoped: scoped); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testExplicitConfirmationUsesSameUUIDFromDurableIntentThroughBothResultReads() async throws {
        let f = try fixture(scoped: true), review = try await f.review()
        let initial = f.wire.requests.count; await f.flow.setMarketing(review)
        XCTAssertEqual(f.wire.requests.count, initial)
        f.wire.afterSend = { request in
            if request.httpMethod == "POST" { XCTAssertNotNil(try? f.journal.pending(scope: f.session!.journalScope, operation: "marketing|41|7|IN_APP")) }
        }
        await f.flow.setMarketing(review, explicitlyConfirmed: true)
        XCTAssertEqual(f.wire.requests.dropFirst(initial).map(\.httpMethod), ["GET", "GET", "POST", "GET", "GET"])
        let post = try XCTUnwrap(f.wire.requests.first { $0.httpMethod == "POST" })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(post.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["merchantRowId", "merchantOwnerMemberId", "channel", "optedIn", "requestId"])
        let id = try XCTUnwrap(body["requestId"] as? String)
        let ids = f.wire.requests.filter { $0.url!.lastPathComponent == "result" }.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "requestId" }!.value! }
        XCTAssertEqual(ids, [id, id]); XCTAssertEqual(f.flow.state.marketingOriginalResults.first?.requestId, id)
        XCTAssertTrue(f.flow.state.marketingLoaded); XCTAssertTrue(f.flow.state.marketing.first?.inAppOptedIn == true)
        XCTAssertTrue(try f.journal.marketingPending(scope: f.session!.journalScope).isEmpty)
        let count = f.wire.requests.count; await f.flow.setMarketing(review, explicitlyConfirmed: true); XCTAssertEqual(f.wire.requests.count, count)
    }
    func testOptOutNeedsItsOwnExactTargetGrant() async throws {
        let f = try fixture(writes: false); f.wire.currentChoice = true
        await f.flow.loadMarketing(); let row = try XCTUnwrap(f.flow.state.marketing.first)
        XCTAssertNil(f.flow.reviewMarketing(row, channel: .inApp, optedIn: false))
        let read = try XCTUnwrap(f.approval)
        let optIn = try MerchantMarketingConsentOriginalGrant(merchantID: 41, ownerID: 7, channel: .inApp, optedIn: true)
        f.approval = try .init(baseURL: read.baseURL, namespace: read.namespace, accountID: read.accountID, grants: [optIn])
        XCTAssertFalse(f.approval!.permits(row, .inApp, false)); XCTAssertFalse(f.approval!.permits(row, .coupon, true))
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testLostPostRetainsOriginalAcrossJournalRecreationAndFreshEpochGETOnlyRecovery() async throws {
        let f = try fixture(), review = try await f.review(); f.wire.dropPostReply = true
        await f.flow.setMarketing(review, explicitlyConfirmed: true)
        let pending = try XCTUnwrap(f.journal.marketingPending(scope: f.session!.journalScope).first)
        XCTAssertFalse(f.flow.state.marketingLoaded); XCTAssertTrue(f.flow.state.marketingUnresolved.contains(pending.operation))
        f.context = .init(market: .china, baseURL: f.url, role: "player", session: try .init(accountID: 71, epoch: 2, namespace: "synthetic-marketing", token: "synthetic-new-token"))
        f.session = .init(accountID: 71, epoch: 2, market: "CN", namespace: "synthetic-marketing"); try f.install()
        let cold = AccountComplianceService(configuration: try .init(baseURL: f.url), transport: f.wire, journal: ComplianceFileJournal(url: f.file), current: { f.session }, token: { f.context.session.token }, marketingOriginal: { f.client })
        let start = f.wire.requests.count; let result = try await cold.recoverMarketing(session: f.session!)
        XCTAssertEqual(f.wire.requests.dropFirst(start).map(\.httpMethod), ["GET", "GET"])
        XCTAssertEqual(result.originalResults.first?.requestId, pending.requestID); XCTAssertTrue(result.unresolvedOperations.isEmpty)
    }
    func testMatchingCurrentWithoutOriginalReceiptNeverResolvesUnknown() async throws {
        let f = try fixture(); f.wire.currentChoice = true; let intent = f.pending(); try f.journal.begin(intent)
        let result = try await f.service.recoverMarketing(session: f.session!)
        XCTAssertTrue(result.rows.first?.inAppOptedIn == true); XCTAssertFalse(result.originalResults.first?.recorded ?? true)
        XCTAssertEqual(try f.journal.pending(scope: intent.scope, operation: intent.operation), intent)
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET", "GET"])
    }
    func testRecordedOriginalAndOppositeCurrentStaySeparate() async throws {
        let f = try fixture(); let intent = f.pending(); try f.journal.begin(intent); f.wire.recorded[intent.requestID] = true
        let result = try await f.service.recoverMarketing(session: f.session!)
        XCTAssertTrue(result.originalResults.first?.recorded == true); XCTAssertFalse(result.rows.first?.inAppOptedIn ?? true)
        XCTAssertFalse(result.reconciledCurrentState); XCTAssertTrue(result.currentAvailable)
    }
    func testSuccessfulReceiptAndFailedCurrentReadPreserveHistoryWithoutInventingCurrent() async throws {
        let f = try fixture(); let intent = f.pending(); try f.journal.begin(intent); f.wire.recorded[intent.requestID] = true; f.wire.failList = true
        let result = try await f.service.recoverMarketing(session: f.session!)
        XCTAssertTrue(result.originalResults.first?.recorded == true); XCTAssertFalse(result.currentAvailable); XCTAssertTrue(result.rows.isEmpty)
        XCTAssertTrue(result.unresolvedOperations.isEmpty)
    }
    func testLegacyTargetAndForeignRealmStayLockedWithoutOriginalQuery() async throws {
        for mode in ["target", "realm", "foreign"] {
            let f = try fixture()
            let intent = CompliancePendingOperation(scope: f.session!.journalScope, operation: "marketing|41|7|IN_APP", requestID: "old-choice", epoch: 1,
                marketingOptedIn: mode == "target" ? nil : true, marketingRealm: mode == "realm" ? nil : mode == "foreign" ? "https://other.example.test" : f.url.absoluteString)
            try f.journal.begin(intent); let result = try await f.service.recoverMarketing(session: f.session!)
            XCTAssertTrue(result.unresolvedOperations.contains(intent.operation)); XCTAssertEqual(f.wire.requests.count, 1)
            XCTAssertNotEqual(f.wire.requests.first?.url?.lastPathComponent, "result")
        }
    }
    func testEveryOriginalReceiptIdentityMismatchRetainsIntent() async throws {
        for key in ["actorId", "merchantRowId", "merchantOwnerMemberId", "channel", "requestId", "eventType", "receiptVersion"] {
            let f = try fixture(), intent = f.pending(); try f.journal.begin(intent); f.wire.recorded[intent.requestID] = true
            f.wire.receiptEdit = { value in
                if ["channel", "requestId", "eventType"].contains(key) { value[key] = "wrong" } else { value[key] = 999 }
            }
            let result = try await f.service.recoverMarketing(session: f.session!)
            XCTAssertTrue(result.originalResults.isEmpty, key); XCTAssertTrue(result.unresolvedOperations.contains(intent.operation), key)
        }
    }
    func testCloseDuringPOSTStopsAdditionalGETAndKeepsDurableUnknown() async throws {
        let f = try fixture(), review = try await f.review()
        f.wire.afterSend = { if $0.httpMethod == "POST" { f.flow.invalidate() } }
        await f.flow.setMarketing(review, explicitlyConfirmed: true)
        XCTAssertEqual(f.wire.requests.suffix(3).map(\.httpMethod), ["GET", "GET", "POST"])
        XCTAssertEqual(try f.journal.marketingPending(scope: f.session!.journalScope).count, 1)
        XCTAssertTrue(f.flow.state.marketing.isEmpty)
    }
    func testCloseDuringPreflightListSkipsOriginalQueryAndWrite() async throws {
        let f = try fixture(), review = try await f.review(); let start = f.wire.requests.count
        f.wire.afterSend = { _ in f.flow.invalidate() }
        await f.flow.setMarketing(review, explicitlyConfirmed: true)
        XCTAssertEqual(f.wire.requests.count - start, 1); XCTAssertTrue(try f.journal.marketingPending(scope: f.session!.journalScope).isEmpty)
    }
    func testRevokedHTTPAndBusiness401CannotInvokeNewSessionCallback() async throws {
        for scoped in [false, true] { for status in [200, 401] {
            let f = try fixture(scoped: scoped); f.wire.code = 401; f.wire.httpStatus = status; f.wire.afterSend = { _ in f.approval = nil }
            do { _ = try await f.client!.list(session: f.session!); XCTFail() } catch {}
            XCTAssertEqual(f.unauthorized, 0)
        } }
    }
    func testCurrentHTTP401StillInvokesOriginalCallback() async throws {
        let f = try fixture(scoped: true); f.wire.httpStatus = 401
        do { _ = try await f.client!.list(session: f.session!); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(f.unauthorized, 1)
    }
    func testCancelledHTTP401CannotInvokeCallback() async throws {
        let f = try fixture(); f.wire.httpStatus = 401; var task: Task<Void, Never>?
        f.wire.afterSend = { _ in task?.cancel() }
        task = Task { do { _ = try await f.client!.list(session: f.session!); XCTFail() } catch {} }
        await task?.value; XCTAssertEqual(f.unauthorized, 0)
    }
    func testNewSourceIssuanceCannotReuseAnOldReview() async throws {
        let f = try fixture(), old = try await f.review(); let start = f.wire.requests.count; try f.install()
        await f.flow.setMarketing(old, explicitlyConfirmed: true)
        XCTAssertEqual(f.wire.requests.count, start)
    }
    func testOldMarketingDismissalCannotCancelNewC08Owner() throws {
        let f = try fixture(), old = f.flow.beginMarketingPresentation(), c08 = f.flow.beginDeregistrationPresentation()
        let intent = try XCTUnwrap(f.flow.captureDeregistrationIntent(c08)); f.flow.pauseMarketingPresentation(old); f.flow.retireMarketingSource()
        XCTAssertTrue(f.flow.isCurrentDeregistrationIntent(intent)); XCTAssertTrue(f.flow.ownsDeregistrationPresentation(c08))
    }
    func testOldC08DismissalCannotCancelNewMarketingOwner() throws {
        let f = try fixture(), old = f.flow.beginDeregistrationPresentation(), next = f.flow.beginMarketingPresentation()
        let intent = try XCTUnwrap(f.flow.captureMarketingRead(next)); f.flow.pauseDeregistrationPresentation(old)
        XCTAssertTrue(f.flow.isCurrentMarketingRead(intent)); XCTAssertTrue(f.flow.ownsMarketingPresentation(next))
    }
    func testPausedReadAndOldRefreshIntentCannotReplaceNewLoad() async throws {
        let f = try fixture(), owner = f.flow.beginMarketingPresentation()
        let old = try XCTUnwrap(f.flow.captureMarketingRead(owner)); f.flow.pauseMarketingPresentation(owner)
        await f.flow.loadMarketing(intent: old); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertTrue(f.flow.resumeMarketingPresentation(owner)); let fresh = try XCTUnwrap(f.flow.captureMarketingRead(owner))
        await f.flow.loadMarketing(intent: fresh); await f.flow.loadMarketing(intent: old)
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertTrue(f.flow.state.marketingLoaded)
    }
    func testDefaultNilClientDoesNotBorrowGenericComplianceGates() async throws {
        let f = try fixture(); f.client = nil
        let service = AccountComplianceService(configuration: try .init(baseURL: f.url), transport: f.wire, journal: f.journal,
            current: { f.session }, token: { "synthetic-token" }, readsEnabled: true, writesEnabled: true)
        do { _ = try await service.marketing(session: f.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .unavailable) }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testOriginalRequestFormatPreservesLegacyReferencesWithoutAcceptingInjectedQueryCharacters() {
        for id in ["original-choice", "ABC_123.4:5", UUID().uuidString] { XCTAssertTrue(MerchantMarketingConsentOriginalClient.validRequestID(id)) }
        for id in ["", "bad&id", "bad/id", "bad\n", String(repeating: "a", count: 65)] { XCTAssertFalse(MerchantMarketingConsentOriginalClient.validRequestID(id)) }
    }
    func testSameUUIDAcrossChannelsStillHasUniqueReceiptPresentationIdentity() throws {
        let base: [String: Any] = ["receiptVersion": 1, "actorId": 71, "merchantRowId": 41, "merchantOwnerMemberId": 7, "requestId": "same-original", "outcome": "NOT_OBSERVED"]
        var first = base, second = base; first["channel"] = "IN_APP"; second["channel"] = "COUPON"
        let a = try JSONDecoder().decode(MerchantMarketingConsentOriginalReceipt.self, from: JSONSerialization.data(withJSONObject: first))
        let b = try JSONDecoder().decode(MerchantMarketingConsentOriginalReceipt.self, from: JSONSerialization.data(withJSONObject: second))
        XCTAssertNotEqual(a.id, b.id)
    }
    func testCancelledQueuedReadPreservesTheCompletedLoadWithoutDispatch() async throws {
        let f = try fixture(); await f.flow.loadMarketing(); let rows = f.flow.state.marketing, count = f.wire.requests.count
        let queued = Task { await f.flow.loadMarketing() }; queued.cancel(); await queued.value
        XCTAssertEqual(f.flow.state.marketing, rows); XCTAssertTrue(f.flow.state.marketingLoaded); XCTAssertEqual(f.wire.requests.count, count)
    }
    func testLateInnerRoleChangeCannotCrossTheOriginalClientFence() async throws {
        let f = try fixture(); let captured = f.context
        f.wire.httpStatus = 401
        f.wire.afterSend = { _ in
            f.context = .init(market: captured.market, baseURL: captured.baseURL, role: captured.role,
                session: try! .init(accountID: 71, epoch: 1, namespace: captured.session.namespace, token: captured.session.token, role: "merchant"))
        }
        do { _ = try await f.client!.list(session: f.session!); XCTFail() } catch {}
        XCTAssertEqual(f.unauthorized, 0)
    }

}
