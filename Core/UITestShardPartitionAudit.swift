import Foundation

/// Canonical UI test shard identifiers (`ui-0`, `ui-1`, `ui-2`) used by CI matrix runs.
public enum UITestShardIdentifier: String, CaseIterable, Comparable, Hashable, Sendable {
    case ui0 = "ui-0"
    case ui1 = "ui-1"
    case ui2 = "ui-2"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Deterministic DEBUG launch flags supported by `QuestifyUITests` and `AppSessionContainer`.
public enum UITestLaunchFixtureFlag: String, CaseIterable, Comparable, Hashable, Sendable {
    case uiTesting = "--uitesting"
    case secondRegistrationFixture = "--second-registration-fixture"
    case merchantCityTemplateHandoffFixture = "--merchant-city-template-handoff-fixture"
    case merchantAICommerceFixture = "--merchant-ai-commerce-fixture"
    case mapCoreEntryFixture = "--uitesting-map-core-entry"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static var canonicalFlags: [String] {
        allCases.map(\.rawValue)
    }

    /// True when the flag triggers deterministic fixture short-circuiting in `AppSessionContainer.init`.
    public var requiresSessionNilShortCircuit: Bool {
        true
    }
}

/// Snapshot of a UI test launch configuration for auditing `AppSessionContainer.init` short-circuiting
/// and zero-network isolation.
public struct UITestLaunchIsolationContext: Equatable, Sendable {
    public let isDebugBuild: Bool
    public let launchArguments: [String]
    public let sessionShortCircuitedToNil: Bool
    public let outboundNetworkURLs: [String]

    public init(
        isDebugBuild: Bool,
        launchArguments: [String],
        sessionShortCircuitedToNil: Bool,
        outboundNetworkURLs: [String] = []
    ) {
        self.isDebugBuild = isDebugBuild
        self.launchArguments = launchArguments
        self.sessionShortCircuitedToNil = sessionShortCircuitedToNil
        self.outboundNetworkURLs = outboundNetworkURLs
    }

    public var recognizedFixtureFlags: [UITestLaunchFixtureFlag] {
        let argSet = Set(launchArguments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return UITestLaunchFixtureFlag.allCases.filter { argSet.contains($0.rawValue) }
    }

    public var unknownFixtureArguments: [String] {
        let known = Set(UITestLaunchFixtureFlag.canonicalFlags)
        return launchArguments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("--") && !known.contains($0) }
            .sorted()
    }

    /// Whether `AppSessionContainer.init` must short-circuit `session = nil`.
    public var shouldShortCircuitSessionToNil: Bool {
        isDebugBuild && !recognizedFixtureFlags.isEmpty
    }
}

/// Deterministic audit report for the 3 UI test shards (`ui-0`, `ui-1`, `ui-2`), launch fixture
/// short-circuiting, and zero-network UI test isolation.
public struct UITestShardAuditReport: Equatable, Sendable {
    public enum Violation: Equatable, Sendable {
        case emptyDiscoveredTestSuite
        case missingTestsFromShards([String])
        case duplicateTestsAcrossShards([String])
        case unknownTestsInShards([String])
        case unbalancedShardDistribution(minCount: Int, maxCount: Int)
        case fixtureFlagsInNonDebugBuild([String])
        case unknownLaunchFixtureFlags([String])
        case sessionNotShortCircuitedToNil
        case liveNetworkTrafficDetected([String])
    }

    public let shardCounts: [UITestShardIdentifier: Int]
    public let missingTests: [String]
    public let duplicateTests: [String]
    public let unknownShardTests: [String]
    public let activeFixtureFlags: [UITestLaunchFixtureFlag]
    public let sessionShortCircuitedToNil: Bool
    public let leakedNetworkURLs: [String]
    public let violations: [Violation]

    public init(
        shardCounts: [UITestShardIdentifier: Int],
        missingTests: [String],
        duplicateTests: [String],
        unknownShardTests: [String],
        activeFixtureFlags: [UITestLaunchFixtureFlag],
        sessionShortCircuitedToNil: Bool,
        leakedNetworkURLs: [String],
        violations: [Violation]
    ) {
        self.shardCounts = shardCounts
        self.missingTests = missingTests
        self.duplicateTests = duplicateTests
        self.unknownShardTests = unknownShardTests
        self.activeFixtureFlags = activeFixtureFlags
        self.sessionShortCircuitedToNil = sessionShortCircuitedToNil
        self.leakedNetworkURLs = leakedNetworkURLs
        self.violations = violations
    }

    public var isHealthy: Bool {
        violations.isEmpty
    }
}

/// Pure auditor for `QuestifyUITests` 3-shard partitioning (`ui-0`, `ui-1`, `ui-2`), DEBUG fixture
/// launch flags, `AppSessionContainer.init` (`session = nil`) short-circuiting, and zero-network isolation.
public enum UITestShardPartitionAudit {
    /// Deterministically partitions a list of UI test identifiers across `ui-0`, `ui-1`, and `ui-2`
    /// in sorted round-robin order so shard counts differ by at most 1.
    public static func partitionTests(
        _ discoveredTests: [String]
    ) -> [UITestShardIdentifier: [String]] {
        let normalized = Array(
            Set(
                discoveredTests
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()

        var assignment: [UITestShardIdentifier: [String]] = [
            .ui0: [],
            .ui1: [],
            .ui2: []
        ]
        let shards = UITestShardIdentifier.allCases
        for (index, testID) in normalized.enumerated() {
            let shard = shards[index % shards.count]
            assignment[shard, default: []].append(testID)
        }
        return assignment
    }

    /// Audits an explicit shard assignment and launch isolation context.
    public static func audit(
        discoveredTests: [String],
        shardAssignments: [UITestShardIdentifier: [String]],
        launchContext: UITestLaunchIsolationContext
    ) -> UITestShardAuditReport {
        var violations: [UITestShardAuditReport.Violation] = []

        let canonicalDiscovered = Set(
            discoveredTests
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        if canonicalDiscovered.isEmpty {
            violations.append(.emptyDiscoveredTestSuite)
        }

        var counts: [UITestShardIdentifier: Int] = [:]
        var seenCountByTest: [String: Int] = [:]

        for shard in UITestShardIdentifier.allCases {
            let entries = (shardAssignments[shard] ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            counts[shard] = entries.count
            for entry in entries {
                seenCountByTest[entry, default: 0] += 1
            }
        }

        let assignedSet = Set(seenCountByTest.keys)
        let missing = canonicalDiscovered.subtracting(assignedSet).sorted()
        if !missing.isEmpty {
            violations.append(.missingTestsFromShards(missing))
        }

        let duplicates = seenCountByTest
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        if !duplicates.isEmpty {
            violations.append(.duplicateTestsAcrossShards(duplicates))
        }

        let unknown = assignedSet.subtracting(canonicalDiscovered).sorted()
        if !unknown.isEmpty {
            violations.append(.unknownTestsInShards(unknown))
        }

        let shardSizes = UITestShardIdentifier.allCases.map { counts[$0] ?? 0 }
        if let minCount = shardSizes.min(), let maxCount = shardSizes.max(),
           maxCount - minCount > 1 {
            violations.append(.unbalancedShardDistribution(minCount: minCount, maxCount: maxCount))
        }

        let activeFlags = launchContext.recognizedFixtureFlags
        if !launchContext.isDebugBuild && !activeFlags.isEmpty {
            violations.append(.fixtureFlagsInNonDebugBuild(activeFlags.map(\.rawValue)))
        }

        let unknownFlags = launchContext.unknownFixtureArguments
        if !unknownFlags.isEmpty {
            violations.append(.unknownLaunchFixtureFlags(unknownFlags))
        }

        if launchContext.shouldShortCircuitSessionToNil && !launchContext.sessionShortCircuitedToNil {
            violations.append(.sessionNotShortCircuitedToNil)
        }

        let leakedURLs = launchContext.outboundNetworkURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        if !leakedURLs.isEmpty {
            violations.append(.liveNetworkTrafficDetected(leakedURLs))
        }

        return UITestShardAuditReport(
            shardCounts: counts,
            missingTests: missing,
            duplicateTests: duplicates,
            unknownShardTests: unknown,
            activeFixtureFlags: activeFlags,
            sessionShortCircuitedToNil: launchContext.sessionShortCircuitedToNil,
            leakedNetworkURLs: leakedURLs,
            violations: violations
        )
    }
}
