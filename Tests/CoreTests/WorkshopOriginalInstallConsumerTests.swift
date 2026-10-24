import XCTest
@testable import QuestifyCore

final class WorkshopOriginalInstallConsumerTests: XCTestCase {
    func testSameRequestReadsOriginalReceiptAndUnknownDoesNotInstall() throws {
        var gate = WorkshopModuleImportGate()
        var consumer = WorkshopOriginalInstallConsumer()
        try consumer.open(entry: "workshop-entry", requestID: "req-c10-install", gate: &gate)
        try consumer.open(entry: "workshop-entry", requestID: "req-c10-install", gate: &gate)
        XCTAssertThrowsError(try consumer.open(entry: "workshop-entry", requestID: "req-c10-other", gate: &gate))
        XCTAssertEqual(consumer.originalRequestID, "req-c10-install")
        let source = InstallRead(fact: nil)
        XCTAssertNil(consumer.read(source))
        source.fact = WorkshopOriginalInstallFact(requestID: "req-c10-install", state: "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(consumer.read(source)?.state, "INSTALLED_PRIVATE_DRAFT")
        XCTAssertEqual(source.reads, ["req-c10-install", "req-c10-install"])
    }

    func testRestartRevokeAndLateFactKeepTheOriginalRequest() throws {
        var gate = WorkshopModuleImportGate()
        var consumer = WorkshopOriginalInstallConsumer()
        try consumer.open(entry: "workshop-entry", requestID: "req-c10-install", gate: &gate)
        let saved = try XCTUnwrap(consumer.record())
        let restarted = try XCTUnwrap(WorkshopOriginalInstallConsumer.restored(saved))
        XCTAssertEqual(restarted.originalRequestID, "req-c10-install")
        let source = InstallRead(fact: nil)
        XCTAssertNil(restarted.read(source))
        var live = restarted
        live.revoke()
        source.fact = WorkshopOriginalInstallFact(requestID: "req-c10-install", state: "INSTALLED_PRIVATE_DRAFT")
        XCTAssertNil(live.read(source))
        XCTAssertFalse(live.acceptLate(try XCTUnwrap(source.fact)))
        XCTAssertEqual(live.originalRequestID, "req-c10-install")
        XCTAssertThrowsError(try live.rejectSelfReport()) { error in
            XCTAssertEqual(error as? WorkshopRunVerifyFailure, .jsSelfReportRejected)
        }
    }
}

private final class InstallRead: WorkshopOriginalInstallReading {
    var fact: WorkshopOriginalInstallFact?
    var reads: [String] = []
    init(fact: WorkshopOriginalInstallFact?) { self.fact = fact }
    func read(requestID: String) -> WorkshopOriginalInstallFact? {
        reads.append(requestID)
        guard fact?.requestID == requestID else { return nil }
        return fact
    }
}
