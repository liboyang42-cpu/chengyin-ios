import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored only: these tests require the supported Swift toolchain; they were not executed here.
@available(macOS 14.0, *) @MainActor final class CityNeutralTaskPortRecoveryTests: XCTestCase {
    private let requestID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let base = URL(string: "https://example.test/native")!
    private func task(_ status: String = "PASSED", request: String? = nil) throws -> CityNeutralTask {
        var value: [String: Any] = [
            "definition": ["taskId": "neutral-1", "title": "Neutral task", "type": "QA_PICK", "access": "REMOTE_NEUTRAL", "arrivalRequirement": "NONE", "scope": "TEAM_ROUND", "question": "Choose", "options": [["id": "a", "label": "Alpha"], ["id": "b", "label": "Beta"]], "maxAttempts": 2, "pointCost": 0, "pointReward": 0, "actionCost": 0],
            "status": status, "version": status == "ACTIVE" ? 1 : 3, "attempts": status == "ACTIVE" ? 0 : 2,
            "instanceId": "11111111-1111-1111-1111-111111111111", "acceptedAt": "2026-10-23T00:00:00Z"
        ]
        if status != "ACTIVE" {
            value["result"] = ["resultId": "22222222-2222-2222-2222-222222222222", "outcome": status, "requestId": request ?? requestID.uuidString, "createdAt": "2026-10-23T00:00:10Z", "verifier": "NATIVE_OBJECTIVE_QA_PICK_V1", "attemptNumber": 2]
        }
        return try JSONDecoder().decode(CityNeutralTask.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private func receipt(_ task: CityNeutralTask) -> CityNeutralTaskReceipt {
        .init(requestId: requestID.uuidString, succeeded: true, errorCode: nil, task: task)
    }
    private func wireReceipt(_ task: CityNeutralTask, id: String? = nil) throws -> (Data, Int) {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task))
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["contract": "CITY_NEUTRAL_TASK_V1", "scope": "CITY", "requestId": id ?? requestID.uuidString, "requestStatus": "COMPLETE", "task": encoded]]), 200)
    }
    private func client(_ wire: Wire) throws -> (CityNeutralTaskService, CityNeutralTaskApproval) {
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "neutral-result", token: "synthetic-token"))
        let approval = try CityNeutralTaskApproval(context: context, regionID: "city-1", allowsWrite: false, expiresAt: Date().addingTimeInterval(600))
        let board = CityReadBoard(gameId: "game-1", boardId: "board-1", regionId: "city-1", seasonId: "season-1", rulesReleaseId: "release-1", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "CITY", revision: 1)
        return (.init(approval: approval, transport: .init(approval: approval, underlying: wire, current: { context }, selected: { _ in approval }), board: board), approval)
    }
    func testAcceptAndWrongAnswerStayActiveNotPassed() throws {
        let active = try task("ACTIVE")
        XCTAssertNoThrow(try CityNeutralTaskResultRecovery.validate(active, requestID: requestID.uuidString))
        XCTAssertNil(active.result)
        var wrongAnswer = try JSONSerialization.jsonObject(with: JSONEncoder().encode(active)) as! [String: Any]
        wrongAnswer["attempts"] = 1; wrongAnswer["version"] = 2
        let snapshot = try JSONDecoder().decode(CityNeutralTask.self, from: JSONSerialization.data(withJSONObject: wrongAnswer))
        XCTAssertNoThrow(try CityNeutralTaskResultRecovery.validate(snapshot, requestID: requestID.uuidString))
        XCTAssertNil(snapshot.result)
    }
    func testTerminalResultMustBelongToExactOriginalRequest() throws {
        XCTAssertThrowsError(try CityNeutralTaskResultRecovery.validate(task(request: UUID().uuidString), requestID: requestID.uuidString))
        XCTAssertNoThrow(try CityNeutralTaskResultRecovery.validate(task(), requestID: requestID.uuidString))
        XCTAssertNoThrow(try CityNeutralTaskResultRecovery.validate(task("EXHAUSTED"), requestID: requestID.uuidString))
    }
    func testZeroEffectAndFrozenAttemptRulesAreNotWeakened() throws {
        for key in ["pointCost", "pointReward", "actionCost"] {
            var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task())) as! [String: Any]
            var definition = value["definition"] as! [String: Any]; definition[key] = 1; value["definition"] = definition
            let invalid = try JSONDecoder().decode(CityNeutralTask.self, from: JSONSerialization.data(withJSONObject: value))
            XCTAssertThrowsError(try CityNeutralTaskResultRecovery.validate(invalid, requestID: requestID.uuidString))
        }
        var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(task())) as! [String: Any]
        value["version"] = 99
        XCTAssertThrowsError(try CityNeutralTaskResultRecovery.validate(JSONDecoder().decode(CityNeutralTask.self, from: JSONSerialization.data(withJSONObject: value)), requestID: requestID.uuidString))
    }
    func testOriginalReloadUsesOnlySameReadWithoutWriteGrant() async throws {
        let wire = Wire(), original = try task(); let (service, _) = try client(wire)
        wire.respond = { _ in try self.wireReceipt(original) }
        let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
        await controller.load()
        XCTAssertEqual(controller.task, original)
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(wire.requests.first?.url?.lastPathComponent, requestID.uuidString)
    }
    func testOrdinaryFailureKeepsPreviouslyVerifiedOriginal() async throws {
        let wire = Wire(), original = try task(); let (service, _) = try client(wire)
        wire.respond = { _ in throw URLError(.timedOut) }
        let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
        await controller.load()
        XCTAssertEqual(controller.task, original); XCTAssertEqual(controller.messageKey, "cityNeutralResult.refreshFailed")
    }
    func testCurrentOrDifferentTaskCannotReplaceOriginalReceipt() async throws {
        let wire = Wire(), original = try task("ACTIVE"), later = try task(); let (service, _) = try client(wire)
        wire.respond = { _ in try self.wireReceipt(later) }
        let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
        await controller.load()
        XCTAssertEqual(controller.task, original); XCTAssertEqual(controller.messageKey, "cityNeutralResult.refreshFailed")
    }
    func test403AndRevocationClearVisibleOriginal() async throws {
        for status in [401, 403] {
            let wire = Wire(), original = try task(); let (service, _) = try client(wire)
            wire.respond = { _ in (Data(), status) }
            let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
            await controller.load(); XCTAssertNil(controller.task)
        }
        let wire = Wire(); let (service, approval) = try client(wire)
        let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(try task())))
        approval.revoke(); await controller.load(); XCTAssertNil(controller.task); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testSuccessWithoutOriginalTaskNeverBecomesResult() async throws {
        let wire = Wire(); let (service, _) = try client(wire)
        wire.respond = { _ in (Data("{\"code\":200,\"data\":{\"requestId\":\"\(self.requestID.uuidString)\",\"requestStatus\":\"COMPLETE\"}}".utf8), 200) }
        do { _ = try await service.receipt(requestID); XCTFail("No original result evidence") } catch {}
    }
    func testReceiptSurvivesStateFailureAndResultNavigation() async throws {
        let wire = Wire(), original = try task(); let (service, _) = try client(wire)
        let journal = Journal(record: pending())
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.wireReceipt(original) }
            throw URLError(.notConnectedToInternet)
        }
        let parent = CityNeutralTaskController(service: service, journal: journal)
        await parent.recover()
        XCTAssertNil(journal.record); XCTAssertNil(parent.snapshot); XCTAssertEqual(parent.receipt?.task, original)
        let child = try XCTUnwrap(parent.makeResultRecoveryController())
        parent.suspendForResult()
        XCTAssertFalse(parent.canWrite); XCTAssertEqual(parent.receipt?.task, original)
        await child.load(); XCTAssertEqual(child.task, original)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testState403ClearsVerifiedReceiptEvenWithInvalidErrorBody() async throws {
        let wire = Wire(), original = try task(); let (service, _) = try client(wire)
        wire.respond = { request in request.url!.path.contains("/request/") ? try self.wireReceipt(original) : (Data(), 403) }
        let parent = CityNeutralTaskController(service: service, journal: Journal(record: pending()))
        await parent.recover(); XCTAssertNil(parent.receipt); XCTAssertNil(parent.makeResultRecoveryController())
    }
    func testUnknownKeepsOriginalPendingAndNeverWritesOrCreatesResult() async throws {
        let wire = Wire(); let (service, _) = try client(wire); let journal = Journal(record: pending())
        wire.respond = { _ in (Data("{\"code\":202,\"data\":{\"requestId\":\"\(self.requestID.uuidString)\",\"requestStatus\":\"UNKNOWN\"}}".utf8), 202) }
        let parent = CityNeutralTaskController(service: service, journal: journal)
        await parent.recover()
        XCTAssertEqual(journal.record?.operationID, requestID); XCTAssertNil(parent.receipt)
        XCTAssertNil(parent.makeResultRecoveryController()); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(wire.requests.first?.httpMethod, "GET")
    }
    func testDismissedAndRevokedReadsCannotRestoreSnapshot() async throws {
        let wire = Wire(), original = try task(); let (service, approval) = try client(wire)
        let controller = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
        wire.respond = { _ in controller.invalidate(); return try self.wireReceipt(original) }
        await controller.load(); XCTAssertNil(controller.task)
        wire.respond = { _ in approval.revoke(); return try self.wireReceipt(original) }
        await controller.load(); XCTAssertNil(controller.task)
    }
    func testBodyDenialIsRecognizedBeforeMalformedTaskData() async throws {
        for code in [401, 403] {
            let wire = Wire(), original = try task(); let (service, _) = try client(wire)
            wire.respond = { _ in (Data("{\"code\":\(code),\"errorCode\":{},\"data\":{\"task\":false}}".utf8), 200) }
            let child = try XCTUnwrap(CityNeutralTaskResultRecoveryController(service: service, receipt: receipt(original)))
            await child.load(); XCTAssertNil(child.task)
            do { _ = try await service.state(); XCTFail("Denied state") }
            catch {
                if code == 401 { XCTAssertEqual(error as? APIError, .unauthorized) }
                else { XCTAssertEqual(error as? CityNeutralTaskError, .server(403, "FORBIDDEN")) }
            }
        }
    }
    func testChild403RetiresParentReceiptSoBackCannotReopenCachedResult() async throws {
        let wire = Wire(), original = try task(); let (service, _) = try client(wire)
        wire.respond = { request in
            if request.url!.path.contains("/request/") { return try self.wireReceipt(original) }
            throw URLError(.notConnectedToInternet)
        }
        let parent = CityNeutralTaskController(service: service, journal: Journal(record: pending()))
        await parent.recover(); let child = try XCTUnwrap(parent.makeResultRecoveryController())
        parent.suspendForResult(); wire.respond = { _ in (Data(), 403) }
        await child.load()
        XCTAssertNil(child.task); XCTAssertNil(parent.receipt); XCTAssertNil(parent.makeResultRecoveryController())
    }
    private func pending() -> OperationPendingRecord {
        .init(operationID: requestID, ownerKey: "city-neutral:neutral-result:\(base.absoluteString):7", targetKey: "city-1:board-1:season-1")
    }
    @MainActor private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        init(record: OperationPendingRecord?) { self.record = record }
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }; return record
        }
        func write(_ value: OperationPendingRecord) throws { XCTFail("Read-only recovery must not create another request") }
        func clear(_ value: OperationPendingRecord) throws {
            guard record == value else { throw APIError.invalidRequest }; record = nil
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var respond: ((URLRequest) throws -> (Data, Int))?
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try respond?(request) ?? (Data(), 500) }
    }
}
