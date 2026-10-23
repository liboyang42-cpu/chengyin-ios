import XCTest
@testable import QuestifyCore

final class WorkshopModuleImportGateTests: XCTestCase {
    private let hashA = String(repeating: "ab", count: 32)
    private let terms = String(repeating: "ef", count: 32)
    private func object(id: String = "mod-city-1", version: String = "1.0.0",
                        extra: [String: String] = [:]) -> [String: String] {
        var value = ["id": id, "version": version, "contentHash": hashA, "schemaVersion": "1"]
        extra.forEach { value[$0.key] = $0.value }
        return value
    }
    func testFirstJourneyImportPublishInstallRunRecoverOriginal() throws {
        var importer = WorkshopModuleImportGate()
        try importer.importFromNormalEntry(entry: "workshop.owned.library",
                                           format: .metadataManifestV1,
                                           originalRequestID: "req-c10-1")
        XCTAssertEqual(importer.phase, .imported)
        try importer.validate(object())
        XCTAssertEqual(importer.phase, .validated)
        XCTAssertEqual(importer.manifest?.schemaVersion, 1)
        XCTAssertEqual(importer.manifest?.contentHash, hashA)
        try importer.previewMetadataOnly()
        XCTAssertEqual(importer.phase, .previewed)
        XCTAssertEqual(importer.preview?.metadataOnly, true)
        try importer.markReviewPending()
        XCTAssertEqual(importer.phase, .reviewPending)

        var publish = WorkshopPackageVersionPublish()
        try publish.freeze(contentHash: hashA, termsHash: terms, versionLabel: "1.0.0",
                           originalRequestID: "req-c10-1", reviewed: true)
        XCTAssertEqual(publish.phase, .frozen)
        XCTAssertEqual(publish.publishCount, 1)
        try publish.freeze(contentHash: hashA, termsHash: terms, versionLabel: "1.0.0",
                           originalRequestID: "req-c10-1", reviewed: true)
        try publish.republish(originalRequestID: "req-c10-1")
        XCTAssertEqual(publish.publishCount, 1)
        XCTAssertEqual(publish.frozen?.contentHash, hashA)
        XCTAssertEqual(publish.frozen?.termsHash, terms)

        var install = WorkshopInstallUpgradeRollback()
        try install.authorizedHold(originalRequestID: "req-c10-1", versionLabel: "1.0.0")
        XCTAssertEqual(install.phase, .held)
        try install.install(originalRequestID: "req-c10-1")
        XCTAssertEqual(install.phase, .installed)
        XCTAssertEqual(install.installCount, 1)
        try install.install(originalRequestID: "req-c10-1")
        XCTAssertEqual(install.installCount, 1)
        XCTAssertEqual(install.snapshot?.installedVersion, "1.0.0")

        var run = WorkshopRunServerVerification()
        try run.bind(originalRequestID: "req-c10-1", intent: .run)
        let pass = try XCTUnwrap(WorkshopServerReceipt(originalRequestID: "req-c10-1",
                                                       kind: .serverPass, projectionSucceeded: true))
        try run.applyServerReceipt(pass)
        XCTAssertEqual(run.phase, .passed)
        XCTAssertEqual(run.originalRequestID, "req-c10-1")
        XCTAssertTrue(run.currentProjectionIsSuccess)

        var unknown = WorkshopRunServerVerification()
        try unknown.bind(originalRequestID: "req-c10-1", intent: .run)
        let receipt = try XCTUnwrap(WorkshopServerReceipt(originalRequestID: "req-c10-1",
                                                          kind: .unknown, projectionSucceeded: true))
        try unknown.applyServerReceipt(receipt)
        XCTAssertEqual(unknown.phase, .unknown)
        XCTAssertEqual(unknown.originalIntent, .run)
        XCTAssertEqual(unknown.originalRequestID, "req-c10-1")
        XCTAssertFalse(unknown.currentProjectionIsSuccess)
        let recovered = try unknown.recoverOriginal(originalRequestID: "req-c10-1")
        XCTAssertEqual(recovered.originalRequestID, "req-c10-1")
        XCTAssertEqual(recovered.intent, .run)
        XCTAssertFalse(recovered.succeeded)
        XCTAssertEqual(recovered.phase, .unknown)
    }
    func testMissingQmodOriginalIsWaitingSourceNotSuccess() {
        var gate = WorkshopModuleImportGate()
        XCTAssertFalse(WorkshopModuleSourceInventory.qmodOriginalPresent)
        XCTAssertFalse(WorkshopModuleSourceInventory.qmodCandidateBinariesPresent)
        XCTAssertFalse(WorkshopModuleSourceInventory.unpushedIOSPresent)
        XCTAssertFalse(WorkshopModuleSourceInventory.implPack232Present)
        XCTAssertFalse(WorkshopModuleSourceInventory.v12DocxPresent)
        XCTAssertEqual(waiting { try gate.consumeQmodOriginal() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertEqual(gate.phase, .waitingSource)
        gate = WorkshopModuleImportGate()
        XCTAssertEqual(importWaiting {
            try gate.importFromNormalEntry(entry: "workshop.owned.library", format: .unknownQmod,
                                           originalRequestID: "req-c10-qmod")
        }, .waitingSource(capability: WorkshopModuleSourceInventory.qmodOriginal))
        XCTAssertNotEqual(gate.phase, .imported)
        gate = WorkshopModuleImportGate()
        XCTAssertEqual(waiting { try gate.consumeCandidateBinaries() },
                       .waitingSource(capability: WorkshopModuleSourceInventory.qmodCandidateBinaries))
        gate = WorkshopModuleImportGate()
        XCTAssertEqual(waiting { try gate.executeJavaScript("clear()") }, .jsExecutionForbidden)
        gate = WorkshopModuleImportGate()
        XCTAssertEqual(waiting { try gate.writeRuntime() }, .runtimeWriteForbidden)
    }
    func testValidateRejectsAnswersHiddenCoordinatesAndBadSchema() throws {
        var gate = WorkshopModuleImportGate()
        try gate.importFromNormalEntry(entry: "workshop.owned.library", format: .metadataManifestV1,
                                       originalRequestID: "req-c10-2")
        XCTAssertThrowsError(try gate.validate(object(extra: ["answer": "42"]))) { error in
            XCTAssertEqual(error as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertThrowsError(try gate.validate(object(extra: ["hiddenCoordinate": "31.2,121.5"]))) { error in
            XCTAssertEqual(error as? WorkshopModuleImportFailure, .answersOrHiddenCoordinatesForbidden)
        }
        XCTAssertThrowsError(try WorkshopModuleImportGate.decodeManifest(
            object(extra: ["schemaVersion": "2"]))) { error in
            XCTAssertEqual(error as? WorkshopModuleImportFailure, .invalidManifest)
        }
        XCTAssertNil(WorkshopModuleManifest(id: "mod-city-1", version: "1.0.0",
                                            contentHash: "not-a-hash", schemaVersion: 1))
        let allowed = try WorkshopModuleImportGate.decodeManifest(object())
        XCTAssertEqual(allowed.id, "mod-city-1")
        XCTAssertEqual(allowed.contentHash.count, 64)
    }
    private func waiting(_ body: () throws -> Never) -> WorkshopModuleImportFailure? {
        do { try body(); return nil } catch let error as WorkshopModuleImportFailure { return error } catch { return nil }
    }
    private func importWaiting(_ body: () throws -> Void) -> WorkshopModuleImportFailure? {
        do { try body(); return nil } catch let error as WorkshopModuleImportFailure { return error } catch { return nil }
    }
}
