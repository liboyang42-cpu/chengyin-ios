import XCTest
@testable import QuestifyCore

final class WorkshopInstallJourneyEntryTests: XCTestCase {
    func testSameRequestInstallsOnceAndRollbackUsesTheRetainedVersion() throws {
        var entry = WorkshopInstallJourneyEntry()
        try entry.hold(originalRequestID: "install-req-0001", versionLabel: "1.0.0")
        try entry.install(originalRequestID: "install-req-0001")
        try entry.install(originalRequestID: "install-req-0001")
        XCTAssertEqual(entry.machine.installCount, 1)
        XCTAssertEqual(entry.machine.installedVersion, "1.0.0")
        try entry.upgrade(to: "1.1.0")
        XCTAssertEqual(entry.machine.installedVersion, "1.1.0")
        XCTAssertEqual(entry.machine.retainedPriorVersion, "1.0.0")
        try entry.rollback()
        XCTAssertEqual(entry.machine.phase, .rolledBack)
        XCTAssertEqual(entry.machine.installedVersion, "1.0.0")
        XCTAssertEqual(entry.purchase(), .digitalGoodsOpenDecision)
        XCTAssertEqual(entry.consumeRuntime(), .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
    }
}
