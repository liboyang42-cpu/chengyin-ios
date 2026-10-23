import XCTest
@testable import QuestifyCore

final class WorkshopRunServerVerificationTests: XCTestCase {
    func testJavaScriptSelfReportCannotClearRun() throws {
        var run = WorkshopRunServerVerification()
        try run.bind(originalRequestID: "req-r1", intent: .run)
        XCTAssertThrowsError(try run.applyJavaScriptClear(originalRequestID: "req-r1")) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertThrowsError(try run.applyH5SelfReport(originalRequestID: "req-r1")) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
        XCTAssertEqual(run.phase, .bound)
        XCTAssertFalse(run.currentProjectionIsSuccess)
        let pass = try XCTUnwrap(WorkshopServerReceipt(originalRequestID: "req-r1",
                                                       kind: .serverPass, projectionSucceeded: true))
        try run.applyServerReceipt(pass)
        XCTAssertEqual(run.phase, .passed)
    }
    func testUnknownReceiptKeepsOriginalIntentAndDoesNotMintRequestId() throws {
        var run = WorkshopRunServerVerification()
        try run.bind(originalRequestID: "req-r1", intent: .run)
        let unknown = try XCTUnwrap(WorkshopServerReceipt(originalRequestID: "req-r1",
                                                          kind: .unknown, projectionSucceeded: true))
        try run.applyServerReceipt(unknown)
        XCTAssertEqual(run.phase, .unknown)
        XCTAssertEqual(run.originalRequestID, "req-r1")
        XCTAssertEqual(run.originalIntent, .run)
        XCTAssertFalse(run.currentProjectionIsSuccess)
        let recovered = try run.recoverOriginal(originalRequestID: "req-r1")
        XCTAssertEqual(recovered.originalRequestID, "req-r1")
        XCTAssertFalse(recovered.succeeded)
        XCTAssertEqual(waiting { try run.consumeUnpushedIOSCandidate() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.unpushedIOS))
    }
    func testOtherRequestIdDoesNotRewriteBoundOriginal() throws {
        var run = WorkshopRunServerVerification()
        try run.bind(originalRequestID: "req-r1", intent: .run)
        let unknown = try XCTUnwrap(WorkshopServerReceipt(originalRequestID: "req-r1",
                                                          kind: .unknown, projectionSucceeded: true))
        try run.applyServerReceipt(unknown)
        XCTAssertEqual(run.originalRequestID, "req-r1")
        try run.bind(originalRequestID: "req-r1", intent: .run)
        XCTAssertEqual(run.phase, .unknown)
        XCTAssertEqual(run.originalRequestID, "req-r1")
        XCTAssertThrowsError(try run.bind(originalRequestID: "req-r-other", intent: .run)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .requestMismatch)
        }
        XCTAssertEqual(run.originalRequestID, "req-r1")
        XCTAssertEqual(try run.recoverOriginal(originalRequestID: "req-r1").originalRequestID, "req-r1")
        XCTAssertFalse(run.currentProjectionIsSuccess)
    }
    func testMissingBindRequestIdStaysNilNeverEmptyString() {
        var run = WorkshopRunServerVerification()
        XCTAssertNil(run.originalRequestID)
        XCTAssertThrowsError(try run.bind(originalRequestID: nil, intent: .run)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .invalidReceipt)
        }
        XCTAssertNil(run.originalRequestID)
        XCTAssertThrowsError(try run.bind(originalRequestID: "", intent: .run)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .invalidReceipt)
        }
        XCTAssertNil(run.originalRequestID)
        XCTAssertNotEqual(run.originalRequestID, "")
    }
    func testRecoverOriginalOfNeverSeenIdDoesNotOccupyThenUniqueBindApplies() throws {
        var run = WorkshopRunServerVerification()
        XCTAssertNil(run.originalRequestID)
        XCTAssertEqual(run.phase, .idle)
        XCTAssertThrowsError(try run.recoverOriginal(originalRequestID: "c10-run-never")) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .notUnknown)
        }
        XCTAssertNil(run.originalRequestID)
        XCTAssertEqual(run.phase, .idle)
        XCTAssertNotEqual(run.originalRequestID, "c10-run-never")
        try run.bind(originalRequestID: "c10-run-never", intent: .run)
        XCTAssertEqual(run.originalRequestID, "c10-run-never")
        XCTAssertEqual(run.phase, .bound)
        XCTAssertEqual(run.originalIntent, .run)
        try run.bind(originalRequestID: "c10-run-never", intent: .run)
        XCTAssertEqual(run.originalRequestID, "c10-run-never")
        XCTAssertEqual(run.phase, .bound)
        XCTAssertThrowsError(try run.bind(originalRequestID: "c10-run-other", intent: .run)) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .requestMismatch)
        }
        XCTAssertEqual(run.originalRequestID, "c10-run-never")
    }
    private func waiting(_ body: () throws -> Never) -> WorkshopRunVerifyFailure? {
        do { try body(); return nil } catch let error as WorkshopRunVerifyFailure { return error } catch { return nil }
    }
}
