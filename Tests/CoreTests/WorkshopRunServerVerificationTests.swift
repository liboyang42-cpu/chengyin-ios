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
    private func waiting(_ body: () throws -> Never) -> WorkshopRunVerifyFailure? {
        do { try body(); return nil } catch let error as WorkshopRunVerifyFailure { return error } catch { return nil }
    }
}
