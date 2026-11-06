import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *) @MainActor final class CityMerchantOriginalRecoveryTests: XCTestCase {
    @MainActor private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record
        }
        func write(_ value: OperationPendingRecord) throws { guard record == nil else { throw APIError.invalidRequest }; record = value }
        func clear(_ value: OperationPendingRecord) throws { guard record == value else { throw APIError.invalidRequest }; record = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var currentStatus = "NONE", currentVersion = 0
        var lastRequest: String?
        var receiptCode: Int?, receiptHTTP: Int?, receiptError = "UNAVAILABLE"
        var postCode: Int?, postError = "UNAVAILABLE"
        var availabilityFails = false, lostPost = false, wrongReceiptID = false
        var afterReceipt: (() async throws -> Void)?
        var afterAvailability: (() async throws -> Void)?
        var afterPost: (() async throws -> Void)?
        var posts: Int { requests.filter { $0.httpMethod == "POST" }.count }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.httpMethod == "POST" {
                if let postCode { return (try JSONSerialization.data(withJSONObject: ["code": postCode, "errorCode": postError]), postCode) }
                let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
                lastRequest = body["requestId"] as? String; currentStatus = "IN_REVIEW"; currentVersion = 1
                try await afterPost?()
                if lostPost { throw URLError(.timedOut) }
                return try snapshot(status: "IN_REVIEW", version: 1, id: lastRequest)
            }
            if request.url!.path.contains("/request/") {
                if let receiptCode {
                    return (try JSONSerialization.data(withJSONObject: ["code": receiptCode, "errorCode": receiptError]), receiptHTTP ?? receiptCode)
                }
                let result = try snapshot(status: "IN_REVIEW", version: 1,
                    id: wrongReceiptID ? UUID().uuidString : request.url!.lastPathComponent)
                try await afterReceipt?(); return result
            }
            if availabilityFails { throw URLError(.timedOut) }
            let value = try snapshot(status: currentStatus, version: currentVersion, id: lastRequest)
            try await afterAvailability?(); return value
        }
        private func snapshot(status: String, version: Int, id: String?) throws -> (Data, Int) {
            var d: [String: Any] = ["merchantId": "41", "version": version, "status": status,
                "effectiveState": "INHERIT", "runtimeApplied": false, "approvalHash": String(repeating: "a", count: 64),
                "availability": "AVAILABLE", "relation": ["regionId": "city-1", "boardId": "board-1", "seasonId": "season-1", "rulesReleaseId": "release-1", "pointIds": ["point-1"]]]
            if let id { d["requestId"] = id; d["originalRequestId"] = id; d["kind"] = "PAUSE_MERCHANT" }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": d]), 200)
        }
    }
    private func approval(account: Int = 7, writes: Bool = true) throws -> CityMerchantOperationsApproval {
        try .init(context: .init(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "merchant",
            session: .init(accountID: account, epoch: 1, namespace: "city-merchant", token: "synthetic-token")),
            regionID: "city-1", allowsIntent: writes, expiresAt: Date().addingTimeInterval(600))
    }
    private func make(_ w: Wire, _ j: Journal, _ a: CityMerchantOperationsApproval,
                      live: (() -> RuntimeDependencyContext?)? = nil, unauthorized: @escaping () -> Void = {}) -> CityMerchantOperationsController {
        let t = CityMerchantOperationsTransport(approval: a, underlying: w, current: live ?? { a.context }, selected: { _ in a })
        return .init(service: .init(approval: a, transport: t), journal: j, unauthorized: unauthorized)
    }
    private func seed(_ j: Journal) throws {
        try j.write(.init(ownerKey: "city-merchant:city-merchant:https://example.test/native:7", targetKey: "own-store:city-1"))
    }
    private func prepare(_ c: CityMerchantOperationsController) async throws -> CityMerchantOperationsController.Confirmation {
        await c.load(); c.prepare(.pause, reason: "Original own-store reason")
        return try XCTUnwrap(c.confirmation)
    }
    func testCancelledConfirmationNeverDispatchesWhenQueuedLater() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); c.dismissConfirmation(); await c.confirm(review)
        XCTAssertEqual(w.posts, 0); XCTAssertNil(j.record)
    }
    func testOldConfirmationCannotConsumeNewReview() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let old = try await prepare(c); c.prepare(.pause, reason: "Different explicit reason"); let next = c.confirmation
        await c.confirm(old); XCTAssertEqual(c.confirmation, next); XCTAssertEqual(w.posts, 0)
    }
    func testExplicitAdmissionSurvivesAutomaticAlertDismissalButDispatchesOnce() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); XCTAssertTrue(c.admitConfirmation(review)); c.dismissConfirmation()
        await c.confirm(review); await c.confirm(review)
        XCTAssertEqual(w.posts, 1); XCTAssertNotNil(c.receipt); XCTAssertNil(j.record)
    }
    func testExitAfterAdmissionBeforeDispatchInvalidatesTicket() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); XCTAssertTrue(c.admitConfirmation(review)); c.invalidate(); c.activate(); await c.load()
        await c.confirm(review); XCTAssertEqual(w.posts, 0); XCTAssertNil(j.record)
    }
    func testGenericServer500NeverCompletesOriginalJournal() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.receiptCode = 500
        await c.load(); await c.recover(); XCTAssertNotNil(j.record); XCTAssertNotNil(c.pendingRequestID)
        XCTAssertNil(c.originalRejection); XCTAssertEqual(w.posts, 0)
    }
    func testRateLimitAndUnknownCodesAreNotRecordedRejections() async throws {
        for (code, reason) in [(429, "RATE_LIMITED"), (409, "UNKNOWN"), (404, "NOT_FOUND"), (409, "OTHER_CONFLICT")] {
            let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
            try seed(j); w.receiptCode = code; w.receiptError = reason
            await c.recover(); XCTAssertNotNil(j.record); XCTAssertNil(c.originalRejection); XCTAssertEqual(w.posts, 0)
        }
    }
    func testMismatchedHTTPAndEnvelopeCannotProveRecordedRejection() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.receiptCode = 409; w.receiptHTTP = 500; w.receiptError = "VERSION_CONFLICT"
        await c.recover(); XCTAssertNotNil(j.record); XCTAssertNil(c.originalRejection)
    }
    func testOriginalVersionConflictIsBoundToExactGETRequestAndCurrent() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); let id = j.record!.operationID; w.receiptCode = 409; w.receiptError = "VERSION_CONFLICT"
        await c.recover(); XCTAssertEqual(c.originalRejection?.requestID, id); XCTAssertEqual(c.originalRejection?.reason, "VERSION_CONFLICT")
        XCTAssertNil(j.record); XCTAssertEqual(c.currentState, .ready); XCTAssertEqual(w.posts, 0)
    }
    func testRecordedRejectionCurrentFailureRetainsOriginalRecoveryHandle() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.receiptCode = 409; w.receiptError = "VERSION_CONFLICT"; w.availabilityFails = true
        await c.recover(); XCTAssertNotNil(c.originalRejection); XCTAssertNotNil(j.record)
        XCTAssertEqual(c.currentState, .unavailable); XCTAssertEqual(c.messageKey, "cityMerchant.status.knownCurrentUnavailable")
    }
    func testAcceptedReceiptCurrentFailureIsKnownNotUnknown() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); w.afterReceipt = { w.availabilityFails = true }
        await c.confirm(review); XCTAssertEqual(c.receipt?.status, "IN_REVIEW"); XCTAssertNotNil(j.record)
        XCTAssertEqual(c.currentState, .unavailable); XCTAssertEqual(c.messageKey, "cityMerchant.status.knownCurrentUnavailable")
    }
    func testCurrentRecoveryNeverRepeatsPost() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); w.afterReceipt = { w.availabilityFails = true }; await c.confirm(review)
        let original = j.record!.operationID; w.afterReceipt = nil; w.availabilityFails = false
        await c.recover(); XCTAssertEqual(c.receipt?.originalRequestId, original.uuidString)
        XCTAssertNil(j.record); XCTAssertEqual(w.posts, 1); XCTAssertEqual(c.currentState, .ready)
    }
    func testRestartLostPostReadsSameOriginalUUID() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); w.lostPost = true; w.receiptCode = 409; w.receiptError = "UNKNOWN"
        await c.confirm(review); let id = j.record!.operationID; c.invalidate()
        w.receiptCode = nil; let next = make(w, j, a); await next.load(); await next.recover()
        XCTAssertEqual(next.receipt?.requestId, id.uuidString); XCTAssertEqual(w.posts, 1); XCTAssertNil(j.record)
    }
    func testWrongReceiptUUIDCannotCompleteJournalOrReadAsSuccess() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.wrongReceiptID = true
        await c.recover(); XCTAssertNotNil(j.record); XCTAssertNil(c.receipt)
    }
    func testOlderCurrentVersionCannotEraseOriginalRecoveryHandle() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); await c.recover(); XCTAssertEqual(c.receipt?.version, 1)
        XCTAssertNotNil(j.record); XCTAssertNil(c.snapshot); XCTAssertEqual(c.currentState, .unavailable)
    }
    func testLoadFailureStillExposesOriginalPendingUUID() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); let id = j.record!.operationID; w.availabilityFails = true
        await c.load(); XCTAssertEqual(c.pendingRequestID, id); XCTAssertNotNil(j.record)
    }
    func testNewAccountCannotReadOldOriginalRequest() async throws {
        let w = Wire(), j = Journal(), a = try approval(account: 8), c = make(w, j, a)
        try seed(j); await c.load(); await c.recover()
        XCTAssertNotNil(j.record); XCTAssertFalse(w.requests.contains { $0.url!.path.contains("/request/") })
    }
    func testRevokedDuringCurrentReadClearsPrivateStateAndPreservesJournal() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.currentStatus = "IN_REVIEW"; w.currentVersion = 1; w.afterAvailability = { a.revoke() }
        await c.recover(); XCTAssertNil(c.snapshot); XCTAssertNil(c.receipt); XCTAssertNotNil(j.record)
    }
    func testBackgroundExitRejectsLateCurrentAndDoesNotReactivateFromQueuedLoad() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        w.afterAvailability = { c.invalidate() }; await c.load(); let count = w.requests.count
        await c.load(); XCTAssertEqual(w.requests.count, count); XCTAssertNil(c.snapshot)
    }
    func testExitAfterDispatchPreservesJournalForNextVisit() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        let review = try await prepare(c); w.afterPost = { c.invalidate() }; await c.confirm(review)
        XCTAssertNotNil(j.record); XCTAssertEqual(w.posts, 1); XCTAssertNil(c.receipt)
        w.afterPost = nil; c.activate(); await c.load(); await c.recover(); XCTAssertNil(j.record); XCTAssertEqual(w.posts, 1)
    }
    func testOld401CannotSignOutReplacementSession() async throws {
        let w = Wire(), j = Journal(), a = try approval(); var live: RuntimeDependencyContext? = a.context; var calls = 0
        let c = make(w, j, a, live: { live }, unauthorized: { calls += 1 })
        w.afterAvailability = { live = nil; throw APIError.unauthorized }
        await c.load(); XCTAssertEqual(calls, 0); XCTAssertNil(c.snapshot)
    }
    func testReadOnlyApprovalStillCannotAdmitOrPost() async throws {
        let w = Wire(), j = Journal(), a = try approval(writes: false), c = make(w, j, a)
        await c.load(); c.prepare(.pause, reason: "Read only")
        XCTAssertNil(c.confirmation); XCTAssertFalse(c.canPrepare); XCTAssertEqual(w.posts, 0)
    }
    func testVisitAdmissionRejectsExitBackgroundCancelAndOldReappearance() {
        var visit = CityMerchantVisitAdmission(); visit.appear(); let first = visit.revision
        XCTAssertTrue(visit.permits(first, active: true, cancelled: false))
        XCTAssertFalse(visit.permits(first, active: false, cancelled: false)); XCTAssertFalse(visit.permits(first, active: true, cancelled: true))
        visit.disappear(); XCTAssertFalse(visit.permits(first, active: true, cancelled: false)); visit.appear()
        XCTAssertFalse(visit.permits(first, active: true, cancelled: false)); let second = visit.revision; visit.invalidate()
        XCTAssertFalse(visit.permits(second, active: true, cancelled: false))
    }
    func testForbiddenOriginalReadRetainsJournalWithoutShowingPrivateReceipt() async throws {
        let w = Wire(), j = Journal(), a = try approval(), c = make(w, j, a)
        try seed(j); w.receiptHTTP = 403; w.receiptCode = 409; w.receiptError = "VERSION_CONFLICT"
        await c.recover(); XCTAssertNotNil(j.record); XCTAssertNil(c.receipt); XCTAssertNil(c.originalRejection)
        XCTAssertEqual(c.messageKey, "cityMerchant.status.accessWithdrawn"); XCTAssertEqual(w.posts, 0)
    }
    func testCurrentSession401UsesExistingUnauthorizedCallbackAndKeepsJournal() async throws {
        let w = Wire(), j = Journal(), a = try approval(); var calls = 0
        let c = make(w, j, a, unauthorized: { calls += 1 }); try seed(j)
        w.receiptHTTP = 401; w.receiptCode = 401; w.receiptError = "NO_AUTHORITY"
        await c.recover(); XCTAssertEqual(calls, 1); XCTAssertNotNil(j.record); XCTAssertNil(c.receipt)
    }
    func testReplacementApprovalRevisionCannotPublishReceiptOrClearJournal() async throws {
        let w = Wire(), j = Journal(), a = try approval(), replacement = try approval()
        var selected = a
        let t = CityMerchantOperationsTransport(approval: a, underlying: w, current: { a.context }, selected: { _ in selected })
        let c = CityMerchantOperationsController(service: .init(approval: a, transport: t), journal: j)
        try seed(j); w.afterReceipt = { selected = replacement }
        await c.recover(); XCTAssertNotNil(j.record); XCTAssertNil(c.receipt); XCTAssertNil(c.snapshot)
    }
    func testPostConflictIsNotAnOriginalGETReceipt() async throws {
        let w = Wire(), a = try approval()
        w.postCode = 409; w.postError = "VERSION_CONFLICT"
        let t = CityMerchantOperationsTransport(approval: a, underlying: w, current: { a.context }, selected: { _ in a })
        let service = CityMerchantOperationsService(approval: a, transport: t)
        do {
            _ = try await service.submit(id: UUID(), version: 0, kind: .pause, reason: "Own store", approvalHash: String(repeating: "a", count: 64))
            XCTFail("expected conflict")
        } catch is CityMerchantOriginalRejection { XCTFail("POST is not the original GET receipt") }
        catch { XCTAssertEqual(error as? CityMerchantOperationError, .server(409, "VERSION_CONFLICT")) }
    }
    func testOnlyExactOriginalWorkRejectionsAreRecognized() {
        for reason in ["PUBLISHED_MERCHANT_RELATION_UNAVAILABLE", "VERSION_CONFLICT", "APPROVAL_CHANGED", "PENDING_REVIEW", "INVALID_STATE"] {
            XCTAssertTrue(CityMerchantOriginalRejection.matches(code: 409, reason: reason))
            XCTAssertFalse(CityMerchantOriginalRejection.matches(code: 500, reason: reason))
        }
        for reason in ["OBJECT_SCOPE", "REASON_REQUIRED"] {
            XCTAssertTrue(CityMerchantOriginalRejection.matches(code: 400, reason: reason))
        }
        for reason in ["UNKNOWN", "NOT_FOUND", "NO_AUTHORITY", "MISSING_PARAM", "CONFLICT", "UNAVAILABLE"] {
            XCTAssertFalse(CityMerchantOriginalRejection.matches(code: 409, reason: reason))
        }
    }
}
