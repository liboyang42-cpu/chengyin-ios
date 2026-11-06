import XCTest
@testable import QuestifyCore

final class ExplorationPrivateToolsAndCapsuleAuditTests: XCTestCase {
    func testCanonicalFiveToolsPassPrivateToolsReadinessAudit() {
        let entries = ExplorationPrivateToolsAndCapsuleAudit.canonicalEntries
        XCTAssertEqual(entries.count, 5)
        XCTAssertTrue(entries.allSatisfy(\.isCompliant))
        XCTAssertEqual(
            entries.map(\.toolKind),
            [
                .timeCapsule,
                .explorationGoals,
                .explorationExport,
                .explorationAnniversary,
                .monthlyRecap
            ]
        )

        let result = ExplorationPrivateToolsAndCapsuleAudit.evaluate()
        XCTAssertEqual(result.totalTools, 5)
        XCTAssertEqual(result.compliantTools, 5)
        XCTAssertTrue(result.coversAllFiveTools)
        XCTAssertTrue(result.isPrivateToolsReady)
    }

    func testMissingToolKindFailsFiveToolCoverageAndReadiness() {
        let incomplete = Array(ExplorationPrivateToolsAndCapsuleAudit.canonicalEntries.dropLast())
        let result = ExplorationPrivateToolsAndCapsuleAudit.evaluate(entries: incomplete)

        XCTAssertEqual(result.totalTools, 4)
        XCTAssertEqual(result.compliantTools, 4)
        XCTAssertFalse(result.coversAllFiveTools)
        XCTAssertFalse(result.isPrivateToolsReady)
    }

    func testPublicVisibilityLeakRejectsPrivateToolCompliance() {
        var entries = ExplorationPrivateToolsAndCapsuleAudit.canonicalEntries
        entries[0] = ExplorationPrivateToolAuditEntry(
            id: "timeCapsule",
            toolKind: .timeCapsule,
            isOwnerOnlyPrivate: false,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        )

        XCTAssertFalse(entries[0].isCompliant)
        let result = ExplorationPrivateToolsAndCapsuleAudit.evaluate(entries: entries)
        XCTAssertEqual(result.totalTools, 5)
        XCTAssertEqual(result.compliantTools, 4)
        XCTAssertTrue(result.coversAllFiveTools)
        XCTAssertFalse(result.isPrivateToolsReady)
    }

    func testWrongStringsTableOrMissingOfflineSupportRejectsCompliance() {
        var entries = ExplorationPrivateToolsAndCapsuleAudit.canonicalEntries
        entries[2] = ExplorationPrivateToolAuditEntry(
            id: "explorationExport",
            toolKind: .explorationExport,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: false,
            supportsOfflineDraftOrExport: true
        )
        entries[4] = ExplorationPrivateToolAuditEntry(
            id: "monthlyRecap",
            toolKind: .monthlyRecap,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: false
        )

        XCTAssertFalse(entries[2].isCompliant)
        XCTAssertFalse(entries[4].isCompliant)
        let result = ExplorationPrivateToolsAndCapsuleAudit.evaluate(entries: entries)
        XCTAssertEqual(result.totalTools, 5)
        XCTAssertEqual(result.compliantTools, 3)
        XCTAssertTrue(result.coversAllFiveTools)
        XCTAssertFalse(result.isPrivateToolsReady)
    }
}
