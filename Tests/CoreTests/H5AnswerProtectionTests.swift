import XCTest
@testable import QuestifyCore

final class H5AnswerProtectionTests: XCTestCase {
    private let hash = String(repeating: "ab", count: 32)
    private let other = String(repeating: "cd", count: 32)
    func testAnswersNeverInClientPackAndJSReportCannotSucceed() {
        var protection = H5AnswerProtection()
        XCTAssertThrowsError(try protection.compareClientPackAnswers(["answer": "42"])) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .answersMustNotShipInClientPack)
        }
        XCTAssertThrowsError(try H5AnswerProtection.inspectClientPack(["hiddenLat": "31.2"])) { error in
            XCTAssertEqual(error as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertThrowsError(try protection.succeedFromJSReport()) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .jsSelfReportRejected)
        }
        XCTAssertThrowsError(try protection.succeedFromClientClock(Date(timeIntervalSince1970: 1))) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .clientClockCannotSucceed)
        }
        XCTAssertNotEqual(protection.phase, .matched)
    }
    func testServerFrozenAuthorVersionCompareOnly() throws {
        var protection = H5AnswerProtection()
        XCTAssertThrowsError(try protection.compareServerFrozenAuthorVersion(
            serverFrozenHash: hash, expectedHash: other, originalRequestID: "req-a1")) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .hashMismatch)
        }
        try protection.compareServerFrozenAuthorVersion(serverFrozenHash: hash, expectedHash: hash,
                                                        originalRequestID: "req-a1")
        XCTAssertEqual(protection.phase, .matched)
        XCTAssertEqual(protection.matchedHash, hash)
        XCTAssertEqual(protection.originalRequestID, "req-a1")
        try protection.compareServerFrozenAuthorVersion(serverFrozenHash: hash, expectedHash: hash,
                                                        originalRequestID: "req-a1")
        XCTAssertEqual(protection.originalRequestID, "req-a1")
        XCTAssertThrowsError(try protection.compareServerFrozenAuthorVersion(
            serverFrozenHash: hash, expectedHash: hash, originalRequestID: "req-a-other")) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .requestMismatch)
        }
        XCTAssertEqual(protection.originalRequestID, "req-a1")
        XCTAssertEqual(waiting { try protection.consumeH5SDKOriginal() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.h5SdkOriginal))
    }
    func testHashMismatchOfNeverSeenIdDoesNotOccupyThenUniqueCompareApplies() throws {
        var protection = H5AnswerProtection()
        XCTAssertNil(protection.originalRequestID)
        XCTAssertEqual(protection.phase, .idle)
        XCTAssertThrowsError(try protection.compareServerFrozenAuthorVersion(
            serverFrozenHash: hash, expectedHash: other, originalRequestID: "req-a-never-c10")) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .hashMismatch)
        }
        XCTAssertNil(protection.originalRequestID)
        XCTAssertEqual(protection.phase, .idle)
        try protection.compareServerFrozenAuthorVersion(serverFrozenHash: hash, expectedHash: hash,
                                                        originalRequestID: "req-a-never-c10")
        XCTAssertEqual(protection.originalRequestID, "req-a-never-c10")
        XCTAssertEqual(protection.phase, .matched)
        try protection.compareServerFrozenAuthorVersion(serverFrozenHash: hash, expectedHash: hash,
                                                        originalRequestID: "req-a-never-c10")
        XCTAssertEqual(protection.originalRequestID, "req-a-never-c10")
        XCTAssertThrowsError(try protection.compareServerFrozenAuthorVersion(
            serverFrozenHash: hash, expectedHash: hash, originalRequestID: "req-a-other")) { error in
            XCTAssertEqual(error as? H5AnswerProtectionFailure, .requestMismatch)
        }
        XCTAssertEqual(protection.originalRequestID, "req-a-never-c10")
    }
    private func waiting(_ body: () throws -> Never) -> H5AnswerProtectionFailure? {
        do { try body(); return nil } catch let error as H5AnswerProtectionFailure { return error } catch { return nil }
    }
}
