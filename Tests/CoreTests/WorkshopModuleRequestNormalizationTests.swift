import XCTest
@testable import QuestifyCore

final class WorkshopModuleRequestNormalizationTests: XCTestCase {
    private var metadata: [String: String] {
        ["id": "mod-1", "version": "1.0.0", "contentHash": String(repeating: "ab", count: 32), "schemaVersion": "1"]
    }
    func testOriginalWhitespaceNormalizationIsAlsoUsedForExactReplay() throws {
        for initial in ["req-1", "  req-1\n"] {
            var entry = WorkshopModuleImportEntry()
            try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: initial)
            let original = entry
            XCTAssertEqual(entry.gate.originalRequestID, "req-1")
            for replay in ["req-1", "  req-1\n", "\treq-1\r"] {
                try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: replay)
                XCTAssertEqual(entry, original)
            }
        }
    }
    func testWhitespaceDoesNotBypassChangedManifestBinding() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: "req-1")
        let original = entry
        var changed = metadata; changed["version"] = "2.0.0"
        XCTAssertThrowsError(try entry.importMetadata(changed, entry: "workshop.owned.library", originalRequestID: " req-1 ")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
        }
        XCTAssertEqual(entry, original)
    }
    func testDistinctRequestOrEntryStillCannotReplaceOriginal() throws {
        for (name, request) in [("workshop.owned.library", " req-2 "), ("other.entry", " req-1 ")] {
            var entry = WorkshopModuleImportEntry()
            try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: "req-1")
            let manifest = entry.gate.manifest, preview = entry.gate.preview
            XCTAssertThrowsError(try entry.importMetadata(metadata, entry: name, originalRequestID: request)) {
                XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
            }
            XCTAssertEqual(entry.gate.originalRequestID, "req-1")
            XCTAssertEqual(entry.gate.manifest, manifest)
            XCTAssertEqual(entry.gate.preview, preview)
        }
    }
    func testBlankRequestCannotBeNormalizedIntoExistingIdentity() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: "req-1")
        XCTAssertThrowsError(try entry.importMetadata(metadata, entry: "workshop.owned.library", originalRequestID: " \n\t")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
        }
        XCTAssertEqual(entry.gate.originalRequestID, "req-1")
    }
    func testQmodMetadataReplayUsesSameOriginalNormalizationWithoutOpeningArchive() throws {
        var entry = WorkshopModuleImportEntry()
        let hash = String(repeating: "ab", count: 32)
        let qmod = ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
                    "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": hash,
                    "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
        try entry.importQmodManifest(qmod, entry: "mod-1", originalRequestID: " req-1 ")
        let original = entry
        try entry.importQmodManifest(qmod, entry: "mod-1", originalRequestID: "\treq-1\n")
        XCTAssertEqual(entry, original)
        XCTAssertEqual(entry.gate.preview?.metadataOnly, true)
        XCTAssertFalse(WorkshopModuleSourceInventory.qmodCandidateBinariesPresent)
    }
}
