import XCTest
@testable import QuestifyCore

final class WorkshopModuleImportEntryTests: XCTestCase {
    func testMetadataImportReachesReviewAndQmodStaysClosed() throws {
        var entry = WorkshopModuleImportEntry()
        let hash = String(repeating: "ab", count: 32)
        let object = ["id": "mod-1", "version": "1.0.0", "contentHash": hash, "schemaVersion": "1"]
        try entry.importMetadata(object, entry: "mod-1", originalRequestID: "import-req-0001")
        XCTAssertEqual(entry.gate.phase, .reviewPending)
        XCTAssertEqual(entry.gate.originalRequestID, "import-req-0001")
        XCTAssertEqual(entry.gate.preview?.metadataOnly, true)
        try entry.importMetadata(object, entry: "mod-1", originalRequestID: "import-req-0001")
        XCTAssertEqual(entry.gate.originalRequestID, "import-req-0001")
        XCTAssertThrowsError(try entry.importMetadata(object.merging(["answer": "secret"]) { _, new in new },
                                                      entry: "mod-2", originalRequestID: "import-req-0002")) { error in
            XCTAssertEqual(error as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertEqual(entry.importQmod(entry: "mod-q", originalRequestID: "import-req-0003"),
                       .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
    }
}
