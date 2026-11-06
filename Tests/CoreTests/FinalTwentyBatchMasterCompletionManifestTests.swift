import XCTest
@testable import QuestifyCore

final class FinalTwentyBatchMasterCompletionManifestTests: XCTestCase {
    func testCanonicalBatchesCoverAllTwentyOneBatchesAndLanesOneToTwoThirtySix() {
        let batches = FinalTwentyBatchMasterCompletionManifest.canonicalBatches
        XCTAssertEqual(batches.count, 21)
        XCTAssertEqual(batches.map(\.batchNumber), Array(1...21))
        XCTAssertEqual(batches.first?.laneRangeText, "Lanes 1–8")
        XCTAssertEqual(batches.last?.laneRangeText, "Lanes 233–236")
        XCTAssertTrue(batches.allSatisfy(\.isIntegratedAndVerified))

        let result = FinalTwentyBatchMasterCompletionManifest.evaluate()
        XCTAssertEqual(result.totalBatches, 21)
        XCTAssertEqual(result.verifiedBatches, 21)
        XCTAssertTrue(result.coversAllTwentyOneBatches)
        XCTAssertTrue(result.isMasterManifestComplete)
    }

    func testMissingBatchIsDetectedAndFailsMasterManifestEvaluation() {
        let twentyBatches = Array(FinalTwentyBatchMasterCompletionManifest.canonicalBatches.dropLast())
        let result = FinalTwentyBatchMasterCompletionManifest.evaluate(batches: twentyBatches)
        XCTAssertEqual(result.totalBatches, 20)
        XCTAssertEqual(result.verifiedBatches, 20)
        XCTAssertFalse(result.coversAllTwentyOneBatches)
        XCTAssertFalse(result.isMasterManifestComplete)
    }

    func testUnverifiedBatchIsRejectedByMasterManifestEvaluation() {
        var modified = FinalTwentyBatchMasterCompletionManifest.canonicalBatches
        modified[20] = CompletedBatchLedgerEntry(
            id: "batch-21",
            batchNumber: 21,
            laneRangeText: "Lanes 233–236",
            focusSummary: "Final 21-batch master completion manifest",
            isIntegratedAndVerified: false
        )
        let result = FinalTwentyBatchMasterCompletionManifest.evaluate(batches: modified)
        XCTAssertEqual(result.totalBatches, 21)
        XCTAssertEqual(result.verifiedBatches, 20)
        XCTAssertTrue(result.coversAllTwentyOneBatches)
        XCTAssertFalse(result.isMasterManifestComplete)
    }

    func testEmptyManifestIsRejected() {
        let result = FinalTwentyBatchMasterCompletionManifest.evaluate(batches: [])
        XCTAssertEqual(result.totalBatches, 0)
        XCTAssertEqual(result.verifiedBatches, 0)
        XCTAssertFalse(result.coversAllTwentyOneBatches)
        XCTAssertFalse(result.isMasterManifestComplete)
    }
}
