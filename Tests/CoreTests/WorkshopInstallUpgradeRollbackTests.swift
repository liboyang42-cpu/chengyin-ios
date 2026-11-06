import XCTest
@testable import QuestifyCore

final class WorkshopInstallUpgradeRollbackTests: XCTestCase {
    func testInstallUpgradeRollbackRetainsPriorVersion() throws {
        var machine = WorkshopInstallUpgradeRollback()
        try machine.authorizedHold(originalRequestID: "req-i1", versionLabel: "1.0.0")
        try machine.install(originalRequestID: "req-i1")
        XCTAssertEqual(machine.phase, .installed)
        XCTAssertEqual(machine.snapshot?.installedVersion, "1.0.0")
        try machine.beginUpgrade(to: "1.1.0")
        XCTAssertEqual(machine.phase, .upgrading)
        XCTAssertEqual(machine.snapshot?.retainedPriorVersion, "1.0.0")
        try machine.finishUpgrade()
        XCTAssertEqual(machine.installedVersion, "1.1.0")
        try machine.rollback()
        XCTAssertEqual(machine.phase, .rolledBack)
        XCTAssertEqual(machine.installedVersion, "1.0.0")
    }
    func testSameOriginalRequestIDCannotDoubleInstallAndRollbackNeedsPrior() throws {
        var machine = WorkshopInstallUpgradeRollback()
        try machine.authorizedHold(originalRequestID: "req-i1", versionLabel: "1.0.0")
        try machine.install(originalRequestID: "req-i1")
        try machine.install(originalRequestID: "req-i1")
        XCTAssertEqual(machine.installCount, 1)
        XCTAssertThrowsError(try machine.rollback()) { error in
            XCTAssertEqual(error as? WorkshopInstallFailure, .noRetainedPrior)
        }
        XCTAssertEqual(machine.phase, .installed)
        XCTAssertEqual(waiting { try machine.purchaseViaIAP() }, .digitalGoodsOpenDecision)
        machine = WorkshopInstallUpgradeRollback()
        XCTAssertEqual(waiting { try machine.consumeQmodRuntime() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
    }
    func testOtherRequestIdCannotRewriteAuthorizedHold() throws {
        var machine = WorkshopInstallUpgradeRollback()
        try machine.authorizedHold(originalRequestID: "req-i1", versionLabel: "1.0.0")
        try machine.install(originalRequestID: "req-i1")
        XCTAssertEqual(machine.originalRequestID, "req-i1")
        XCTAssertThrowsError(try machine.authorizedHold(originalRequestID: "req-i-other",
                                                       versionLabel: "9.9.9")) { error in
            XCTAssertEqual(error as? WorkshopInstallFailure, .invalidGrant)
        }
        XCTAssertEqual(machine.originalRequestID, "req-i1")
        XCTAssertEqual(machine.installCount, 1)
        XCTAssertEqual(machine.snapshot?.installedVersion, "1.0.0")
    }
    func testNotHeldInstallOfNeverSeenIdDoesNotOccupyThenUniqueHoldApplies() throws {
        var machine = WorkshopInstallUpgradeRollback()
        XCTAssertNil(machine.originalRequestID)
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.installCount, 0)
        XCTAssertThrowsError(try machine.install(originalRequestID: "c10-ins-never-c10")) { error in
            XCTAssertEqual(error as? WorkshopInstallFailure, .notHeld)
        }
        XCTAssertNil(machine.originalRequestID)
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.installCount, 0)
        try machine.authorizedHold(originalRequestID: "c10-ins-never-c10", versionLabel: "1.0.0")
        XCTAssertEqual(machine.originalRequestID, "c10-ins-never-c10")
        XCTAssertEqual(machine.phase, .held)
        try machine.install(originalRequestID: "c10-ins-never-c10")
        XCTAssertEqual(machine.phase, .installed)
        XCTAssertEqual(machine.installCount, 1)
        try machine.install(originalRequestID: "c10-ins-never-c10")
        XCTAssertEqual(machine.installCount, 1)
        XCTAssertEqual(machine.originalRequestID, "c10-ins-never-c10")
    }
    private func waiting(_ body: () throws -> Never) -> WorkshopInstallFailure? {
        do { try body(); return nil } catch let error as WorkshopInstallFailure { return error } catch { return nil }
    }
}
