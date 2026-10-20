import Foundation

/// Runner operating systems used by `.github/workflows/native-ios.yml`.
public enum CloudCIRunnerOS: String, CaseIterable, Equatable, Sendable {
    case ubuntu2404 = "ubuntu-24.04"
    case macos26 = "macos-26"
}

/// Canonical Ubuntu control gates executed before macOS native build/test shards.
public enum CloudCIControlGate: String, CaseIterable, Equatable, Sendable {
    case currentCICheck = "current_ci.py check"
    case testCurrentCI = "test_current_ci"
    case checkScaffold = "check_scaffold.py"
    case checkRoamPrivateTools = "check_roam_private_tools.py"
    case contractChecks = "ContractChecks"

    public static let canonicalOrder: [CloudCIControlGate] = [
        .currentCICheck,
        .testCurrentCI,
        .checkScaffold,
        .checkRoamPrivateTools,
        .contractChecks
    ]
}

/// Execution mode for native macOS shards (`build-for-testing` vs `test-without-building`).
public enum CloudCIShardExecutionMode: String, Equatable, Sendable {
    case buildAndTest = "build-and-test"
    case buildForTesting = "build-for-testing"
    case testWithoutBuilding = "test-without-building"
}

/// Standard native test shards (`core`, `app-unit`, `ui-0`, `ui-1`, `ui-2`).
public enum CloudCITestShard: String, CaseIterable, Equatable, Sendable {
    case core = "core"
    case appUnit = "app-unit"
    case ui0 = "ui-0"
    case ui1 = "ui-1"
    case ui2 = "ui-2"

    public var requiredExecutionMode: CloudCIShardExecutionMode {
        switch self {
        case .core, .appUnit:
            return .buildAndTest
        case .ui0, .ui1, .ui2:
            return .testWithoutBuilding
        }
    }

    public var requiresPrebuiltArtifact: Bool {
        requiredExecutionMode == .testWithoutBuilding
    }
}

/// Result of a single Ubuntu control gate step.
public struct CloudCIControlGateResult: Equatable, Sendable {
    public let gate: CloudCIControlGate
    public let runner: CloudCIRunnerOS
    public let passed: Bool

    public init(gate: CloudCIControlGate, runner: CloudCIRunnerOS = .ubuntu2404, passed: Bool) {
        self.gate = gate
        self.runner = runner
        self.passed = passed
    }
}

/// Same-run `ui-build` (`build-for-testing`) artifact bundle transferred to `ui-*` shards.
public struct CloudCIBuildArtifactBundle: Equatable, Sendable {
    public let commitSHA: String
    public let treeSHA: String
    public let runID: String
    public let attempt: String
    public let mode: CloudCIShardExecutionMode
    public let hasReceiptJSON: Bool
    public let hasProductsTarGz: Bool

    public init(
        commitSHA: String,
        treeSHA: String,
        runID: String,
        attempt: String,
        mode: CloudCIShardExecutionMode = .buildForTesting,
        hasReceiptJSON: Bool,
        hasProductsTarGz: Bool
    ) {
        self.commitSHA = commitSHA
        self.treeSHA = treeSHA
        self.runID = runID
        self.attempt = attempt
        self.mode = mode
        self.hasReceiptJSON = hasReceiptJSON
        self.hasProductsTarGz = hasProductsTarGz
    }

    public func matchesSourceIdentity(
        commitSHA expectedCommit: String,
        treeSHA expectedTree: String,
        runID expectedRunID: String,
        attempt expectedAttempt: String
    ) -> Bool {
        mode == .buildForTesting
            && hasReceiptJSON
            && hasProductsTarGz
            && !commitSHA.isEmpty
            && !treeSHA.isEmpty
            && commitSHA == expectedCommit
            && treeSHA == expectedTree
            && runID == expectedRunID
            && attempt == expectedAttempt
    }
}

/// Assignment and execution record for a single macOS test shard.
public struct CloudCIShardAssignment: Equatable, Sendable {
    public let shard: CloudCITestShard
    public let runner: CloudCIRunnerOS
    public let executionMode: CloudCIShardExecutionMode
    public let assignedMethods: [String]
    public let passedMethods: [String]
    public let failedMethods: [String]

    public init(
        shard: CloudCITestShard,
        runner: CloudCIRunnerOS = .macos26,
        executionMode: CloudCIShardExecutionMode? = nil,
        assignedMethods: [String],
        passedMethods: [String],
        failedMethods: [String] = []
    ) {
        self.shard = shard
        self.runner = runner
        self.executionMode = executionMode ?? shard.requiredExecutionMode
        self.assignedMethods = assignedMethods
        self.passedMethods = passedMethods
        self.failedMethods = failedMethods
    }
}

/// Fail-closed validation reasons for the cloud CI pipeline contract.
public enum CloudCIValidationFailure: String, CaseIterable, Equatable, Sendable {
    case controlGateOrderInvalid
    case controlGateRunnerMismatch
    case controlGateFailed
    case artifactBundleCorruptedOrMismatched
    case missingRequiredShard
    case duplicateShardAssignment
    case shardRunnerMismatch
    case shardExecutionModeMismatch
    case shardMethodLimitExceeded
    case partitionUnionMismatch
    case duplicateMethodAcrossShards
    case shardExecutionFailed
}

/// Deterministic evaluation outcome for a cloud CI pipeline run.
public struct CloudCIPipelineEvaluation: Equatable, Sendable {
    public let isValid: Bool
    public let controlGatesPassed: Bool
    public let artifactBundleIntact: Bool
    public let shardPartitionComplete: Bool
    public let allShardsSucceeded: Bool
    public let failures: [CloudCIValidationFailure]

    public init(
        isValid: Bool,
        controlGatesPassed: Bool,
        artifactBundleIntact: Bool,
        shardPartitionComplete: Bool,
        allShardsSucceeded: Bool,
        failures: [CloudCIValidationFailure]
    ) {
        self.isValid = isValid
        self.controlGatesPassed = controlGatesPassed
        self.artifactBundleIntact = artifactBundleIntact
        self.shardPartitionComplete = shardPartitionComplete
        self.allShardsSucceeded = allShardsSucceeded
        self.failures = failures
    }
}

/// Contract validator for the repository's `ubuntu-24.04` + `macos-26` cloud CI pipeline.
public enum CloudCIShardExecutionContract {
    public static let shardDurationLimitSeconds: Int = 1500
    public static let shardMethodLimit: Int = 900

    public static func evaluate(
        expectedCommitSHA: String,
        expectedTreeSHA: String,
        expectedRunID: String,
        expectedAttempt: String,
        expectedSelectedMethods: Set<String>,
        controlGates: [CloudCIControlGateResult],
        buildArtifact: CloudCIBuildArtifactBundle,
        shards: [CloudCIShardAssignment]
    ) -> CloudCIPipelineEvaluation {
        var failures: [CloudCIValidationFailure] = []

        let gateOrderMatches = controlGates.map(\.gate) == CloudCIControlGate.canonicalOrder
        if !gateOrderMatches {
            failures.append(.controlGateOrderInvalid)
        }
        if controlGates.contains(where: { $0.runner != .ubuntu2404 }) {
            failures.append(.controlGateRunnerMismatch)
        }
        let gatesPassed = gateOrderMatches
            && controlGates.allSatisfy { $0.runner == .ubuntu2404 && $0.passed }
        if !controlGates.allSatisfy(\.passed) {
            failures.append(.controlGateFailed)
        }

        let artifactOK = buildArtifact.matchesSourceIdentity(
            commitSHA: expectedCommitSHA,
            treeSHA: expectedTreeSHA,
            runID: expectedRunID,
            attempt: expectedAttempt
        )
        if !artifactOK {
            failures.append(.artifactBundleCorruptedOrMismatched)
        }

        let shardTypes = shards.map(\.shard)
        if Set(shardTypes).count != shardTypes.count {
            failures.append(.duplicateShardAssignment)
        }
        if Set(shardTypes) != Set(CloudCITestShard.allCases) {
            failures.append(.missingRequiredShard)
        }
        if shards.contains(where: { $0.runner != .macos26 }) {
            failures.append(.shardRunnerMismatch)
        }
        if shards.contains(where: { $0.executionMode != $0.shard.requiredExecutionMode }) {
            failures.append(.shardExecutionModeMismatch)
        }
        if shards.contains(where: { $0.assignedMethods.count > shardMethodLimit }) {
            failures.append(.shardMethodLimitExceeded)
        }

        let allAssignedList = shards.flatMap(\.assignedMethods)
        let allAssignedSet = Set(allAssignedList)
        if allAssignedList.count != allAssignedSet.count {
            failures.append(.duplicateMethodAcrossShards)
        }
        let unionMatches = allAssignedSet == expectedSelectedMethods && !expectedSelectedMethods.isEmpty
        if !unionMatches {
            failures.append(.partitionUnionMismatch)
        }

        let shardsSucceeded = shards.allSatisfy { shard in
            shard.failedMethods.isEmpty
                && Set(shard.passedMethods) == Set(shard.assignedMethods)
                && shard.passedMethods.count == shard.assignedMethods.count
        }
        if !shardsSucceeded {
            failures.append(.shardExecutionFailed)
        }

        let partitionComplete = Set(shardTypes) == Set(CloudCITestShard.allCases)
            && Set(shardTypes).count == shardTypes.count
            && allAssignedList.count == allAssignedSet.count
            && unionMatches

        var deduplicatedFailures: [CloudCIValidationFailure] = []
        var seen = Set<CloudCIValidationFailure>()
        for failure in failures where seen.insert(failure).inserted {
            deduplicatedFailures.append(failure)
        }

        return CloudCIPipelineEvaluation(
            isValid: deduplicatedFailures.isEmpty,
            controlGatesPassed: gatesPassed,
            artifactBundleIntact: artifactOK,
            shardPartitionComplete: partitionComplete,
            allShardsSucceeded: shardsSucceeded,
            failures: deduplicatedFailures
        )
    }
}
