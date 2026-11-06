import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WithdrawalRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var response: (URLRequest) throws -> (Data, Int) = { _ in throw APIError.notConfigured }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return try response(request)
    }
}
@MainActor final class MerchantOfferWithdrawalOriginalRecoveryTests: XCTestCase {
    func testUnknownResultAndCurrentExitNeverAcknowledgeOrSendAgain() async throws {
        let dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let api = try APIConfiguration(baseURL: URL(string: "https://withdraw.example.test/")!)
        let store = MerchantOfferWithdrawalUnifiedStore(url: dir.appendingPathComponent("legacy.json"))
        let p = try MerchantOfferWithdrawalOriginalPending(accountID: 1, merchantID: 2, offerID: 3, namespace: "test", realm: api.baseURL.absoluteString,
            requestID: UUID(), intentSHA256: String(repeating: "a", count: 64), reasonSHA256: String(repeating: "b", count: 64), expectedSHA256: String(repeating: "c", count: 64))
        try store.begin(p) // Synthetic persisted fixture, no request sent.
        let journal = MerchantOfferWithdrawalOriginalJournal(store: store)
        let wire = WithdrawalRecoveryWire()
        wire.response = { request in
            var data: [String: Any] = ["receiptVersion": 1, "actorId": 1, "merchantId": 2, "ownerId": 1, "offerId": 3]
            if request.url?.lastPathComponent == "result" {
                data["requestId"] = p.requestID.uuidString.lowercased(); data["outcome"] = "UNKNOWN"
            } else {
                data["status"] = 0; data["isOrdinary"] = true; data["canWithdraw"] = false
                data["snapshotSHA256"] = String(repeating: "d", count: 64)
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
        let flow = MerchantOfferWithdrawalOriginalFlow(api: api, transport: wire, journal: journal,
            actorID: 1, merchantID: 2, ownerID: 1, offerID: 3, namespace: "test", token: { "synthetic-token" }, current: { true },
            allowed: { $0.hasSuffix("current") || $0.hasSuffix("result") }, authorize: {}, unauthorized: {})
        await flow.recover()
        XCTAssertEqual(flow.receipt?.outcome, "UNKNOWN")
        XCTAssertEqual(flow.snapshot?.status, 0)
        XCTAssertFalse(flow.canPrepare)
        XCTAssertThrowsError(try flow.acknowledgeKnown())
        XCTAssertEqual(try flow.pending(), p)
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertTrue(wire.requests.first?.url?.absoluteString.contains(p.requestID.uuidString.lowercased()) == true)
        flow.invalidate()
        await flow.recover()
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(try journal.read(account: 1, merchant: 2, offer: 3, namespace: "test", realm: api.baseURL.absoluteString), p)
    }
}

extension MerchantOfferWithdrawalOriginalRecoveryTests {
    private func knownFixture(authorize: @escaping () async throws -> Void = {}) throws ->
        (MerchantOfferWithdrawalUnifiedStore, MerchantOfferWithdrawalOriginalPending, WithdrawalRecoveryWire, MerchantOfferWithdrawalOriginalFlow) {
        let dir = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let api = try APIConfiguration(baseURL: URL(string: "https://withdraw.example.test/")!)
        let store = MerchantOfferWithdrawalUnifiedStore(url: dir.appendingPathComponent("legacy.json"))
        let p = try MerchantOfferWithdrawalOriginalPending(accountID: 1, merchantID: 2, offerID: 3, namespace: "test", realm: api.baseURL.absoluteString,
            requestID: UUID(), intentSHA256: String(repeating: "a", count: 64), reasonSHA256: String(repeating: "b", count: 64), expectedSHA256: String(repeating: "c", count: 64))
        try store.begin(p)
        let wire = WithdrawalRecoveryWire()
        wire.response = { request in try Self.knownResponse(request, pending: p) }
        let flow = MerchantOfferWithdrawalOriginalFlow(api: api, transport: wire,
            journal: MerchantOfferWithdrawalOriginalJournal(store: store), actorID: 1, merchantID: 2, ownerID: 1,
            offerID: 3, namespace: "test", token: { "synthetic-token" }, current: { true },
            allowed: { $0.hasSuffix("current") || $0.hasSuffix("result") }, authorize: authorize, unauthorized: {})
        return (store, p, wire, flow)
    }
    nonisolated private static func knownResponse(_ request: URLRequest, pending p: MerchantOfferWithdrawalOriginalPending,
                                      outcome: String = "REJECTED_STATE") throws -> (Data, Int) {
        var data: [String: Any] = ["receiptVersion": 1, "actorId": 1, "merchantId": 2, "ownerId": 1, "offerId": 3]
        if request.url?.lastPathComponent == "result" {
            data.merge(["requestId": p.requestID.uuidString.lowercased(), "outcome": outcome,
                        "reasonSHA256": p.reasonSHA256, "intentSHA256": p.intentSHA256, "expectedSHA256": p.expectedSHA256,
                        "receivedSHA256": String(repeating: "d", count: 64), "receivedReasonSHA256": p.reasonSHA256,
                        "completedAt": 10]) { _, latest in latest }
        } else {
            data.merge(["status": 0, "isOrdinary": true, "canWithdraw": false,
                        "snapshotSHA256": String(repeating: "e", count: 64)]) { _, latest in latest }
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
    func testTransientResultRetainsExactHistoryButCannotAcknowledgeUntilFreshResult() async throws {
        let (_, p, wire, flow) = try knownFixture()
        await flow.recover()
        let original = try XCTUnwrap(flow.receipt)
        XCTAssertTrue(flow.canAcknowledgeKnown)
        wire.response = { request in
            if request.url?.lastPathComponent == "result" { throw URLError(.timedOut) }
            return try Self.knownResponse(request, pending: p)
        }
        await flow.recover()
        XCTAssertEqual(flow.receipt, original)
        XCTAssertFalse(flow.receiptIsFresh)
        XCTAssertFalse(flow.canAcknowledgeKnown)
        XCTAssertThrowsError(try flow.acknowledgeKnown())
        XCTAssertEqual(try flow.pending(), p)
        wire.response = { try Self.knownResponse($0, pending: p) }
        await flow.recover()
        XCTAssertEqual(flow.receipt, original)
        XCTAssertTrue(flow.canAcknowledgeKnown)
        XCTAssertEqual(try flow.pending(), p)
        XCTAssertEqual(wire.requests.count, 6)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testTransientAccessRetainsHistoryButExplicitDenialClearsItWithoutFurtherRequests() async throws {
        var accessError: Error?
        let (_, p, wire, flow) = try knownFixture(authorize: { if let accessError { throw accessError } })
        await flow.recover()
        let original = flow.receipt
        accessError = URLError(.networkConnectionLost)
        await flow.recover()
        XCTAssertEqual(flow.receipt, original)
        XCTAssertFalse(flow.canAcknowledgeKnown)
        XCTAssertEqual(wire.requests.count, 2)
        accessError = MerchantOperationsFailure.accessDenied
        await flow.recover()
        XCTAssertNil(flow.receipt)
        XCTAssertEqual(wire.requests.count, 2)
        XCTAssertEqual(try flow.pending(), p)
    }
    func testContradictoryImmutableResultClearsDisplayAndNeverAcknowledges() async throws {
        let (_, p, wire, flow) = try knownFixture()
        await flow.recover()
        wire.response = { try Self.knownResponse($0, pending: p, outcome: "REJECTED_CHANGED") }
        await flow.recover()
        XCTAssertNil(flow.receipt)
        XCTAssertFalse(flow.canAcknowledgeKnown)
        XCTAssertThrowsError(try flow.acknowledgeKnown())
        XCTAssertEqual(try flow.pending(), p)
    }
    func testHTTPDenialRetiresEvenWhenCallerUnauthorizedHandlerDoesNothing() async throws {
        for status in [401, 403] {
            let (_, p, wire, flow) = try knownFixture()
            await flow.recover()
            wire.response = { _ in (Data(), status) }
            await flow.recover()
            XCTAssertNil(flow.receipt)
            XCTAssertFalse(flow.isCurrent)
            XCTAssertFalse(flow.canAcknowledgeKnown)
            XCTAssertEqual(wire.requests.count, 3)
            XCTAssertEqual(try flow.pending(), p)
        }
    }
    func testDifferentDurableUUIDNeverInheritsHistoryAfterTransientFailure() async throws {
        let (store, p, wire, flow) = try knownFixture()
        await flow.recover()
        try store.acknowledge(p) // Simulate a different cooperating process acknowledging its exact record.
        let next = try MerchantOfferWithdrawalOriginalPending(accountID: p.accountID, merchantID: p.merchantID,
            offerID: p.offerID, namespace: p.namespace, realm: p.realm, requestID: UUID(),
            intentSHA256: p.intentSHA256, reasonSHA256: p.reasonSHA256, expectedSHA256: p.expectedSHA256)
        try store.begin(next)
        wire.response = { _ in throw URLError(.timedOut) }
        await flow.recover()
        XCTAssertNil(flow.receipt)
        XCTAssertFalse(flow.canAcknowledgeKnown)
        XCTAssertEqual(try flow.pending(), next)
    }
    func testCurrentFailureDoesNotEraseFreshOriginalResult() async throws {
        let (_, p, wire, flow) = try knownFixture()
        wire.response = { request in
            if request.url?.lastPathComponent == "current" { throw URLError(.timedOut) }
            return try Self.knownResponse(request, pending: p)
        }
        await flow.recover()
        XCTAssertEqual(flow.receipt?.outcome, "REJECTED_STATE")
        XCTAssertTrue(flow.receiptIsFresh)
        XCTAssertTrue(flow.canAcknowledgeKnown)
        XCTAssertNil(flow.snapshot)
        XCTAssertEqual(try flow.pending(), p)
    }
}


extension MerchantOfferWithdrawalOriginalRecoveryTests {
    func testHTTP503RetainsKnownHistoryButDenialEnvelopeOverridesRetryableStatus() async throws {
        let (_, p, wire, flow) = try knownFixture()
        await flow.recover()
        let original = flow.receipt
        wire.response = { _ in (Data(), 503) }
        await flow.recover()
        XCTAssertEqual(flow.receipt, original)
        XCTAssertFalse(flow.canAcknowledgeKnown)
        XCTAssertEqual(try flow.pending(), p)
        wire.response = { _ in (Data("{\"code\":403}".utf8), 503) }
        await flow.recover()
        XCTAssertNil(flow.receipt)
        XCTAssertFalse(flow.isCurrent)
        XCTAssertEqual(try flow.pending(), p)
    }
}
