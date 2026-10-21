import XCTest
@testable import QuestifyCore

final class UITestShardPartitionAuditTests: XCTestCase {
    private let sampleTests = [
        "QuestifyUITests/testAuthEntryFlow",
        "QuestifyUITests/testCouponRuntimeJourney",
        "QuestifyUITests/testMapCoreManualBrowse",
        "QuestifyUITests/testMerchantAICommerceFixture",
        "QuestifyUITests/testMerchantCityTemplateHandoffFixture",
        "QuestifyUITests/testProfileSelfEditFlow",
        "QuestifyUITests/testProjectEditorOffScreenReveal",
        "QuestifyUITests/testSecondRegistrationFixture"
    ]

    func testBalancedThreeShardPartitioningProducesHealthyAudit() {
        let partitions = UITestShardPartitionAudit.partitionTests(sampleTests)
        XCTAssertEqual(partitions[.ui0]?.count, 3)
        XCTAssertEqual(partitions[.ui1]?.count, 3)
        XCTAssertEqual(partitions[.ui2]?.count, 2)

        let context = UITestLaunchIsolationContext(
            isDebugBuild: true,
            launchArguments: [
                "--uitesting",
                "--merchant-ai-commerce-fixture"
            ],
            sessionShortCircuitedToNil: true,
            outboundNetworkURLs: []
        )

        let report = UITestShardPartitionAudit.audit(
            discoveredTests: sampleTests,
            shardAssignments: partitions,
            launchContext: context
        )
        XCTAssertTrue(report.isHealthy)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertTrue(report.missingTests.isEmpty)
        XCTAssertTrue(report.duplicateTests.isEmpty)
        XCTAssertTrue(report.unknownShardTests.isEmpty)
        XCTAssertEqual(
            report.activeFixtureFlags,
            [.uiTesting, .merchantAICommerceFixture]
        )
        XCTAssertTrue(report.sessionShortCircuitedToNil)
    }

    func testDuplicateMissingUnknownAndUnbalancedShardDetection() {
        let brokenAssignments: [UITestShardIdentifier: [String]] = [
            .ui0: [
                "QuestifyUITests/testAuthEntryFlow",
                "QuestifyUITests/testCouponRuntimeJourney",
                "QuestifyUITests/testMapCoreManualBrowse",
                "QuestifyUITests/testMerchantAICommerceFixture",
                "QuestifyUITests/testGhostOrphanCase"
            ],
            .ui1: [
                "QuestifyUITests/testAuthEntryFlow",
                "QuestifyUITests/testMerchantCityTemplateHandoffFixture"
            ],
            .ui2: [
                "QuestifyUITests/testProfileSelfEditFlow"
            ]
        ]

        let context = UITestLaunchIsolationContext(
            isDebugBuild: true,
            launchArguments: ["--uitesting"],
            sessionShortCircuitedToNil: true
        )

        let report = UITestShardPartitionAudit.audit(
            discoveredTests: sampleTests,
            shardAssignments: brokenAssignments,
            launchContext: context
        )
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(
            report.missingTests,
            [
                "QuestifyUITests/testProjectEditorOffScreenReveal",
                "QuestifyUITests/testSecondRegistrationFixture"
            ]
        )
        XCTAssertEqual(
            report.duplicateTests,
            ["QuestifyUITests/testAuthEntryFlow"]
        )
        XCTAssertEqual(
            report.unknownShardTests,
            ["QuestifyUITests/testGhostOrphanCase"]
        )
        XCTAssertTrue(
            report.violations.contains(.unbalancedShardDistribution(minCount: 1, maxCount: 5))
        )
    }

    func testDebugFixtureLaunchFlagsAndSessionNilShortCircuitValidation() {
        let expectedFlags = [
            "--uitesting",
            "--second-registration-fixture",
            "--merchant-city-template-handoff-fixture",
            "--merchant-ai-commerce-fixture",
            "--uitesting-map-core-entry"
        ]
        XCTAssertEqual(UITestLaunchFixtureFlag.canonicalFlags, expectedFlags)
        XCTAssertTrue(UITestLaunchFixtureFlag.allCases.allSatisfy(\.requiresSessionNilShortCircuit))

        let partitions = UITestShardPartitionAudit.partitionTests(sampleTests)

        let unshortCircuitedContext = UITestLaunchIsolationContext(
            isDebugBuild: true,
            launchArguments: [
                "--uitesting",
                "--second-registration-fixture",
                "--merchant-city-template-handoff-fixture",
                "--uitesting-map-core-entry"
            ],
            sessionShortCircuitedToNil: false
        )
        let unshortCircuitedReport = UITestShardPartitionAudit.audit(
            discoveredTests: sampleTests,
            shardAssignments: partitions,
            launchContext: unshortCircuitedContext
        )
        XCTAssertFalse(unshortCircuitedReport.isHealthy)
        XCTAssertEqual(unshortCircuitedReport.violations, [.sessionNotShortCircuitedToNil])

        let releaseLeakContext = UITestLaunchIsolationContext(
            isDebugBuild: false,
            launchArguments: ["--uitesting", "--unknown-fixture-flag"],
            sessionShortCircuitedToNil: false
        )
        let releaseLeakReport = UITestShardPartitionAudit.audit(
            discoveredTests: sampleTests,
            shardAssignments: partitions,
            launchContext: releaseLeakContext
        )
        XCTAssertFalse(releaseLeakReport.isHealthy)
        XCTAssertEqual(
            releaseLeakReport.violations,
            [
                .fixtureFlagsInNonDebugBuild(["--uitesting"]),
                .unknownLaunchFixtureFlags(["--unknown-fixture-flag"])
            ]
        )
    }

    func testZeroNetworkIsolationRejectsLiveNetworkTrafficInUITests() {
        let partitions = UITestShardPartitionAudit.partitionTests(sampleTests)
        let leakyNetworkContext = UITestLaunchIsolationContext(
            isDebugBuild: true,
            launchArguments: ["--uitesting", "--uitesting-map-core-entry"],
            sessionShortCircuitedToNil: true,
            outboundNetworkURLs: [
                "https://api.example.com/api/userInfo",
                "http://47.103.124.64:8080/api/config/features"
            ]
        )

        let report = UITestShardPartitionAudit.audit(
            discoveredTests: sampleTests,
            shardAssignments: partitions,
            launchContext: leakyNetworkContext
        )
        XCTAssertFalse(report.isHealthy)
        XCTAssertEqual(
            report.leakedNetworkURLs,
            [
                "http://47.103.124.64:8080/api/config/features",
                "https://api.example.com/api/userInfo"
            ]
        )
        XCTAssertEqual(
            report.violations,
            [
                .liveNetworkTrafficDetected([
                    "http://47.103.124.64:8080/api/config/features",
                    "https://api.example.com/api/userInfo"
                ])
            ]
        )
    }
}
