import XCTest
@testable import QuestifyCore

final class WorkshopOriginalLedgerSplitTests: XCTestCase {
    private let hash = String(repeating: "ab", count: 32)
    private let runHash = String(repeating: "cd", count: 32)

    func testAppliedCommandDoesNotGrantServerPassAndMissingStaysPending() async throws {
        let source = LedgerRead()
        source.game = Data(#"{"receiptId":"4","activityId":"9","requestId":"req-1","action":"MOVE","outcome":"APPLIED","replayed":false,"revision":"2"}"#.utf8)
        let split = WorkshopOriginalLedgerSplit()
        let applied = try await split.readGameSession(activityID: 9, memberID: 3, requestID: "req-1", source: source)
        XCTAssertEqual(applied.outcome, "APPLIED")
        XCTAssertFalse(applied.grantsServerPass)
        XCTAssertTrue(applied.confirmed)
        XCTAssertEqual(applied.receiptID, 4)
        source.game = nil
        let pending = try await split.readGameSession(activityID: 9, memberID: 3, requestID: "req-1", source: source)
        XCTAssertEqual(pending.outcome, "PENDING")
        XCTAssertFalse(pending.confirmed)
        XCTAssertFalse(pending.grantsServerPass)
    }

    func testAdvancedProvenanceIsNotACommandReceipt() async throws {
        let source = LedgerRead()
        source.advanced = Data("""
        {"sourceHash":"\(hash)","runHash":"\(runHash)","session":"8","topic":"2","node":"5","kind":"CHOICE"}
        """.utf8)
        let fact = try await WorkshopOriginalLedgerSplit().readAdvanced(sessionID: 8, memberID: 3, source: source)
        XCTAssertFalse(fact.isCommandReceipt)
        XCTAssertFalse(fact.grantsServerPass)
        XCTAssertEqual(fact.nodeID, 5)
        source.advanced = Data(#"{"activityId":9,"requestId":"req-1","outcome":"APPLIED","replayed":true}"#.utf8)
        do {
            _ = try await WorkshopOriginalLedgerSplit().readAdvanced(sessionID: 8, memberID: 3, source: source)
            XCTFail("mixed")
        } catch let error as WorkshopOriginalLedgerError {
            XCTAssertEqual(error, .mixed)
        }
    }

    func testNativeFreezeRejectsExecutableTextAndDoesNotAdmitH5() async throws {
        let source = LedgerRead()
        source.artifact = Data("""
        {"moduleId":"mod-1","releaseId":"rel-1","contentHash":"\(hash)","status":"ACTIVE","template":{"title":"door"}}
        """.utf8)
        let freeze = try await WorkshopOriginalLedgerSplit().readArtifactFreeze(
            moduleID: "mod-1", releaseID: "rel-1", memberID: 3, source: source)
        XCTAssertFalse(freeze.h5Admitted)
        XCTAssertNil(freeze.sdkVersion)
        XCTAssertEqual(freeze.contentHash, hash)
        source.artifact = Data("""
        {"moduleId":"mod-1","releaseId":"rel-1","contentHash":"\(hash)","status":"ACTIVE","template":{"title":"<script>"}}
        """.utf8)
        do {
            _ = try await WorkshopOriginalLedgerSplit().readArtifactFreeze(
                moduleID: "mod-1", releaseID: "rel-1", memberID: 3, source: source)
            XCTFail("script")
        } catch let error as WorkshopOriginalLedgerError {
            XCTAssertEqual(error, .unknown)
        }
    }

    func testLargeActivityIdStaysLongAndFractionIsNotAVersion() async throws {
        let source = LedgerRead()
        source.game = Data(#"{"receiptId":"1","activityId":"9007199254740993","requestId":"req-large","action":"MOVE","outcome":"UNKNOWN","replayed":false,"revision":"1"}"#.utf8)
        let fact = try await WorkshopOriginalLedgerSplit().readGameSession(
            activityID: 9007199254740993, memberID: 3, requestID: "req-large", source: source)
        XCTAssertEqual(fact.activityID, 9007199254740993)
        XCTAssertEqual(fact.outcome, "UNKNOWN")
        XCTAssertFalse(fact.grantsServerPass)
        source.game = Data(#"{"receiptId":1.5,"activityId":9,"requestId":"req-1","action":"MOVE","outcome":"APPLIED","replayed":false}"#.utf8)
        do {
            _ = try await WorkshopOriginalLedgerSplit().readGameSession(activityID: 9, memberID: 3, requestID: "req-1", source: source)
            XCTFail("fraction")
        } catch let error as WorkshopOriginalLedgerError {
            XCTAssertEqual(error, .unknown)
        }
    }
}

private final class LedgerRead: WorkshopOriginalLedgerReading {
    var game: Data?
    var advanced: Data?
    var artifact: Data?
    func gameSession(activityID: Int64, memberID: Int64, requestID: String) async throws -> Data? { game }
    func advancedState(sessionID: Int64, memberID: Int64) async throws -> Data? { advanced }
    func artifact(moduleID: String, releaseID: String) async throws -> Data? { artifact }
}
