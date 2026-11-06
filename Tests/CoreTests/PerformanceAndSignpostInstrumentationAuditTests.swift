import XCTest
@testable import QuestifyCore

final class PerformanceAndSignpostInstrumentationAuditTests: XCTestCase {
    private var healthyMeasurements: [SignpostTraceMeasurement] {
        [
            SignpostTraceMeasurement(
                interval: .appColdLaunch,
                beginCount: 1,
                endCount: 1,
                p95LatencyMilliseconds: 245.0
            ),
            SignpostTraceMeasurement(
                interval: .routeMapStopProjection,
                beginCount: 12,
                endCount: 12,
                p95LatencyMilliseconds: 6.4
            ),
            SignpostTraceMeasurement(
                interval: .roamPOIClusterUpdate,
                beginCount: 18,
                endCount: 18,
                p95LatencyMilliseconds: 8.2
            ),
            SignpostTraceMeasurement(
                interval: .questChapterTransition,
                beginCount: 4,
                endCount: 4,
                p95LatencyMilliseconds: 22.0
            ),
            SignpostTraceMeasurement(
                interval: .gltfScenePrepare,
                beginCount: 2,
                endCount: 2,
                p95LatencyMilliseconds: 78.5
            )
        ]
    }

    func testAllSignpostIntervalsBalancedLinearProjectionAndWithinBudgetPassesAudit() {
        let linearSample = RouteMapProjectionComplexitySample(
            stopCount: 150,
            lookupOperations: 150,
            usesIndexedStopLookup: true,
            hasNestedLinearScan: false
        )

        let report = PerformanceAndSignpostInstrumentationAudit.audit(
            measurements: healthyMeasurements,
            routeMapSample: linearSample,
            signpostMeasureScriptVerified: true
        )

        XCTAssertTrue(report.isReadyForRelease)
        XCTAssertTrue(report.violations.isEmpty)
        XCTAssertEqual(report.registeredIntervals.count, PerformanceSignpostInterval.allCases.count)
        XCTAssertTrue(report.missingIntervals.isEmpty)
        XCTAssertTrue(report.unbalancedIntervals.isEmpty)
        XCTAssertTrue(report.overBudgetIntervals.isEmpty)
        XCTAssertTrue(report.isRouteMapProjectionLinear)
        XCTAssertEqual(
            PerformanceAndSignpostInstrumentationAudit.measureScriptRelativePath,
            "tools/signpost_measure.py"
        )
    }

    func testMissingAndUnbalancedSignpostIntervalsAreReported() {
        let incompleteMeasurements = [
            SignpostTraceMeasurement(
                interval: .appColdLaunch,
                beginCount: 1,
                endCount: 1,
                p95LatencyMilliseconds: 210.0
            ),
            SignpostTraceMeasurement(
                interval: .routeMapStopProjection,
                beginCount: 5,
                endCount: 3,
                p95LatencyMilliseconds: 9.0
            )
        ]

        let linearSample = RouteMapProjectionComplexitySample(
            stopCount: 40,
            lookupOperations: 40,
            usesIndexedStopLookup: true
        )

        let report = PerformanceAndSignpostInstrumentationAudit.audit(
            measurements: incompleteMeasurements,
            routeMapSample: linearSample
        )

        XCTAssertFalse(report.isReadyForRelease)
        XCTAssertEqual(
            report.missingIntervals,
            [.roamPOIClusterUpdate, .questChapterTransition, .gltfScenePrepare]
        )
        XCTAssertEqual(report.unbalancedIntervals, [.routeMapStopProjection])
    }

    func testQuadraticRouteMapStopProjectionIsRejected() {
        let quadraticByOperationCount = RouteMapProjectionComplexitySample(
            stopCount: 100,
            lookupOperations: 10_000,
            usesIndexedStopLookup: true,
            hasNestedLinearScan: false
        )
        XCTAssertFalse(quadraticByOperationCount.isLinearComplexityCompliant)

        let quadraticByNestedScan = RouteMapProjectionComplexitySample(
            stopCount: 20,
            lookupOperations: 20,
            usesIndexedStopLookup: false,
            hasNestedLinearScan: true
        )
        XCTAssertFalse(quadraticByNestedScan.isLinearComplexityCompliant)

        let report = PerformanceAndSignpostInstrumentationAudit.audit(
            measurements: healthyMeasurements,
            routeMapSample: quadraticByOperationCount
        )
        XCTAssertFalse(report.isReadyForRelease)
        XCTAssertFalse(report.isRouteMapProjectionLinear)
        XCTAssertEqual(
            report.violations,
            [.quadraticRouteMapProjectionDetected(stopCount: 100, lookupOperations: 10_000)]
        )
    }

    func testLatencyBudgetThresholdAndMeasureScriptVerificationChecks() {
        var overBudget = healthyMeasurements.filter {
            $0.interval != .routeMapStopProjection && $0.interval != .gltfScenePrepare
        }
        overBudget.append(
            SignpostTraceMeasurement(
                interval: .routeMapStopProjection,
                beginCount: 10,
                endCount: 10,
                p95LatencyMilliseconds: 29.5
            )
        )
        overBudget.append(
            SignpostTraceMeasurement(
                interval: .gltfScenePrepare,
                beginCount: 2,
                endCount: 2,
                p95LatencyMilliseconds: 185.0
            )
        )

        let linearSample = RouteMapProjectionComplexitySample(
            stopCount: 80,
            lookupOperations: 80,
            usesIndexedStopLookup: true
        )

        let report = PerformanceAndSignpostInstrumentationAudit.audit(
            measurements: overBudget,
            routeMapSample: linearSample,
            signpostMeasureScriptVerified: false
        )

        XCTAssertFalse(report.isReadyForRelease)
        XCTAssertEqual(report.overBudgetIntervals, [.routeMapStopProjection, .gltfScenePrepare])
        XCTAssertFalse(report.signpostMeasureScriptVerified)
        XCTAssertEqual(
            report.violations,
            [
                .signpostLatencyBudgetExceeded([.routeMapStopProjection, .gltfScenePrepare]),
                .signpostMeasureScriptNotVerified
            ]
        )
    }
}
