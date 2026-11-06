import XCTest
@testable import QuestifyCore

final class SQLiteAndJSONJournalCorruptionRecoveryAuditTests: XCTestCase {
    func testCanonicalStoresPassCorruptionRecoveryReadiness() {
        let result = SQLiteAndJSONJournalCorruptionRecoveryAudit.evaluate()
        XCTAssertEqual(SQLiteAndJSONJournalCorruptionRecoveryAudit.canonicalStores.count, 4)
        XCTAssertEqual(result.totalStores, 4)
        XCTAssertEqual(result.compliantStores, 4)
        XCTAssertTrue(result.isCorruptionRecoveryReady)
    }

    func testNonAtomicWriteRenameRejectsCorruptionRecoveryReadiness() {
        var stores = SQLiteAndJSONJournalCorruptionRecoveryAudit.canonicalStores
        stores[0] = DurableStoreCorruptionPolicyCheck(
            id: "play-game-command-journal",
            storeName: "PlayGameCommandJournal",
            usesAtomicWriteRename: false,
            quarantinesCorruptPayloadWithoutCrash: true,
            validatesSchemaVersionBeforeDecode: true
        )

        let result = SQLiteAndJSONJournalCorruptionRecoveryAudit.evaluate(stores: stores)
        XCTAssertFalse(stores[0].isCompliant)
        XCTAssertEqual(result.totalStores, 4)
        XCTAssertEqual(result.compliantStores, 3)
        XCTAssertFalse(result.isCorruptionRecoveryReady)
    }

    func testUnquarantinedCorruptPayloadCrashRiskRejectsCompliance() {
        var stores = SQLiteAndJSONJournalCorruptionRecoveryAudit.canonicalStores
        stores[1] = DurableStoreCorruptionPolicyCheck(
            id: "roam-exploration-draft-store",
            storeName: "RoamExplorationDraftStore",
            usesAtomicWriteRename: true,
            quarantinesCorruptPayloadWithoutCrash: false,
            validatesSchemaVersionBeforeDecode: true
        )

        let result = SQLiteAndJSONJournalCorruptionRecoveryAudit.evaluate(stores: stores)
        XCTAssertFalse(stores[1].isCompliant)
        XCTAssertEqual(result.totalStores, 4)
        XCTAssertEqual(result.compliantStores, 3)
        XCTAssertFalse(result.isCorruptionRecoveryReady)
    }

    func testMissingSchemaVersionValidationBeforeDecodeRejectsCompliance() {
        var stores = SQLiteAndJSONJournalCorruptionRecoveryAudit.canonicalStores
        stores[2] = DurableStoreCorruptionPolicyCheck(
            id: "publish-draft-outbox-store",
            storeName: "PublishDraftOutboxStore",
            usesAtomicWriteRename: true,
            quarantinesCorruptPayloadWithoutCrash: true,
            validatesSchemaVersionBeforeDecode: false
        )

        let result = SQLiteAndJSONJournalCorruptionRecoveryAudit.evaluate(stores: stores)
        XCTAssertFalse(stores[2].isCompliant)
        XCTAssertEqual(result.totalStores, 4)
        XCTAssertEqual(result.compliantStores, 3)
        XCTAssertFalse(result.isCorruptionRecoveryReady)
    }
}
