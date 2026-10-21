import XCTest
@testable import QuestifyCore

final class CrashResilienceAndMetricKitDiagnosticsAuditTests: XCTestCase {
    func testCanonicalCategoriesPassCrashResilienceEvaluation() {
        let result = CrashResilienceAndMetricKitDiagnosticsAudit.evaluate()
        XCTAssertEqual(result.totalCategories, 4)
        XCTAssertEqual(result.compliantCategories, 4)
        XCTAssertTrue(result.coversAllCategories)
        XCTAssertTrue(result.isCrashResilienceReady)
        XCTAssertEqual(
            CrashResilienceAndMetricKitDiagnosticsAudit.canonicalDescriptors.map(\.category),
            MetricKitDiagnosticCategory.allCases
        )
    }

    func testMainThreadHangThresholdExceeding250MsFailsCompliance() {
        var descriptors = CrashResilienceAndMetricKitDiagnosticsAudit.canonicalDescriptors
        descriptors[1] = CrashResilienceCheckDescriptor(
            id: "metrickit-hang-over-threshold",
            category: .hangDiagnostic,
            maxMainThreadBlockMs: 320,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: true
        )
        XCTAssertFalse(descriptors[1].isCompliant)

        let result = CrashResilienceAndMetricKitDiagnosticsAudit.evaluate(descriptors: descriptors)
        XCTAssertEqual(result.totalCategories, 4)
        XCTAssertEqual(result.compliantCategories, 3)
        XCTAssertTrue(result.coversAllCategories)
        XCTAssertFalse(result.isCrashResilienceReady)
    }

    func testUnstrippedPIIOrForceUnwrapInRuntimePathFailsCompliance() {
        var descriptors = CrashResilienceAndMetricKitDiagnosticsAudit.canonicalDescriptors
        descriptors[0] = CrashResilienceCheckDescriptor(
            id: "metrickit-crash-pii-leak",
            category: .crashDiagnostic,
            maxMainThreadBlockMs: 200,
            stripsUserPIIBeforePersist: false,
            zeroForceUnwrapInRuntimePath: true
        )
        descriptors[2] = CrashResilienceCheckDescriptor(
            id: "metrickit-cpu-force-unwrap",
            category: .cpuExceptionDiagnostic,
            maxMainThreadBlockMs: 200,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: false
        )
        XCTAssertFalse(descriptors[0].isCompliant)
        XCTAssertFalse(descriptors[2].isCompliant)

        let result = CrashResilienceAndMetricKitDiagnosticsAudit.evaluate(descriptors: descriptors)
        XCTAssertEqual(result.compliantCategories, 2)
        XCTAssertFalse(result.isCrashResilienceReady)
    }

    func testMissingMetricKitCategoryFailsCoverageAndReadiness() {
        let incomplete = Array(CrashResilienceAndMetricKitDiagnosticsAudit.canonicalDescriptors.prefix(3))
        let result = CrashResilienceAndMetricKitDiagnosticsAudit.evaluate(descriptors: incomplete)
        XCTAssertEqual(result.totalCategories, 3)
        XCTAssertEqual(result.compliantCategories, 3)
        XCTAssertFalse(result.coversAllCategories)
        XCTAssertFalse(result.isCrashResilienceReady)
    }
}
