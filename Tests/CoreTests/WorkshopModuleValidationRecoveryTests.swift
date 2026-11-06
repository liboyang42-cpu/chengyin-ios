import XCTest
@testable import QuestifyCore

final class WorkshopModuleValidationRecoveryTests: XCTestCase {
    private var valid: [String: String] {
        ["id": "mod-1", "version": "1.0.0", "contentHash": String(repeating: "ab", count: 32), "schemaVersion": "1"]
    }
    private func failedImport() throws -> WorkshopModuleImportEntry {
        var entry = WorkshopModuleImportEntry()
        var bad = valid; bad["schemaVersion"] = "2"
        XCTAssertThrowsError(try entry.importMetadata(bad, entry: "workshop.owned.library", originalRequestID: " req-1 ")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
        }
        XCTAssertEqual(entry.gate.phase, .imported)
        XCTAssertEqual(entry.gate.originalRequestID, "req-1")
        XCTAssertNil(entry.gate.manifest)
        XCTAssertNil(entry.gate.preview)
        return entry
    }
    func testOriginalFailedValidationCanResumeWithoutReplacingRequest() throws {
        var entry = try failedImport()
        try entry.importMetadata(valid, entry: "workshop.owned.library", originalRequestID: "\treq-1\n")
        XCTAssertEqual(entry.gate.phase, .reviewPending)
        XCTAssertEqual(entry.gate.originalRequestID, "req-1")
        XCTAssertEqual(entry.gate.manifest, try WorkshopModuleImportGate.decodeManifest(valid))
        XCTAssertEqual(entry.gate.preview?.metadataOnly, true)
        XCTAssertNil(entry.gate.failure)
    }
    func testRepeatedInvalidBodyNeverCreatesPreviewOrChangesRequest() throws {
        var entry = try failedImport()
        var bad = valid; bad["contentHash"] = "invalid"
        XCTAssertThrowsError(try entry.importMetadata(bad, entry: "workshop.owned.library", originalRequestID: "req-1")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .invalidManifest)
        }
        XCTAssertEqual(entry.gate.phase, .imported)
        XCTAssertEqual(entry.gate.originalRequestID, "req-1")
        XCTAssertNil(entry.gate.manifest)
        XCTAssertNil(entry.gate.preview)
    }
    func testRecoveryStillRejectsOtherIdentityAndHiddenAnswers() throws {
        var entry = try failedImport()
        XCTAssertThrowsError(try entry.importMetadata(valid, entry: "workshop.owned.library", originalRequestID: "req-2")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
        }
        var hidden = valid; hidden["answer"] = "forbidden"
        XCTAssertThrowsError(try entry.importMetadata(hidden, entry: "workshop.owned.library", originalRequestID: "req-1")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertEqual(entry.gate.originalRequestID, "req-1")
        XCTAssertNil(entry.gate.preview)
    }
    func testFirstAcceptedManifestCannotBeReplacedAfterRecovery() throws {
        var entry = try failedImport()
        try entry.importMetadata(valid, entry: "workshop.owned.library", originalRequestID: "req-1")
        let original = entry
        var changed = valid; changed["version"] = "2.0.0"
        XCTAssertThrowsError(try entry.importMetadata(changed, entry: "workshop.owned.library", originalRequestID: "req-1")) {
            XCTAssertEqual($0 as? WorkshopModuleImportFailure, .requestMismatch)
        }
        XCTAssertEqual(entry, original)
    }
    func testDeclaredPageRecoversSameOriginalValidationWithoutOpeningRuntime() throws {
        var page = H5DeclaredSessionPage()
        var bad = valid; bad["schemaVersion"] = "2"
        XCTAssertThrowsError(try page.importMetadata(bad, entry: "mod-1", originalRequestID: "req-1"))
        try page.importMetadata(valid, entry: "mod-1", originalRequestID: " req-1 ")
        XCTAssertEqual(page.imports.gate.phase, .reviewPending)
        XCTAssertEqual(page.imports.gate.originalRequestID, "req-1")
        XCTAssertEqual(page.imports.gate.preview?.metadataOnly, true)
        XCTAssertFalse(WorkshopModuleSourceInventory.h5ContainerOriginalPresent)
    }
}
