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
        {"schema":"mod-installation-native-runtime-v1","status":"SUPPORTED","kind":"CHOICE","sourceHash":"\(hash)","runHash":"\(runHash)","sessionId":"8","activityId":"1","topicId":"2","nodeId":"5"}
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

    func testRegisteredArtifactReceiptDoesNotAdmitH5() throws {
        let receipt = Data("""
        {"moduleId":"mod-1","releaseId":"rel-1","contentHash":"\(hash)","title":"door","contentApprovalReference":"audit-task:4","schema":"w18-native-text-template-v1","requiredBindings":[]}
        """.utf8)
        let freeze = try WorkshopOriginalLedgerSplit().acceptRegisteredArtifact(receipt, moduleID: "mod-1", releaseID: "rel-1")
        XCTAssertFalse(freeze.h5Admitted)
        XCTAssertNil(freeze.sdkVersion)
        XCTAssertEqual(freeze.contentHash, hash)
        let internalRow = Data("""
        {"moduleId":"mod-1","releaseId":"rel-1","contentHash":"\(hash)","title":"door","contentApprovalReference":"audit-task:4","schema":"w18-native-text-template-v1","requiredBindings":[],"status":"ACTIVE","template":{"title":"<script>"}}
        """.utf8)
        XCTAssertThrowsError(try WorkshopOriginalLedgerSplit().acceptRegisteredArtifact(
            internalRow, moduleID: "mod-1", releaseID: "rel-1")) { error in
            XCTAssertEqual(error as? WorkshopOriginalLedgerError, .mixed)
        }
    }

    func testLargeActivityIdStaysLongAndFractionIsNotAVersion() async throws {
        let source = LedgerRead()
        source.game = Data(#"{"receiptId":"1","activityId":"9007199254740993","requestId":"req-large","action":"MOVE","outcome":"FAILED","reasonCode":"GAME_BAD_REQUEST","replayed":false,"result":{"reason":"synthetic"}}"#.utf8)
        let fact = try await WorkshopOriginalLedgerSplit().readGameSession(
            activityID: 9007199254740993, memberID: 3, requestID: "req-large", source: source)
        XCTAssertEqual(fact.activityID, 9007199254740993)
        XCTAssertEqual(fact.outcome, "FAILED")
        XCTAssertEqual(fact.reasonCode, "GAME_BAD_REQUEST")
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
    func gameSession(activityID: Int64, memberID: Int64, requestID: String) async throws -> Data? { game }
    func advancedState(sessionID: Int64, memberID: Int64) async throws -> Data? { advanced }
}
