import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic transport and UUID-isolated defaults only. Execution: NOT_RUN (Swift unavailable).
/// The original eight tests and their assertions remain unchanged.
@available(macOS 14.0, *) extension CityAcquisitionTests {
    @MainActor private final class OriginalStore {
        let suite: String
        let defaults: UserDefaults
        let owner: String
        let target = "city-1"
        init(_ grant: CityAcquisitionApproval) throws {
            let suite = "CityAcquisitionOriginalRecoveryTests." + UUID().uuidString
            self.suite = suite
            defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            owner = "city-acquisition:\(grant.context.session.namespace):\(grant.context.baseURL.absoluteString):\(grant.context.session.accountID)"
        }
        func fresh() -> CityAcquisitionIdentityJournal {
            .init(defaults: defaults, ownerKey: owner, targetKey: target)
        }
        func pending() throws -> OperationPendingRecord? { try fresh().pending(ownerKey: owner, targetKey: target) }
        func original() throws -> OperationPendingRecord? { try fresh().original(ownerKey: owner, targetKey: target) }
        func seed(_ id: UUID = UUID(), completed: Bool = false) throws -> OperationPendingRecord {
            let record = OperationPendingRecord(operationID: id, ownerKey: owner, targetKey: target)
            let journal = fresh(); try journal.write(record)
            if completed { try journal.clear(record) }
            return record
        }
        func cleanup() { defaults.removePersistentDomain(forName: suite) }
    }
    private func originalResponse(_ request: URLRequest, quote override: [String: Any]? = nil) throws -> (Data, Int) {
        let path = request.url!.path
        if request.httpMethod == "POST" { return try response([:]) }
        if path.contains("/request/") {
            let id = request.url!.lastPathComponent
            var value: [String: Any] = ["contract": "CITY_ACQUISITION_V1", "requestId": id, "requestStatus": "COMPLETE"]
            if id == confirmID { value["title"] = title(); value["effectsStatus"] = "COMMITTED" }
            else { value["quote"] = quote(); value["effectsStatus"] = "NOT_EXECUTED" }
            return try response(value)
        }
        if path.contains("/quote/") { return try response(["contract": "CITY_ACQUISITION_V1", "quote": override ?? quote()]) }
        if path.hasSuffix("/titles") { return try response(["contract": "CITY_ACQUISITION_V1", "memberId": 7, "regionId": "city-1", "titles": []]) }
        return try response(state())
    }
    private func requestReads(_ wire: Wire) -> [String] {
        wire.requests.filter { $0.url!.path.contains("/request/") }.map { $0.url!.lastPathComponent }
    }

    func testOriginalQuoteSurvivesFreshJournalAndControllerWithoutNewPOST() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        wire.respond = { try self.originalResponse($0) }
        let first = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await first.open(activity: first.activityID)
        await first.requestQuote(try XCTUnwrap(first.snapshot?.candidates.first))
        let original = try XCTUnwrap(store.original()), selected = try XCTUnwrap(first.selectedQuote)
        XCTAssertNil(try store.pending()); XCTAssertEqual(selected.confirmRequestId, confirmID)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        wire.requests.removeAll()
        let reopened = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await reopened.open(activity: reopened.activityID)
        XCTAssertEqual(requestReads(wire), [original.operationID.uuidString])
        XCTAssertEqual(reopened.selectedQuote, selected)
        XCTAssertEqual(reopened.receipt?.requestId, original.operationID.uuidString)
        XCTAssertTrue(reopened.canWrite); XCTAssertNil(reopened.confirmation)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testFailedQuoteSecondReadRetainsPendingThenReopenRecoversSameIdentity() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        var fail = true
        wire.respond = { request in
            if fail && request.url!.path.contains("/quote/") { throw URLError(.timedOut) }
            return try self.originalResponse(request)
        }
        let first = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await first.load(); await first.requestQuote(try XCTUnwrap(first.snapshot?.candidates.first))
        let pending = try XCTUnwrap(store.pending())
        XCTAssertNil(try store.original()); XCTAssertNil(first.selectedQuote); XCTAssertFalse(first.canWrite)
        fail = false; wire.requests.removeAll()
        let reopened = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await reopened.open(activity: reopened.activityID)
        XCTAssertEqual(requestReads(wire), [pending.operationID.uuidString])
        XCTAssertEqual(reopened.selectedQuote?.confirmRequestId, confirmID)
        XCTAssertNil(try store.pending()); XCTAssertEqual(try store.original(), pending)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testKnownConfirmClearsPendingRetainsMarkerAndReopensOriginalTitleWithoutCharge() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        wire.respond = { try self.originalResponse($0) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.load(); await c.requestQuote(try XCTUnwrap(c.snapshot?.candidates.first))
        c.prepareConfirmation(); await c.confirm(try XCTUnwrap(c.confirmation))
        XCTAssertNil(try store.pending()); XCTAssertNil(c.pendingRequestID)
        XCTAssertEqual(try store.original()?.operationID.uuidString, confirmID)
        XCTAssertEqual(c.receipt?.title?.pointsAfter, 70)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 2)
        wire.requests.removeAll()
        let reopened = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await reopened.open(activity: reopened.activityID)
        XCTAssertEqual(requestReads(wire), [confirmID]); XCTAssertEqual(reopened.receipt?.title, c.receipt?.title)
        XCTAssertNil(reopened.selectedQuote); reopened.prepareConfirmation(); XCTAssertNil(reopened.confirmation)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testUnknownConfirmPrefersPendingOverOldQuoteMarkerWithoutFallbackOrPOST() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        let prior = try store.seed(completed: true)
        let pending = try store.seed(try XCTUnwrap(UUID(uuidString: confirmID)))
        wire.respond = { request in
            XCTAssertTrue(request.url!.path.contains("/request/"))
            return try self.response(["requestId": request.url!.lastPathComponent, "requestStatus": "UNKNOWN"], status: 202)
        }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID); await c.recover()
        XCTAssertEqual(requestReads(wire), [confirmID, confirmID])
        XCTAssertEqual(try store.pending(), pending); XCTAssertEqual(try store.original(), prior)
        XCTAssertNil(c.receipt); XCTAssertNil(c.selectedQuote); XCTAssertFalse(c.canWrite)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testChangedOriginalQuoteTermsCannotClearPendingEvenWhenIndividuallyValid() async throws {
        let mutations: [(String, Any)] = [
            ("payerMemberId", 8), ("pointCost", 31), ("confirmRequestId", UUID().uuidString),
            ("pointId", "point-2"), ("beneficiaryTeamId", "99999999-9999-9999-9999-999999999999"),
            ("actionCost", 3), ("termSeconds", 601), ("budgetVersion", 1),
            ("evidenceAcceptanceReason", "Different reason"), ("quoteHash", String(repeating: "c", count: 64))
        ]
        for (field, value) in mutations {
            let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
            defer { store.cleanup() }
            let pending = try store.seed(); var changed = quote(); changed[field] = value
            let client = service(grant, wire)
            if field != "payerMemberId" {
                let parsed = try JSONDecoder().decode(CityAcquisitionQuote.self, from: JSONSerialization.data(withJSONObject: changed))
                XCTAssertNoThrow(try client.validate(parsed), field)
            }
            wire.respond = { try self.originalResponse($0, quote: changed) }
            let c = CityAcquisitionController(service: client, journal: store.fresh())
            await c.open(activity: c.activityID)
            XCTAssertEqual(try store.pending(), pending, field); XCTAssertNil(try store.original(), field)
            XCTAssertNil(c.selectedQuote, field); XCTAssertFalse(c.canWrite, field)
            XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" }, field)
        }
    }

    func testOnlyQuoteAvailabilityFlagsMayChangeOnSecondRead() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        let pending = try store.seed(); var changed = quote(); changed["writeApproved"] = false; changed["expired"] = true
        wire.respond = { try self.originalResponse($0, quote: changed) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID)
        XCTAssertNil(try store.pending()); XCTAssertEqual(try store.original(), pending)
        XCTAssertEqual(c.selectedQuote?.expired, true); c.prepareConfirmation(); XCTAssertNil(c.confirmation)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testChangedOriginalMarkerBeforeConfirmationBlocksPOST() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        _ = try store.seed(completed: true); wire.respond = { try self.originalResponse($0) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID); c.prepareConfirmation()
        let captured = try XCTUnwrap(c.confirmation), replacement = try store.seed(completed: true)
        wire.requests.removeAll(); await c.confirm(captured)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertEqual(try store.original(), replacement)
        XCTAssertNil(try store.pending()); XCTAssertFalse(c.canWrite); XCTAssertNil(c.confirmation)
    }

    func testLoadIsStateOnlyAndOriginalMustBeRereadBeforeWriting() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        _ = try store.seed(completed: true); wire.respond = { try self.originalResponse($0) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.load()
        XCTAssertTrue(requestReads(wire).isEmpty); XCTAssertNotNil(c.snapshot); XCTAssertNil(c.receipt)
        XCTAssertFalse(c.canWrite); await c.requestQuote(try XCTUnwrap(c.snapshot?.candidates.first))
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        await c.open(activity: c.activityID); XCTAssertTrue(c.canWrite)
    }

    func testReadOnlyGrantCanRecoverOriginalButCannotConfirm() async throws {
        let grant = try approval(writes: false), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        let marker = try store.seed(completed: true); wire.respond = { try self.originalResponse($0) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID)
        XCTAssertEqual(requestReads(wire), [marker.operationID.uuidString]); XCTAssertNotNil(c.selectedQuote)
        XCTAssertFalse(c.canWrite); c.prepareConfirmation(); XCTAssertNil(c.confirmation)
        await c.confirm(try XCTUnwrap(c.selectedQuote))
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testStaleActivityAndSuspendedQueuedActionsCannotReadOrWrite() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        wire.respond = { try self.originalResponse($0) }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.load(); let candidate = try XCTUnwrap(c.snapshot?.candidates.first), old = c.activityID
        let queuedQuote = Task { @MainActor in await c.requestQuote(candidate, activity: old) }
        let queuedOpen = Task { @MainActor in await c.open(activity: old) }
        c.suspend(); wire.requests.removeAll()
        await queuedQuote.value; await queuedOpen.value
        await c.open(activity: old); await c.requestQuote(candidate, activity: old); await c.recover(activity: old)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(c.snapshot)
        c.activate(); await c.open(activity: c.activityID)
        wire.requests.removeAll()
        await c.open(activity: old); await c.requestQuote(candidate, activity: old); await c.recover(activity: old)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(try store.pending())
        await c.requestQuote(candidate, activity: c.activityID); c.prepareConfirmation()
        let captured = try XCTUnwrap(c.confirmation), capturedActivity = c.activityID
        let queuedConfirm = Task { @MainActor in await c.confirm(captured, activity: capturedActivity) }
        c.suspend(); wire.requests.removeAll(); await queuedConfirm.value
        XCTAssertTrue(wire.requests.isEmpty)
        c.activate(); await c.open(activity: c.activityID); c.prepareConfirmation()
        wire.requests.removeAll(); await c.confirm(captured, activity: capturedActivity)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertNil(try store.pending())
    }

    func testMalformedHTTP403AndEnvelopeAccessCodesHidePreviouslyVisibleFacts() async throws {
        for access in [403, 401] {
            for envelopeOnly in [false, true] {
                let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
                defer { store.cleanup() }
                _ = try store.seed(completed: true); var denied = false; var unauthorized = 0
                wire.respond = { request in
                    // Denial arrives after receipt and second quote read, when facts exist again.
                    if denied && request.url!.path.hasSuffix("/titles") {
                        return envelopeOnly ? (Data("{\"code\":\(access),\"data\":\"malformed\"}".utf8), 200) : (Data("not-json".utf8), access)
                    }
                    return try self.originalResponse(request)
                }
                let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh(), unauthorized: { unauthorized += 1 })
                await c.open(activity: c.activityID); XCTAssertNotNil(c.selectedQuote)
                denied = true; await c.recover()
                XCTAssertNil(c.receipt); XCTAssertNil(c.selectedQuote); XCTAssertNil(c.snapshot); XCTAssertTrue(c.titles.isEmpty)
                XCTAssertFalse(c.canWrite); XCTAssertNil(c.confirmation)
                XCTAssertEqual(unauthorized, access == 401 ? 1 : 0)
                XCTAssertEqual(c.messageKey, access == 401 ? "cityAcquire.status.signedOut" : "cityAcquire.status.accessWithdrawn")
            }
        }
    }

    func testMalformedErrorCodeCannotMaskEnvelope401Or403AfterQuoteRecovery() async throws {
        for access in [401, 403] {
            let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
            defer { store.cleanup() }
            let original = try store.seed()
            var unauthorized = 0
            wire.respond = { request in
                if request.url!.path.hasSuffix("/titles") {
                    let object: [String: Any] = ["code": access, "errorCode": 123, "data": "malformed"]
                    return (try JSONSerialization.data(withJSONObject: object), 200)
                }
                return try self.originalResponse(request)
            }
            let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh(), unauthorized: { unauthorized += 1 })
            await c.open(activity: c.activityID)
            XCTAssertEqual(requestReads(wire), [original.operationID.uuidString])
            XCTAssertEqual(wire.requests.filter { $0.url!.path.contains("/quote/") }.count, 1)
            // Verified original receipt and immutable second read may complete the pending lock,
            // but a malformed permission response must revoke every visible acquisition fact.
            XCTAssertNil(try store.pending()); XCTAssertEqual(try store.original(), original)
            XCTAssertEqual(c.originalRequestID, original.operationID)
            XCTAssertNil(c.receipt); XCTAssertNil(c.selectedQuote); XCTAssertNil(c.snapshot)
            XCTAssertTrue(c.titles.isEmpty); XCTAssertNil(c.confirmation); XCTAssertFalse(c.canWrite)
            XCTAssertEqual(unauthorized, access == 401 ? 1 : 0)
            XCTAssertEqual(c.messageKey, access == 401 ? "cityAcquire.status.signedOut" : "cityAcquire.status.accessWithdrawn")
            XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    func testNon4xxCompleteAndEmptyErrorCannotUnlockOriginalPending() async throws {
        for status in [201, 202, 302, 503, 409] {
            let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
            defer { store.cleanup() }
            let pending = try store.seed()
            wire.respond = { request in
                let object: [String: Any] = ["code": status, "errorCode": status == 409 ? "" : "NOT_TERMINAL", "data": ["requestId": request.url!.lastPathComponent, "requestStatus": "COMPLETE"]]
                return (try JSONSerialization.data(withJSONObject: object), status)
            }
            let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
            await c.open(activity: c.activityID)
            XCTAssertEqual(try store.pending(), pending, "HTTP \(status)"); XCTAssertNil(try store.original())
            XCTAssertFalse(c.canWrite); XCTAssertNil(c.receipt)
            XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    func testMarkerAloneIsOnlyAReadAnchorAndNeverProofOfSuccess() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        let marker = try store.seed(completed: true)
        wire.respond = { request in
            return try self.response(["requestId": request.url!.lastPathComponent, "requestStatus": "UNKNOWN"], status: 202)
        }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID)
        XCTAssertEqual(requestReads(wire), [marker.operationID.uuidString])
        XCTAssertEqual(try store.original(), marker); XCTAssertNil(try store.pending())
        XCTAssertNil(c.receipt); XCTAssertNil(c.selectedQuote); XCTAssertFalse(c.canWrite)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testNonempty4xxTerminalFailureClearsPendingAndRetainsOriginalIdentity() async throws {
        let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
        defer { store.cleanup() }
        let pending = try store.seed()
        wire.respond = { request in
            if request.url!.path.contains("/request/") {
                let object: [String: Any] = ["code": 409, "errorCode": "ALREADY_OWNED", "data": ["requestId": request.url!.lastPathComponent, "requestStatus": "COMPLETE"]]
                return (try JSONSerialization.data(withJSONObject: object), 409)
            }
            return try self.originalResponse(request)
        }
        let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
        await c.open(activity: c.activityID)
        XCTAssertNil(try store.pending()); XCTAssertEqual(try store.original(), pending)
        XCTAssertEqual(c.receipt?.succeeded, false); XCTAssertEqual(c.receipt?.errorCode, "ALREADY_OWNED")
        XCTAssertNil(c.selectedQuote); XCTAssertNil(c.confirmation)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testExplicit4xxReceiptContractAndEffectsMustAgreeWithNoExecution() async throws {
        let cases: [(String, String, Bool)] = [
            ("OTHER", "NOT_EXECUTED", false),
            ("CITY_ACQUISITION_V1", "COMMITTED", false),
            ("CITY_ACQUISITION_V1", "NOT_EXECUTED", true)
        ]
        for (contract, effects, terminal) in cases {
            let grant = try approval(), wire = Wire(), store = try OriginalStore(grant)
            defer { store.cleanup() }
            let pending = try store.seed()
            wire.respond = { request in
                if request.url!.path.contains("/request/") {
                    let object: [String: Any] = ["code": 409, "errorCode": "ALREADY_OWNED", "data": [
                        "requestId": request.url!.lastPathComponent, "requestStatus": "COMPLETE",
                        "contract": contract, "effectsStatus": effects
                    ]]
                    return (try JSONSerialization.data(withJSONObject: object), 409)
                }
                return try self.originalResponse(request)
            }
            let c = CityAcquisitionController(service: service(grant, wire), journal: store.fresh())
            await c.open(activity: c.activityID)
            XCTAssertEqual(requestReads(wire), [pending.operationID.uuidString])
            if terminal {
                XCTAssertNil(try store.pending()); XCTAssertEqual(try store.original(), pending)
                XCTAssertEqual(c.receipt?.succeeded, false)
                XCTAssertEqual(c.receipt?.errorCode, "ALREADY_OWNED")
            } else {
                XCTAssertEqual(try store.pending(), pending); XCTAssertNil(try store.original())
                XCTAssertEqual(c.pendingRequestID, pending.operationID)
                XCTAssertNil(c.receipt); XCTAssertFalse(c.canWrite)
                XCTAssertEqual(c.messageKey, "cityAcquire.status.unknown")
            }
            XCTAssertNil(c.selectedQuote); XCTAssertNil(c.confirmation)
            XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    @MainActor private final class FailingOriginalJournal: CityAcquisitionOriginalJournal {
        var failRead = false, failOriginalRead = false, failWrite = false, failReadback = false
        var record: OperationPendingRecord?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            if failRead || (failReadback && record != nil) { throw APIError.malformedResponse }
            return record
        }
        func original(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            if failRead || failOriginalRead { throw APIError.malformedResponse }; return nil
        }
        func write(_ value: OperationPendingRecord) throws {
            if failWrite { throw APIError.malformedResponse }; record = value
        }
        func clear(_ value: OperationPendingRecord) throws { throw APIError.malformedResponse }
    }
    func testJournalReadWriteAndReadbackFailureNeverPOST() async throws {
        for mode in ["read", "originalRead", "write", "readback"] {
            let grant = try approval(), wire = Wire(), journal = FailingOriginalJournal()
            wire.respond = { try self.originalResponse($0) }
            let c = CityAcquisitionController(service: service(grant, wire), journal: journal)
            await c.load(); let candidate = try XCTUnwrap(c.snapshot?.candidates.first)
            journal.failRead = mode == "read"; journal.failOriginalRead = mode == "originalRead"; journal.failWrite = mode == "write"; journal.failReadback = mode == "readback"
            wire.requests.removeAll(); await c.requestQuote(candidate)
            XCTAssertTrue(wire.requests.isEmpty, mode); XCTAssertFalse(c.canWrite, mode)
            XCTAssertNil(c.confirmation, mode)
        }
    }
}
