import XCTest
@testable import QuestifyCore

/// Pure metadata state machines only; no archive, network, payment, install or runtime execution.
final class WorkshopModuleOriginalManifestBindingTests: XCTestCase {
    private let request = "import-req-0001"
    private let hash = String(repeating: "ab", count: 32)
    private var metadata: [String: String] {
        ["id": "mod-1", "version": "1.0.0", "contentHash": hash, "schemaVersion": "1"]
    }
    private var qmod: [String: String] {
        ["formatVersion": "1.0", "kind": "questify.mod", "packageId": "mod-1",
         "packageVersion": "1.0.0", "entrypoint": "content.json", "contentHash": hash,
         "schemaVersion": "1", "filePath": "content.json", "fileSha256": hash, "fileBytes": "12"]
    }
    func testExactReplayAndExistingSchemaNormalizationPreserveOriginalState() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
        let original = entry
        try entry.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
        XCTAssertEqual(entry, original)
        var normalized = metadata; normalized["schemaVersion"] = "01"
        try entry.importMetadata(normalized, entry: "mod-1", originalRequestID: request)
        XCTAssertEqual(entry, original, "Original decoder already accepts integer schema normalization")
    }
    func testSameRequestCannotReplaceAnyCatalogIdentityField() throws {
        for (key, value) in [("id", "mod-2"), ("version", "2.0.0"),
                             ("contentHash", String(repeating: "cd", count: 32))] {
            var entry = WorkshopModuleImportEntry()
            try entry.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
            let original = entry
            var changed = metadata; changed[key] = value
            XCTAssertThrowsError(try entry.importMetadata(changed, entry: "mod-1", originalRequestID: request)) {
                XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
            }
            XCTAssertEqual(entry, original)
        }
    }
    func testMalformedReplayIsNotSilentlyAcceptedAndKeepsOriginalPreview() throws {
        for key in ["id", "version", "contentHash", "schemaVersion"] {
            var entry = WorkshopModuleImportEntry()
            try entry.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
            let original = entry
            var malformed = metadata; malformed[key] = nil
            XCTAssertThrowsError(try entry.importMetadata(malformed, entry: "mod-1", originalRequestID: request)) {
                XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
            }
            XCTAssertEqual(entry, original)
        }
    }
    func testUnsupportedSchemaAndHiddenAnswersStillFailBeforeAnyReplacement() throws {
        var entry = WorkshopModuleImportEntry()
        try entry.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
        let original = entry
        var wrongSchema = metadata; wrongSchema["schemaVersion"] = "2"
        XCTAssertThrowsError(try entry.importMetadata(wrongSchema, entry: "mod-1", originalRequestID: request)) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
        }
        var hidden = metadata; hidden["answer"] = "forbidden"
        XCTAssertThrowsError(try entry.importMetadata(hidden, entry: "mod-1", originalRequestID: request)) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertEqual(entry, original)
    }
    func testNormalDeclaredPageCannotAcknowledgeChangedOriginalHash() throws {
        var page = H5DeclaredSessionPage()
        try page.importMetadata(metadata, entry: "mod-1", originalRequestID: request)
        let original = page
        var changed = metadata; changed["contentHash"] = String(repeating: "cd", count: 32)
        XCTAssertThrowsError(try page.importMetadata(changed, entry: "mod-1", originalRequestID: request)) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
        }
        XCTAssertEqual(page, original)
    }
    func testQmodDeclarationCannotSwapVersionUnderOriginalImportRequest() throws {
        var release = WorkshopModReleaseEntry()
        try release.submitManifest(qmod, entry: "mod-1", originalRequestID: request)
        let original = release
        var changed = qmod; changed["packageVersion"] = "2.0.0"
        XCTAssertThrowsError(try release.submitManifest(changed, entry: "mod-1", originalRequestID: request)) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
        }
        XCTAssertEqual(release, original)
        XCTAssertFalse(release.released)
        XCTAssertEqual(release.imports.gate.preview?.metadataOnly, true)
    }
}
