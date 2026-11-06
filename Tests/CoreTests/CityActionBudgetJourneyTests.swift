import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityActionBudgetJourneyTests: XCTestCase {
    private static let team = "00000000-0000-0000-0000-000000000001", session = "00000000-0000-0000-0000-000000000002"
    private static let binding: [String: Any] = ["releaseId": 1, "regionId": "region", "boardId": "board", "seasonId": "season", "rulesReleaseId": "rules",
        "contentHash": String(repeating: "a", count: 64), "revision": 1, "title": "Fake original board",
        "rules": ["mode": "CITY_TEAM", "minMembers": 1, "maxMembers": 3, "joinPolicy": "INVITE_CODE", "rosterPolicy": "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM",
            "replacementPolicy": "FORBIDDEN_AFTER_LOCK", "reentryPolicy": "RESUME_ORIGINAL_SESSION", "roundPolicy": "FIXED_PUBLISHED_ROUND", "roundId": "round"]]
    private static func state() -> [String: Any] {
        ["contract": "CITY_ACTION_BUDGET_V1", "scope": "CITY", "status": "AVAILABLE", "writeApproved": true, "binding": binding,
         "teamId": team, "sessionId": session, "teamVersion": 3, "version": 0, "usedUnits": 0, "remainingUnits": 2, "rollCount": 0,
         "movementStatus": "UNAVAILABLE", "arrivalProof": "NOT_PROVIDED", "ownershipEffect": "NONE", "pointsEffect": "NONE", "effectsStatus": "NOT_EXECUTED", "recentResults": [],
         "rules": ["scope": "TEAM_ROUND", "unit": "ACTION", "totalUnits": 2, "rollCost": 1, "refillPolicy": "NONE_WITHIN_ROUND", "chargeTiming": "COMMITTED_DICE_RESULT", "actionKind": "DICE_ROLL", "resultPolicy": "RECORD_ONLY_NO_EFFECTS"],
         "dice": ["diceId": "dice", "faces": [1, 9], "weights": [1, 3]]]
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], lastCommand: CityActionBudgetCommand?
        var unknown = false, receiptMissing = false, corruptResult = false
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            if request.url?.path.hasSuffix("/state") == true { return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": CityActionBudgetJourneyTests.state()]), 200) }
            if request.httpMethod == "POST" { lastCommand = try JSONDecoder().decode(CityActionBudgetCommand.self, from: XCTUnwrap(request.httpBody)) }
            if receiptMissing, request.httpMethod == "GET" { return (Data(#"{"code":404,"errorCode":"NOT_FOUND"}"#.utf8), 404) }
            let c = try XCTUnwrap(lastCommand)
            if unknown { return (try JSONSerialization.data(withJSONObject: ["code": 202, "errorCode": "OUTCOME_UNKNOWN", "data": ["requestId": c.requestId, "requestStatus": "UNKNOWN"]]), 202) }
            let result: [String: Any] = ["resultId": "00000000-0000-0000-0000-000000000003", "requestId": c.requestId, "rollNumber": 1, "budgetVersion": 1,
                "costUnits": 1, "beforeUnits": 2, "afterUnits": 1, "diceId": "dice", "faceIndex": 0, "faceValue": corruptResult ? 999 : 1,
                "createdAt": "2026-11-05T12:00:00.123Z", "effectsStatus": "NOT_EXECUTED", "verifier": "SERVER_WEIGHTED_SECURE_RANDOM_V1"]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": c.requestId, "requestStatus": "COMPLETE",
                "contract": "CITY_ACTION_BUDGET_V1", "scope": "CITY", "binding": CityActionBudgetJourneyTests.binding,
                "teamId": CityActionBudgetJourneyTests.team, "sessionId": CityActionBudgetJourneyTests.session, "result": result]]), 200)
        }
    }
    @MainActor private final class Harness {
        let scope: CityActionBudgetScope
        var current: CityActionBudgetScope?
        let wire = Wire()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var read: CityActionBudgetReadGrant?, command: CityActionBudgetCommandGrant?, receipt: CityOriginalReceiptReadGrant?
        init() throws {
            scope = try .init(market: .china, baseURL: URL(string: "https://city.example.test/native/")!, namespace: "test-budget", accountID: 7, epoch: 1, token: "fake-token")
            current = scope; read = .init(scope: scope, region: "region")
        }
        func model() throws -> CityActionBudgetRecovery {
            .init(configuration: try .init(baseURL: scope.session.baseURL), region: "region", transport: wire,
                journal: try .init(directory: directory), currentScope: { self.current }, readGrant: { self.read }, commandGrant: { self.command },
                receiptGrant: { reference in self.receipt?.reference == reference ? self.receipt : nil })
        }
        func authorize(_ model: CityActionBudgetRecovery) throws {
            let p = try XCTUnwrap(model.prepared); command = try .init(scope: scope, prepared: p)
            receipt = .init(reference: try .init(session: scope.session, domain: .actionBudget, requestID: p.command.requestId))
        }
    }
    func testActualStatePrepareExactSavedPostAndVerifiedOriginalResult() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); try h.authorize(m)
        let pending = try XCTUnwrap(m.prepared), expected = try pending.command.bytes()
        h.wire.beforeReply = {
            if h.wire.requests.last?.httpMethod == "POST" {
                do {
                    let journal = try CityActionBudgetJournal(directory: h.directory)
                    XCTAssertEqual(try journal.load(h.scope)?.bytes, expected)
                } catch { XCTFail("Original bytes were not saved before transport") }
            }
        }
        await m.submit(); XCTAssertEqual(m.display, .complete(200)); XCTAssertEqual(m.result?.faceValue, 1)
        XCTAssertEqual(m.result?.effectsStatus, "NOT_EXECUTED")
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.first?.httpBody, expected)
        let reopened = try h.model(); await reopened.open(); XCTAssertEqual(reopened.display, .complete(200)); XCTAssertEqual(reopened.result?.faceValue, 1)
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testUnknownRestartAnd404NeverUnlockOrResendOriginal() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); try h.authorize(m); h.wire.unknown = true
        await m.submit(); XCTAssertEqual(m.display, .unknown)
        let next = try h.model(); await next.open(); next.prepare(); XCTAssertNil(next.prepared)
        h.wire.receiptMissing = true; await next.recheck(); XCTAssertEqual(next.display, .unknown)
        await next.submit(); XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        h.wire.receiptMissing = false; h.wire.unknown = false; await next.recheck()
        XCTAssertEqual(next.display, .complete(200)); XCTAssertEqual(next.result?.faceValue, 1)
        XCTAssertEqual(h.wire.requests.last?.url?.lastPathComponent, h.wire.lastCommand?.requestId)
    }
    func testMissingGrantNeverCreatesJournalOrPosts() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); XCTAssertFalse(m.canSubmit)
        await m.submit(); XCTAssertNil(try CityActionBudgetJournal(directory: h.directory).load(h.scope))
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testCompleteStatusWithWrongFaceRemainsUnknownWithoutShowingResult() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); try h.authorize(m); h.wire.corruptResult = true
        await m.submit(); XCTAssertEqual(m.display, .unknown); XCTAssertNil(m.result)
        await m.recheck(); XCTAssertEqual(m.display, .unknown)
        XCTAssertNil(try CityActionBudgetJournal(directory: h.directory).load(h.scope)?.status)
    }
    func testLateAccountLossHidesReplyAndOriginalCanOnlyBeRechecked() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); try h.authorize(m)
        h.wire.beforeReply = { if h.wire.requests.last?.httpMethod == "POST" { h.current = nil } }
        await m.submit(); XCTAssertEqual(m.display, .hidden); XCTAssertNil(m.result)
        h.current = h.scope; h.wire.beforeReply = nil
        let next = try h.model(); await next.open(); XCTAssertEqual(next.display, .unknown)
        await next.recheck(); XCTAssertEqual(next.display, .complete(200))
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testCancelPreparationDoesNotPersistOrDispatch() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); m.prepare(); m.cancelPreparation()
        XCTAssertNil(m.prepared); XCTAssertNil(try CityActionBudgetJournal(directory: h.directory).load(h.scope))
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testReadGrantRevocationHidesPreparedSourceWithoutPosting() async throws {
        let h = try Harness(), m = try h.model(); await m.open(); XCTAssertNotNil(m.state)
        h.read?.revoke(); XCTAssertNil(m.state); m.prepare(); XCTAssertNil(m.prepared)
        XCTAssertEqual(h.wire.requests.count, 1)
    }

}
