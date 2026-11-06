import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored synthetic regressions only. No Swift/XCTest, Apple UI, real task, or network execution.
@available(macOS 14.0, *) @MainActor extension CityOnsiteTaskPortJourneyTests {
    func onsiteRecord(_ grant: CityOnsiteTaskApproval, _ id: UUID, acknowledged: Int = 0) -> OperationPendingRecord {
        .init(operationID: id, ownerKey: "city-onsite:\(grant.context.session.namespace):\(base.absoluteString):7", targetKey: "city-1:board-1:season-1", acknowledgedSteps: acknowledged)
    }
    func onsiteEnvelope(_ data: [String: Any], status: Int = 200, error: String? = nil) throws -> (Data, Int) {
        var envelope: [String: Any] = ["code": status, "data": data]
        if let error { envelope["errorCode"] = error }
        return (try JSONSerialization.data(withJSONObject: envelope), status)
    }
    func onsiteReceipt(_ id: UUID, result: [String: Any]? = nil, status: Int = 200, error: String? = nil) throws -> (Data, Int) {
        var value: [String: Any] = ["requestId": id.uuidString, "requestStatus": "COMPLETE"]
        if let result { value["result"] = result }
        return try onsiteEnvelope(value, status: status, error: error)
    }
    func onsiteResult(_ value: [String: Any]) throws -> (Data, Int) {
        try onsiteEnvelope(["contract": "CITY_ONSITE_TASK_V1", "effectsStatus": "NOT_EXECUTED", "result": value])
    }
    func onsiteController(_ grant: CityOnsiteTaskApproval, _ wire: any HTTPTransport, _ journal: any OperationPendingJournal, unauthorized: @escaping () -> Void = {}) -> CityOnsiteTaskController {
        let transport = CityOnsiteTaskTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
        return .init(service: .init(approval: grant, transport: transport, board: board), journal: journal, unauthorized: unauthorized)
    }
    func testOriginalResultFailureRetainsExactIdentityAndReopensBeforeCurrentState() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(), accept = UUID().uuidString
        let result = originalResult(accept, id.uuidString); journal.record = onsiteRecord(grant, id)
        var resultOffline = true
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
            if request.url!.path.contains("/result/") { if resultOffline { throw URLError(.timedOut) }; return try self.onsiteResult(result) }
            throw URLError(.notConnectedToInternet)
        }
        let first = onsiteController(grant, wire, journal); await first.load()
        XCTAssertEqual(first.pendingRequestID, id); XCTAssertEqual(first.receipt?.requestId, id.uuidString)
        XCTAssertNil(first.selectedResult); XCTAssertEqual(journal.record?.acknowledgedSteps, 0); XCTAssertFalse(first.canWrite)
        XCTAssertEqual(first.messageKey, "cityOnsite.status.resultUnavailable")
        XCTAssertFalse(wire.requests.contains { $0.url!.path.hasSuffix("/state") })
        first.suspend(); XCTAssertNil(first.receipt); resultOffline = false
        let reopened = onsiteController(grant, wire, journal); await reopened.load()
        XCTAssertEqual(reopened.selectedResult?.resultId, resultID); XCTAssertNil(reopened.snapshot)
        XCTAssertNil(reopened.pendingRequestID); XCTAssertEqual(journal.record?.operationID, id)
        XCTAssertEqual(journal.record?.acknowledgedSteps, 1); XCTAssertFalse(reopened.canWrite)
        XCTAssertEqual(reopened.messageKey, "cityOnsite.status.currentUnavailable")
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, [id.uuidString, resultID, id.uuidString, resultID, "state"])
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testSuccessfulResultCloseReopenAndProcessReentryUseOriginalGetsOnly() async throws {
        let grant = try approval(writes: false), wire = Wire(), journal = Journal(), id = UUID(), accept = UUID().uuidString
        let result = originalResult(accept, id.uuidString); journal.record = onsiteRecord(grant, id, acknowledged: 1)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
            if request.url!.path.contains("/result/") { return try self.onsiteResult(result) }
            return try self.response(accept, id.uuidString)
        }
        let first = onsiteController(grant, wire, journal); await first.load(); first.closeResult()
        XCTAssertNil(first.selectedResult); XCTAssertNotNil(first.receipt)
        await first.readResult(resultID); XCTAssertEqual(first.selectedResult?.requestId, id.uuidString)
        first.suspend(); XCTAssertNil(first.selectedResult)
        let reopened = onsiteController(grant, wire, journal); await reopened.load()
        XCTAssertEqual(reopened.selectedResult?.requestId, id.uuidString); XCTAssertFalse(reopened.canWrite)
        XCTAssertEqual(journal.record?.operationID, id); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testResultMustExactlyMatchAllOriginalReceiptFields() async throws {
        let changes: [String: Any] = ["instanceId": "66666666-6666-6666-6666-666666666666", "taskId": "other-task", "acceptRequestId": "other-accept", "requestId": "other-request", "pointId": "other-point", "teamId": "77777777-7777-7777-7777-777777777777", "sessionId": "88888888-8888-8888-8888-888888888888", "evidenceId": "99999999-9999-9999-9999-999999999999", "releaseId": 2, "rulesReleaseId": "other-rules", "roundId": "other-round", "contentHash": String(repeating: "d", count: 64), "taskHash": String(repeating: "e", count: 64), "evidencePolicyHash": String(repeating: "f", count: 64), "merchantId": 42, "placeId": 62, "outcome": "EXHAUSTED", "attemptNumber": 2, "createdAt": "2026-10-22T00:00:00Z", "evidenceCheckedAt": "2026-10-22T00:00:00Z", "evidenceExpiresAt": "2098-01-01T00:00:00Z"]
        for (field, changed) in changes {
            let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID()
            let original = originalResult(UUID().uuidString, id.uuidString); var altered = original; altered[field] = changed
            journal.record = onsiteRecord(grant, id)
            wire.respond = { request in
                if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: original) }
                return try self.onsiteResult(altered)
            }
            let controller = onsiteController(grant, wire, journal); await controller.load()
            XCTAssertNil(controller.selectedResult, field); XCTAssertEqual(controller.pendingRequestID, id, field)
            XCTAssertEqual(journal.record?.acknowledgedSteps, 0, field); XCTAssertFalse(controller.canWrite, field)
            XCTAssertEqual(wire.requests.count, 2, field)
        }
    }
    func testOriginalResultRereadFailureKeepsVerifiedHistoryWithoutWriteEligibility() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(), accept = UUID().uuidString
        let result = originalResult(accept, id.uuidString); journal.record = onsiteRecord(grant, id)
        var offline = false
        wire.respond = { request in
            if offline { throw URLError(.timedOut) }
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
            if request.url!.path.contains("/result/") { return try self.onsiteResult(result) }
            return try self.response(accept, id.uuidString)
        }
        let controller = onsiteController(grant, wire, journal); await controller.load(); offline = true
        await controller.readResult(resultID)
        XCTAssertEqual(controller.selectedResult?.resultId, resultID); XCTAssertNil(controller.snapshot)
        XCTAssertFalse(controller.canWrite); XCTAssertEqual(journal.record?.operationID, id)
    }
    func testExactStoredTerminalRejectionsAreNotCurrentAuthorizationOrUnknown() async throws {
        for status in [401, 403, 404, 409, 503] {
            let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); var signedOut = false
            journal.record = onsiteRecord(grant, id)
            wire.respond = { request in
                if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, status: status, error: "ORIGINAL_REJECTION") }
                return try self.response()
            }
            let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true }); await controller.load()
            XCTAssertFalse(signedOut); XCTAssertEqual(controller.receipt?.succeeded, false); XCTAssertNil(controller.pendingRequestID)
            XCTAssertEqual(controller.messageKey, "cityOnsite.status.rejected"); XCTAssertEqual(journal.record?.acknowledgedSteps, 1)
            controller.suspend(); let reopened = onsiteController(grant, wire, journal); await reopened.load()
            XCTAssertEqual(reopened.receipt?.errorCode, "ORIGINAL_REJECTION"); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }
    func testUnknownMalformedAndForeignRequestKeepIdentityAndNeverReadCurrentOrReplay() async throws {
        for shape in ["unknown", "malformed", "foreign", "invalidComplete"] {
            let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); journal.record = onsiteRecord(grant, id)
            wire.respond = { _ in
                switch shape {
                case "unknown": return try self.onsiteEnvelope(["requestId": id.uuidString, "requestStatus": "UNKNOWN"], status: 202)
                case "foreign": return try self.onsiteReceipt(UUID())
                case "invalidComplete": return try self.onsiteReceipt(id, status: 202)
                default: return (Data("unavailable".utf8), 503)
                }
            }
            let controller = onsiteController(grant, wire, journal); await controller.load(); await controller.recover()
            XCTAssertNil(controller.receipt); XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.canWrite)
            XCTAssertEqual(controller.pendingRequestID, id); XCTAssertEqual(journal.record?.acknowledgedSteps, 0)
            XCTAssertEqual(wire.requests.count, 2); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.url!.lastPathComponent == id.uuidString })
        }
    }
    func testBareAndBodyDenialsPrecedeMalformedResultDecoding() async throws {
        for status in [401, 403] {
            for http in [200, status] {
                let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); var signedOut = false
                journal.record = onsiteRecord(grant, id)
                wire.respond = { request in
                    if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: self.originalResult(UUID().uuidString, id.uuidString)) }
                    return (Data("{\"code\":\(status),\"data\":\"invalid-result\"}".utf8), http)
                }
                let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true }); await controller.load()
                XCTAssertEqual(signedOut, status == 401); XCTAssertNil(controller.receipt); XCTAssertNil(controller.selectedResult)
                XCTAssertNil(controller.snapshot); XCTAssertNil(controller.originalRequestID); XCTAssertFalse(controller.canWrite)
                XCTAssertEqual(journal.record?.operationID, id)
            }
        }
    }
    func testBareReceiptDenialCannotBecomeStoredRejection() async throws {
        for status in [401, 403] {
            let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); var signedOut = false
            journal.record = onsiteRecord(grant, id)
            wire.respond = { _ in (Data("{\"code\":\(status),\"errorCode\":\"DENIED\",\"data\":\"invalid\"}".utf8), status) }
            let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true }); await controller.load()
            XCTAssertEqual(signedOut, status == 401); XCTAssertNil(controller.receipt); XCTAssertEqual(journal.record?.acknowledgedSteps, 0)
            XCTAssertFalse(controller.canWrite); XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testHistoricalResultDoesNotMakeCurrentWriteApproval() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); journal.record = onsiteRecord(grant, id)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id) }
            var envelope = try JSONSerialization.jsonObject(with: self.response().0) as! [String: Any]
            var data = envelope["data"] as! [String: Any]; data["writeApproved"] = false
            var tasks = data["tasks"] as! [[String: Any]]; tasks[0]["canAct"] = false; data["tasks"] = tasks; envelope["data"] = data
            return (try JSONSerialization.data(withJSONObject: envelope), 200)
        }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        XCTAssertNotNil(controller.receipt); XCTAssertFalse(controller.canWrite)
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); XCTAssertNil(controller.confirmation)
    }
    func testCurrentStateCanBeUnavailableWithoutDiscardingOriginalRejectedReceipt() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); journal.record = onsiteRecord(grant, id)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, status: 409, error: "EVIDENCE_EXPIRED") }
            return (Data("source unavailable".utf8), 503)
        }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        XCTAssertEqual(controller.receipt?.succeeded, false); XCTAssertEqual(controller.receipt?.errorCode, "EVIDENCE_EXPIRED")
        XCTAssertNil(controller.pendingRequestID); XCTAssertEqual(journal.record?.acknowledgedSteps, 1); XCTAssertFalse(controller.canWrite)
    }
    func testFreshConfirmationReplacesOnlyReauthorizedOriginalIdentityWithoutClear() async throws {
        let grant = try approval(), wire = Wire(), journal = OnsiteCheckedJournal(), old = UUID()
        journal.record = onsiteRecord(grant, old, acknowledged: 1); var newID: UUID?
        wire.respond = { request in
            if request.httpMethod == "POST" { let data = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]; newID = UUID(uuidString: data["requestId"] as! String); return try self.response() }
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(UUID(uuidString: request.url!.lastPathComponent)!) }
            return try self.response()
        }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); await controller.confirm(try XCTUnwrap(controller.confirmation))
        XCTAssertNotEqual(newID, old); XCTAssertEqual(journal.record?.operationID, newID)
        XCTAssertEqual(journal.replacements, 1); XCTAssertEqual(journal.clears, 0); XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testReplacementFailurePreservesOriginalAndSendsNothing() async throws {
        let grant = try approval(), wire = Wire(), journal = OnsiteCheckedJournal(), old = UUID()
        journal.record = onsiteRecord(grant, old, acknowledged: 1); journal.failReplace = true
        wire.respond = { request in if request.url!.path.contains("/request/") { return try self.onsiteReceipt(old) }; return try self.response() }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); await controller.confirm(try XCTUnwrap(controller.confirmation))
        XCTAssertEqual(journal.record?.operationID, old); XCTAssertEqual(controller.receipt?.requestId, old.uuidString)
        XCTAssertFalse(controller.canWrite); XCTAssertEqual(journal.clears, 0); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testAcknowledgementFailureRetainsVerifiedResultButBlocksNewWrite() async throws {
        let grant = try approval(), wire = Wire(), journal = OnsiteCheckedJournal(), id = UUID()
        let result = originalResult(UUID().uuidString, id.uuidString); journal.record = onsiteRecord(grant, id); journal.failWrite = true
        wire.respond = { request in if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }; return try self.onsiteResult(result) }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        XCTAssertEqual(controller.selectedResult?.resultId, resultID); XCTAssertEqual(controller.pendingRequestID, id)
        XCTAssertFalse(controller.canWrite); XCTAssertEqual(controller.messageKey, "cityOnsite.status.journalUnavailable")
        XCTAssertEqual(journal.record?.acknowledgedSteps, 0); XCTAssertEqual(wire.requests.count, 2)
    }
    func testUnsupportedJournalCannotDeleteOriginalToMakeNewRequest() async throws {
        let grant = try approval(), wire = Wire(), journal = OnsiteLegacyJournal(), old = UUID()
        journal.record = onsiteRecord(grant, old, acknowledged: 1)
        wire.respond = { request in if request.url!.path.contains("/request/") { return try self.onsiteReceipt(old) }; return try self.response() }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); await controller.confirm(try XCTUnwrap(controller.confirmation))
        XCTAssertEqual(journal.record?.operationID, old); XCTAssertEqual(journal.clears, 0)
        XCTAssertFalse(controller.canWrite); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testOldActivityAndQueuedConfirmationCannotDispatchAfterSuspendOrReentry() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(); wire.respond = { _ in try self.response() }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); let captured = try XCTUnwrap(controller.confirmation), activity = controller.activityID
        controller.suspend(); await controller.confirm(captured); await controller.load(activity: activity); await controller.recover(activity: activity)
        controller.activate(); await controller.load(activity: activity); await controller.confirm(captured)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertNil(journal.record); XCTAssertNil(controller.confirmation)
    }
    func testSuspensionDuringPostKeepsOriginalJournalAndIgnoresLateReply() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal()
        var controller: CityOnsiteTaskController!
        wire.respond = { request in if request.httpMethod == "POST" { controller.suspend() }; return try self.response() }
        controller = onsiteController(grant, wire, journal); await controller.load()
        controller.prepare(try XCTUnwrap(controller.snapshot?.tasks.first)); await controller.confirm(try XCTUnwrap(controller.confirmation))
        XCTAssertNil(controller.receipt); XCTAssertNil(controller.selectedResult); XCTAssertNotNil(journal.record)
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertFalse(wire.requests.contains { $0.url!.path.contains("/request/") })
    }
    func testRevocationImmediatelyHidesAlreadyVerifiedResult() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(), accept = UUID().uuidString
        let result = originalResult(accept, id.uuidString); journal.record = onsiteRecord(grant, id)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
            if request.url!.path.contains("/result/") { return try self.onsiteResult(result) }
            return try self.response(accept, id.uuidString)
        }
        let controller = onsiteController(grant, wire, journal); await controller.load(); XCTAssertNotNil(controller.selectedResult)
        grant.revoke(); XCTAssertNil(controller.receipt); XCTAssertNil(controller.selectedResult); XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.canWrite)
        let count = wire.requests.count; await controller.readResult(resultID); XCTAssertEqual(wire.requests.count, count)
    }
    func testChangedOriginalReceiptCannotReplacePreviouslyVerifiedFacts() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); journal.record = onsiteRecord(grant, id)
        var changed = false
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, status: changed ? 409 : 200, error: changed ? "CHANGED" : nil) }
            return try self.response()
        }
        let controller = onsiteController(grant, wire, journal); await controller.load(); changed = true; await controller.recover()
        XCTAssertEqual(controller.receipt?.succeeded, true); XCTAssertEqual(controller.pendingRequestID, id)
        XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.canWrite)
    }
    func testNonJSONAuthorizationFailureClearsOriginalFacts() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(); var signedOut = false
        journal.record = onsiteRecord(grant, id)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: self.originalResult(UUID().uuidString, id.uuidString)) }
            return (Data("authentication required".utf8), 401)
        }
        let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true }); await controller.load()
        XCTAssertTrue(signedOut); XCTAssertNil(controller.receipt); XCTAssertNil(controller.selectedResult)
        XCTAssertEqual(journal.record?.operationID, id); XCTAssertFalse(controller.canWrite)
    }
    func testExpiredHistoricalEvidenceRemainsReadableWithoutCurrentQualification() async throws {
        let grant = try approval(writes: false), wire = Wire(), journal = Journal(), id = UUID()
        var result = originalResult(UUID().uuidString, id.uuidString)
        result["evidenceExpiresAt"] = "2026-10-21T00:03:00Z"; journal.record = onsiteRecord(grant, id)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
            if request.url!.path.contains("/result/") { return try self.onsiteResult(result) }
            return (Data("original board unavailable".utf8), 503)
        }
        let controller = onsiteController(grant, wire, journal); await controller.load()
        XCTAssertEqual(controller.selectedResult?.evidenceExpiresAt, "2026-10-21T00:03:00Z")
        XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.canWrite); XCTAssertEqual(journal.record?.acknowledgedSteps, 1)
    }
    func testCallerCancellationSuppressesLateResultAndUnauthorizedCallback() async throws {
        let grant = try approval(), wire = OnsiteDelayedWire(), journal = Journal(), id = UUID(); var signedOut = false
        journal.record = onsiteRecord(grant, id)
        let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true })
        let task = Task { await controller.load() }; await wire.waitUntilStarted()
        task.cancel(); wire.finish((Data("expired account".utf8), 401)); await task.value
        XCTAssertFalse(signedOut); XCTAssertNil(controller.receipt); XCTAssertNil(controller.selectedResult)
        XCTAssertFalse(controller.busy); XCTAssertFalse(controller.canWrite); XCTAssertEqual(journal.record?.operationID, id)
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testDismissedReadCannotRepopulateAfterNewActivity() async throws {
        let grant = try approval(), wire = OnsiteDelayedWire(), journal = Journal(), id = UUID()
        journal.record = onsiteRecord(grant, id)
        let controller = onsiteController(grant, wire, journal)
        let task = Task { await controller.load() }; await wire.waitUntilStarted()
        controller.suspend(); controller.activate(); wire.finish(try onsiteReceipt(id)); await task.value
        XCTAssertNil(controller.receipt); XCTAssertNil(controller.snapshot); XCTAssertNil(controller.selectedResult)
        XCTAssertFalse(controller.busy); XCTAssertEqual(journal.record?.acknowledgedSteps, 0); XCTAssertEqual(wire.requests.count, 1)
    }
    func testChangedDurableIdentityCannotKeepAnotherRequestsResult() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal(), firstID = UUID(), secondID = UUID(), accept = UUID().uuidString
        var currentID = firstID
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.onsiteReceipt(currentID, result: self.originalResult(accept, currentID.uuidString)) }
            if request.url!.path.contains("/result/") {
                if currentID == firstID { return try self.onsiteResult(self.originalResult(accept, firstID.uuidString)) }
                throw URLError(.timedOut)
            }
            return try self.response(accept, firstID.uuidString)
        }
        let controller = onsiteController(grant, wire, journal)
        journal.record = onsiteRecord(grant, firstID); await controller.load()
        XCTAssertEqual(controller.receipt?.requestId, firstID.uuidString); XCTAssertNotNil(controller.selectedResult)
        currentID = secondID; journal.record = onsiteRecord(grant, secondID); await controller.recover()
        XCTAssertEqual(controller.receipt?.requestId, secondID.uuidString); XCTAssertNil(controller.selectedResult)
        XCTAssertEqual(controller.pendingRequestID, secondID); XCTAssertFalse(controller.canWrite)
    }
    func testMalformedErrorCodeCannotHideBodyAuthorizationDenial() async throws {
        for status in [401, 403] {
            let grant = try approval(), wire = Wire(), journal = Journal(), id = UUID(), accept = UUID().uuidString
            let result = originalResult(accept, id.uuidString); journal.record = onsiteRecord(grant, id)
            var denied = false, signedOut = false
            wire.respond = { request in
                if denied { return (Data("{\"code\":\(status),\"errorCode\":{},\"data\":\"invalid\"}".utf8), 200) }
                if request.url!.path.contains("/request/") { return try self.onsiteReceipt(id, result: result) }
                if request.url!.path.contains("/result/") { return try self.onsiteResult(result) }
                return try self.response(accept, id.uuidString)
            }
            let controller = onsiteController(grant, wire, journal, unauthorized: { signedOut = true }); await controller.load()
            XCTAssertNotNil(controller.selectedResult); denied = true; await controller.readResult(resultID)
            XCTAssertEqual(signedOut, status == 401); XCTAssertNil(controller.selectedResult); XCTAssertNil(controller.receipt)
            XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.canWrite); XCTAssertEqual(journal.record?.operationID, id)
        }
    }
    func testRecoveryJournalPersistsIdentityOnly() throws {
        let grant = try approval(), id = UUID(), record = onsiteRecord(grant, id, acknowledged: 1)
        let data = try JSONEncoder().encode(record), text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for sensitive in ["synthetic-token", "optionId", "resultId", "evidenceId", "teamId", "question", "PASSED"] { XCTAssertFalse(text.contains(sensitive)) }
        XCTAssertTrue(text.contains(id.uuidString)); XCTAssertEqual(record.acknowledgedSteps, 1)
    }
    @MainActor final class OnsiteDelayedWire: HTTPTransport {
        var requests: [URLRequest] = []
        private var response: CheckedContinuation<(Data, Int), Error>?
        private var started: CheckedContinuation<Void, Never>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try await withCheckedThrowingContinuation { continuation in
                response = continuation; started?.resume(); started = nil
            }
        }
        func waitUntilStarted() async {
            if response != nil { return }
            await withCheckedContinuation { started = $0 }
        }
        func finish(_ value: (Data, Int)) { response?.resume(returning: value); response = nil }
    }
    @MainActor class OnsiteLegacyJournal: OperationPendingJournal {
        var record: OperationPendingRecord?; var clears = 0
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record }
        func write(_ value: OperationPendingRecord) throws { guard record == nil || record?.operationID == value.operationID else { throw APIError.invalidRequest }; record = value }
        func clear(_ value: OperationPendingRecord) throws { clears += 1; guard record == value else { throw APIError.invalidRequest }; record = nil }
    }
    @MainActor final class OnsiteCheckedJournal: OnsiteLegacyJournal, OperationPendingReplacing {
        var replacements = 0; var failReplace = false; var failWrite = false
        override func write(_ value: OperationPendingRecord) throws { if failWrite { throw APIError.invalidRequest }; try super.write(value) }
        func replace(_ previous: OperationPendingRecord, with next: OperationPendingRecord) throws {
            if failReplace { throw APIError.invalidRequest }
            guard record == previous, previous.ownerKey == next.ownerKey, previous.targetKey == next.targetKey else { throw APIError.invalidRequest }
            replacements += 1; record = next
        }
    }
}
