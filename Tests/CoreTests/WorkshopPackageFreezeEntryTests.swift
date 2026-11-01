import XCTest
@testable import QuestifyCore

final class WorkshopPackageFreezeEntryTests: XCTestCase {
    func testReviewedFreezeRepublishesAndPublicRegistryStaysClosed() throws {
        var entry = WorkshopPackageFreezeEntry()
        let hash = String(repeating: "ab", count: 32)
        let terms = String(repeating: "cd", count: 32)
        try entry.freeze(contentHash: hash, termsHash: terms, versionLabel: "1.0.0",
                         originalRequestID: "pkg-freeze-0001", reviewed: true)
        XCTAssertEqual(entry.publish.phase, .frozen)
        XCTAssertEqual(entry.publish.publishCount, 1)
        try entry.freeze(contentHash: hash, termsHash: terms, versionLabel: "1.0.0",
                         originalRequestID: "pkg-freeze-0001", reviewed: true)
        XCTAssertEqual(entry.publish.publishCount, 1)
        XCTAssertEqual(entry.registerPublic(), .publicRegistryReserved)
        XCTAssertEqual(entry.consumePack(), .waitingSource(capability: WorkshopModuleSourceInventory.modulePackOriginal))
        XCTAssertThrowsError(try entry.freeze(contentHash: String(repeating: "ef", count: 32), termsHash: terms,
                                               versionLabel: "1.0.0", originalRequestID: "pkg-freeze-0001", reviewed: true)) { error in
            XCTAssertEqual(error as? WorkshopPackagePublishFailure, .frozenHashMutation)
        }
    }
}
