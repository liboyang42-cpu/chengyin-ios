import Foundation

/// Four `MetricKit` diagnostic categories audited for production App Store crash & hang resilience.
public enum MetricKitDiagnosticCategory: String, Sendable, Equatable, CaseIterable {
    case crashDiagnostic
    case hangDiagnostic
    case cpuExceptionDiagnostic
    case diskWriteExceptionDiagnostic
}

/// Descriptor for a single `MetricKit` diagnostic category and runtime resilience check.
public struct CrashResilienceCheckDescriptor: Sendable, Equatable, Identifiable {
    public let id: String
    public let category: MetricKitDiagnosticCategory
    public let maxMainThreadBlockMs: Int
    public let stripsUserPIIBeforePersist: Bool
    public let zeroForceUnwrapInRuntimePath: Bool

    public init(
        id: String,
        category: MetricKitDiagnosticCategory,
        maxMainThreadBlockMs: Int = 250,
        stripsUserPIIBeforePersist: Bool = true,
        zeroForceUnwrapInRuntimePath: Bool = true
    ) {
        self.id = id
        self.category = category
        self.maxMainThreadBlockMs = maxMainThreadBlockMs
        self.stripsUserPIIBeforePersist = stripsUserPIIBeforePersist
        self.zeroForceUnwrapInRuntimePath = zeroForceUnwrapInRuntimePath
    }

    public var isCompliant: Bool {
        maxMainThreadBlockMs > 0
            && maxMainThreadBlockMs <= 250
            && stripsUserPIIBeforePersist
            && zeroForceUnwrapInRuntimePath
    }
}

/// Evaluator for App Store crash resilience, `MetricKit` diagnostic payload telemetry
/// (`MXCrashDiagnostic`, `MXHangDiagnostic`, `MXCPUExceptionDiagnostic`, `MXDiskWriteExceptionDiagnostic`),
/// main-thread hang threshold (`<= 250ms`), and PII-free symbolicated stack trace collection.
public struct CrashResilienceAndMetricKitDiagnosticsAudit: Sendable, Equatable {
    public static let canonicalDescriptors: [CrashResilienceCheckDescriptor] = [
        CrashResilienceCheckDescriptor(
            id: "metrickit-crash-diagnostic",
            category: .crashDiagnostic,
            maxMainThreadBlockMs: 250,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: true
        ),
        CrashResilienceCheckDescriptor(
            id: "metrickit-hang-diagnostic",
            category: .hangDiagnostic,
            maxMainThreadBlockMs: 250,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: true
        ),
        CrashResilienceCheckDescriptor(
            id: "metrickit-cpu-exception-diagnostic",
            category: .cpuExceptionDiagnostic,
            maxMainThreadBlockMs: 250,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: true
        ),
        CrashResilienceCheckDescriptor(
            id: "metrickit-disk-write-exception-diagnostic",
            category: .diskWriteExceptionDiagnostic,
            maxMainThreadBlockMs: 250,
            stripsUserPIIBeforePersist: true,
            zeroForceUnwrapInRuntimePath: true
        )
    ]

    public init() {}

    public static func evaluate(
        descriptors: [CrashResilienceCheckDescriptor] = canonicalDescriptors
    ) -> (totalCategories: Int, compliantCategories: Int, coversAllCategories: Bool, isCrashResilienceReady: Bool) {
        let total = descriptors.count
        let compliant = descriptors.filter(\.isCompliant).count
        let coveredCategories = Set(descriptors.map(\.category))
        let coversAll = coveredCategories == Set(MetricKitDiagnosticCategory.allCases)
            && total == MetricKitDiagnosticCategory.allCases.count
        let isReady = coversAll && compliant == total
        return (
            totalCategories: total,
            compliantCategories: compliant,
            coversAllCategories: coversAll,
            isCrashResilienceReady: isReady
        )
    }
}
