import XCTest
@testable import QuestifyCore

final class WorkshopModuleQmodVersionContractTests: XCTestCase {
    private func manifest(_ version: String) -> [String: String] {
        let hash = String(repeating: "ab", count: 32)
        return ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
                "packageVersion": version, "entrypoint": "content.json", "contentHash": hash,
                "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
    }
    func testQmodEntryAcceptsCanonicalVersionBoundaries() throws {
        for version in ["0.0.0", "1.2.3", "999999.999999.999999"] {
            XCTAssertTrue(QmodManifest.strictSemver(version))
            var entry = WorkshopModuleImportEntry()
            try entry.importQmodManifest(manifest(version), entry: "mod-1", originalRequestID: "req-1")
            XCTAssertEqual(entry.gate.phase, .reviewPending)
            XCTAssertEqual(entry.gate.manifest?.version, version)
            XCTAssertEqual(entry.gate.preview?.metadataOnly, true)
        }
    }
    func testQmodEntryRejectsExactlyTheExistingCanonicalVersionFailures() throws {
        for version in ["١.٢.٣", "１.２.３", "².².²", "1000000.0.0", "01.2.3",
                        "1.02.3", "1.2.03", "1.2", "1.2.3.4", "1.2.3-beta", "1.2.3+build", "1.2.3\n"] {
            XCTAssertFalse(QmodManifest.strictSemver(version))
            var entry = WorkshopModuleImportEntry()
            XCTAssertThrowsError(try entry.importQmodManifest(manifest(version), entry: "mod-1", originalRequestID: "req-1")) {
                XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
            }
            XCTAssertEqual(entry.gate.phase, .idle)
            XCTAssertNil(entry.gate.originalRequestID)
            XCTAssertNil(entry.gate.preview)
        }
    }
    func testInvalidVersionReplayDoesNotMutatePriorAcceptedDeclaration() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importQmodManifest(manifest("1.0.0"), entry: "mod-1", originalRequestID: "req-1")
        let original = entry
        XCTAssertThrowsError(try entry.importQmodManifest(manifest("１.０.０"), entry: "mod-1", originalRequestID: "req-1")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
        }
        XCTAssertEqual(entry, original)
    }
    func testOrdinaryMetadataKeepsItsOriginalNonSemverVersionContract() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importMetadata(["id": "mod-1", "version": "edition-a", "contentHash": String(repeating: "ab", count: 32), "schemaVersion": "1"],
                                 entry: "workshop.owned.library", originalRequestID: "req-1")
        XCTAssertEqual(entry.gate.preview?.version, "edition-a")
    }
}
