import XCTest
@testable import QuestifyCore

final class CloudCIShardExecutionContractTests: XCTestCase {
    private let commitSHA = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678"
    private let treeSHA = "f0e1d2c3b4a5968778695a4b3c2d1e0f9a8b7c6d"
    private let runID = "9001"
    private let attempt = "1"

    private func validControlGates() -> [CloudCIControlGateResult] {
        CloudCIControlGate.canonicalOrder.map {
            CloudCIControlGateResult(gate: $0, runner: .ubuntu2404, passed: true)
        }
    }

    private func validArtifactBundle() -> CloudCIBuildArtifactBundle {
        CloudCIBuildArtifactBundle(
            commitSHA: commitSHA,
            treeSHA: treeSHA,
            runID: runID,
            attempt: attempt,
            mode: .buildForTesting,
            hasReceiptJSON: true,
            hasProductsTarGz: true
        )
    }

    private func validShards() -> [CloudCIShardAssignment] {
        [
            CloudCIShardAssignment(
                shard: .core,
                assignedMethods: ["QuestifyCoreTests/A/test1", "QuestifyCoreTests/A/test2"],
                passedMethods: ["QuestifyCoreTests/A/test1", "QuestifyCoreTests/A/test2"]
            ),
            CloudCIShardAssignment(
                shard: .appUnit,
                assignedMethods: ["QuestifyAppUnitTests/B/test1"],
                passedMethods: ["QuestifyAppUnitTests/B/test1"]
            ),
            CloudCIShardAssignment(
                shard: .ui0,
                assignedMethods: ["QuestifyUITests/C/test0"],
                passedMethods: ["QuestifyUITests/C/test0"]
            ),
            CloudCIShardAssignment(
                shard: .ui1,
                assignedMethods: ["QuestifyUITests/C/test1"],
                passedMethods: ["QuestifyUITests/C/test1"]
            ),
            CloudCIShardAssignment(
                shard: .ui2,
                assignedMethods: ["QuestifyUITests/C/test2"],
                passedMethods: ["QuestifyUITests/C/test2"]
            )
        ]
    }

    private var expectedMethods: Set<String> {
        [
            "QuestifyCoreTests/A/test1",
            "QuestifyCoreTests/A/test2",
            "QuestifyAppUnitTests/B/test1",
            "QuestifyUITests/C/test0",
            "QuestifyUITests/C/test1",
            "QuestifyUITests/C/test2"
        ]
    }

    func testValidPipelinePassesControlGatesBuildOnceAndParallelShards() {
        let evaluation = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: validControlGates(),
            buildArtifact: validArtifactBundle(),
            shards: validShards()
        )

        XCTAssertTrue(evaluation.isValid)
        XCTAssertTrue(evaluation.controlGatesPassed)
        XCTAssertTrue(evaluation.artifactBundleIntact)
        XCTAssertTrue(evaluation.shardPartitionComplete)
        XCTAssertTrue(evaluation.allShardsSucceeded)
        XCTAssertTrue(evaluation.failures.isEmpty)
        XCTAssertEqual(CloudCIShardExecutionContract.shardDurationLimitSeconds, 1500)
        XCTAssertEqual(CloudCIShardExecutionContract.shardMethodLimit, 900)
    }

    func testControlGateOrderAndFailureFailClosed() {
        var reorderedGates = validControlGates()
        reorderedGates.swapAt(0, 1)

        let orderEval = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: reorderedGates,
            buildArtifact: validArtifactBundle(),
            shards: validShards()
        )
        XCTAssertFalse(orderEval.isValid)
        XCTAssertFalse(orderEval.controlGatesPassed)
        XCTAssertTrue(orderEval.failures.contains(.controlGateOrderInvalid))

        var failedGates = validControlGates()
        failedGates[4] = CloudCIControlGateResult(gate: .contractChecks, runner: .ubuntu2404, passed: false)

        let failedGateEval = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: failedGates,
            buildArtifact: validArtifactBundle(),
            shards: validShards()
        )
        XCTAssertFalse(failedGateEval.isValid)
        XCTAssertFalse(failedGateEval.controlGatesPassed)
        XCTAssertEqual(failedGateEval.failures, [.controlGateFailed])
    }

    func testShardPartitionCompletenessDetectsMissingShardAndDuplicateOrMissingMethods() {
        let incompleteShards = Array(validShards().dropLast())
        let missingShardEval = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: validControlGates(),
            buildArtifact: validArtifactBundle(),
            shards: incompleteShards
        )
        XCTAssertFalse(missingShardEval.isValid)
        XCTAssertFalse(missingShardEval.shardPartitionComplete)
        XCTAssertTrue(missingShardEval.failures.contains(.missingRequiredShard))
        XCTAssertTrue(missingShardEval.failures.contains(.partitionUnionMismatch))

        var overlappingShards = validShards()
        overlappingShards[3] = CloudCIShardAssignment(
            shard: .ui1,
            assignedMethods: ["QuestifyUITests/C/test0", "QuestifyUITests/C/test1"],
            passedMethods: ["QuestifyUITests/C/test0", "QuestifyUITests/C/test1"]
        )
        let overlapEval = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: validControlGates(),
            buildArtifact: validArtifactBundle(),
            shards: overlappingShards
        )
        XCTAssertFalse(overlapEval.isValid)
        XCTAssertFalse(overlapEval.shardPartitionComplete)
        XCTAssertEqual(overlapEval.failures, [.duplicateMethodAcrossShards])
    }

    func testArtifactBundleIntegrityAndTestWithoutBuildingModeEnforcement() {
        let brokenArtifact = CloudCIBuildArtifactBundle(
            commitSHA: commitSHA,
            treeSHA: treeSHA,
            runID: runID,
            attempt: attempt,
            mode: .buildForTesting,
            hasReceiptJSON: true,
            hasProductsTarGz: false
        )
        var wrongModeShards = validShards()
        wrongModeShards[2] = CloudCIShardAssignment(
            shard: .ui0,
            runner: .macos26,
            executionMode: .buildAndTest,
            assignedMethods: ["QuestifyUITests/C/test0"],
            passedMethods: ["QuestifyUITests/C/test0"]
        )

        let evaluation = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: validControlGates(),
            buildArtifact: brokenArtifact,
            shards: wrongModeShards
        )

        XCTAssertFalse(evaluation.isValid)
        XCTAssertFalse(evaluation.artifactBundleIntact)
        XCTAssertEqual(
            evaluation.failures,
            [.artifactBundleCorruptedOrMismatched, .shardExecutionModeMismatch]
        )
    }

    func testSingleFailedMethodInAnyShardFailsClosed() {
        var failingShards = validShards()
        failingShards[4] = CloudCIShardAssignment(
            shard: .ui2,
            assignedMethods: ["QuestifyUITests/C/test2"],
            passedMethods: [],
            failedMethods: ["QuestifyUITests/C/test2"]
        )

        let evaluation = CloudCIShardExecutionContract.evaluate(
            expectedCommitSHA: commitSHA,
            expectedTreeSHA: treeSHA,
            expectedRunID: runID,
            expectedAttempt: attempt,
            expectedSelectedMethods: expectedMethods,
            controlGates: validControlGates(),
            buildArtifact: validArtifactBundle(),
            shards: failingShards
        )

        XCTAssertFalse(evaluation.isValid)
        XCTAssertTrue(evaluation.controlGatesPassed)
        XCTAssertTrue(evaluation.artifactBundleIntact)
        XCTAssertTrue(evaluation.shardPartitionComplete)
        XCTAssertFalse(evaluation.allShardsSucceeded)
        XCTAssertEqual(evaluation.failures, [.shardExecutionFailed])
    }
}
