import XCTest
@testable import QuestifyCore

final class WorkshopModReleaseEntryTests: XCTestCase {
    func testDeclarationDoesNotReleaseAndAReviewedPackageInstallsOnce() throws {
        var entry = WorkshopModReleaseEntry()
        let hash = String(repeating: "ab", count: 32)
        let terms = String(repeating: "cd", count: 32)
        try entry.submitManifest(manifest(hash), entry: "mod-1", originalRequestID: "import-req-0001")
        XCTAssertEqual(entry.imports.gate.phase, .reviewPending)
        XCTAssertFalse(entry.released)
        XCTAssertFalse(entry.ownsCopyright)
        XCTAssertFalse(entry.publishRight)
        XCTAssertThrowsError(try entry.install()) { XCTAssertEqual($0 as? WorkshopInstallFailure, .invalidGrant) }
        XCTAssertThrowsError(try entry.release(termsHash: terms, reviewed: false)) {
            XCTAssertEqual($0 as? WorkshopPackagePublishFailure, .notReviewed)
        }
        try entry.release(termsHash: terms, reviewed: true)
        XCTAssertTrue(entry.released)
        XCTAssertFalse(entry.ownsCopyright)
        try entry.install()
        try entry.installAgain()
        XCTAssertEqual(entry.journey.machine.installCount, 1)
        XCTAssertEqual(entry.freezeEntry.registerPublic(), .publicRegistryReserved)
    }

    private func manifest(_ hash: String) -> [String: String] {
        ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
         "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": hash,
         "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
    }
}
