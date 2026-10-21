import Foundation

/// Canonical `OSSignposter` Points-of-Interest intervals emitted by `NativePerformanceSignposts` (`I10`).
public enum PerformanceSignpostInterval: String, CaseIterable, Comparable, Hashable, Sendable {
    case appColdLaunch = "AppColdLaunch"
    case routeMapStopProjection = "RouteMapStopProjection"
    case roamPOIClusterUpdate = "RoamPOIClusterUpdate"
    case questChapterTransition = "QuestChapterTransition"
    case gltfScenePrepare = "GLTFScenePrepare"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static var canonicalNames: [String] {
        allCases.map(\.rawValue)
    }

    /// Default p95 latency budget in milliseconds enforced by `tools/signpost_measure.py`.
    public var defaultP95BudgetMilliseconds: Double {
        switch self {
        case .appColdLaunch:
            return 400.0
        case .routeMapStopProjection:
            return 16.0
        case .roamPOIClusterUpdate:
            return 16.0
        case .questChapterTransition:
            return 50.0
        case .gltfScenePrepare:
            return 120.0
        }
    }
}

/// Complexity sample for `PlayRouteMapView` stop projection (`I10`).
/// Verifies that stop projection uses O(N) pre-indexed dictionary/set lookup rather than O(N^2) nested scans.
public struct RouteMapProjectionComplexitySample: Equatable, Sendable {
    public let stopCount: Int
    public let lookupOperations: Int
    public let usesIndexedStopLookup: Bool
    public let hasNestedLinearScan: Bool

    public init(
        stopCount: Int,
        lookupOperations: Int,
        usesIndexedStopLookup: Bool,
        hasNestedLinearScan: Bool = false
    ) {
        self.stopCount = max(0, stopCount)
        self.lookupOperations = max(0, lookupOperations)
        self.usesIndexedStopLookup = usesIndexedStopLookup
        self.hasNestedLinearScan = hasNestedLinearScan
    }

    /// True when the projection is O(N) and free of quadratic nested scans.
    public var isLinearComplexityCompliant: Bool {
        guard usesIndexedStopLookup, !hasNestedLinearScan else {
            return false
        }
        let linearCeiling = max(1, stopCount * 2)
        return lookupOperations <= linearCeiling
    }
}

/// Trace measurement sample produced by `tools/signpost_measure.py` for a single signpost interval.
public struct SignpostTraceMeasurement: Equatable, Sendable {
    public let interval: PerformanceSignpostInterval
    public let beginCount: Int
    public let endCount: Int
    public let p95LatencyMilliseconds: Double
    public let customBudgetMilliseconds: Double?

    public init(
        interval: PerformanceSignpostInterval,
        beginCount: Int,
        endCount: Int,
        p95LatencyMilliseconds: Double,
        customBudgetMilliseconds: Double? = nil
    ) {
        self.interval = interval
        self.beginCount = beginCount
        self.endCount = endCount
        self.p95LatencyMilliseconds = p95LatencyMilliseconds
        self.customBudgetMilliseconds = customBudgetMilliseconds
    }

    public var effectiveBudgetMilliseconds: Double {
        customBudgetMilliseconds ?? interval.defaultP95BudgetMilliseconds
    }

    public var isBalancedAndRecorded: Bool {
        beginCount > 0 && beginCount == endCount
    }

    public var isWithinLatencyBudget: Bool {
        p95LatencyMilliseconds >= 0 && p95LatencyMilliseconds <= effectiveBudgetMilliseconds
    }
}

/// Deterministic `I10` performance & signpost instrumentation audit report.
public struct PerformanceInstrumentationAuditReport: Equatable, Sendable {
    public enum Violation: Equatable, Sendable {
        case missingSignpostIntervals([PerformanceSignpostInterval])
        case unbalancedOrZeroSignpostIntervals([PerformanceSignpostInterval])
        case quadraticRouteMapProjectionDetected(stopCount: Int, lookupOperations: Int)
        case signpostLatencyBudgetExceeded([PerformanceSignpostInterval])
        case signpostMeasureScriptNotVerified
    }

    public let registeredIntervals: [PerformanceSignpostInterval]
    public let missingIntervals: [PerformanceSignpostInterval]
    public let unbalancedIntervals: [PerformanceSignpostInterval]
    public let overBudgetIntervals: [PerformanceSignpostInterval]
    public let isRouteMapProjectionLinear: Bool
    public let signpostMeasureScriptVerified: Bool
    public let violations: [Violation]

    public init(
        registeredIntervals: [PerformanceSignpostInterval],
        missingIntervals: [PerformanceSignpostInterval],
        unbalancedIntervals: [PerformanceSignpostInterval],
        overBudgetIntervals: [PerformanceSignpostInterval],
        isRouteMapProjectionLinear: Bool,
        signpostMeasureScriptVerified: Bool,
        violations: [Violation]
    ) {
        self.registeredIntervals = registeredIntervals
        self.missingIntervals = missingIntervals
        self.unbalancedIntervals = unbalancedIntervals
        self.overBudgetIntervals = overBudgetIntervals
        self.isRouteMapProjectionLinear = isRouteMapProjectionLinear
        self.signpostMeasureScriptVerified = signpostMeasureScriptVerified
        self.violations = violations
    }

    public var isReadyForRelease: Bool {
        violations.isEmpty
    }
}

/// Pure auditor for `I10` `OSSignposter` POI intervals (`NativePerformanceSignposts`),
/// `PlayRouteMapView` O(N) stop projection, and `tools/signpost_measure.py` trace budgets.
public enum PerformanceAndSignpostInstrumentationAudit {
    public static let measureScriptRelativePath = "tools/signpost_measure.py"

    public static func audit(
        measurements: [SignpostTraceMeasurement],
        routeMapSample: RouteMapProjectionComplexitySample,
        signpostMeasureScriptVerified: Bool = true
    ) -> PerformanceInstrumentationAuditReport {
        var violations: [PerformanceInstrumentationAuditReport.Violation] = []

        var byInterval: [PerformanceSignpostInterval: SignpostTraceMeasurement] = [:]
        for item in measurements {
            byInterval[item.interval] = item
        }

        let registered = byInterval.keys.sorted()
        let missing = PerformanceSignpostInterval.allCases.filter { byInterval[$0] == nil }
        if !missing.isEmpty {
            violations.append(.missingSignpostIntervals(missing))
        }

        let unbalanced = PerformanceSignpostInterval.allCases.filter { interval in
            guard let sample = byInterval[interval] else { return false }
            return !sample.isBalancedAndRecorded
        }
        if !unbalanced.isEmpty {
            violations.append(.unbalancedOrZeroSignpostIntervals(unbalanced))
        }

        if !routeMapSample.isLinearComplexityCompliant {
            violations.append(
                .quadraticRouteMapProjectionDetected(
                    stopCount: routeMapSample.stopCount,
                    lookupOperations: routeMapSample.lookupOperations
                )
            )
        }

        let overBudget = PerformanceSignpostInterval.allCases.filter { interval in
            guard let sample = byInterval[interval] else { return false }
            return !sample.isWithinLatencyBudget
        }
        if !overBudget.isEmpty {
            violations.append(.signpostLatencyBudgetExceeded(overBudget))
        }

        if !signpostMeasureScriptVerified {
            violations.append(.signpostMeasureScriptNotVerified)
        }

        return PerformanceInstrumentationAuditReport(
            registeredIntervals: registered,
            missingIntervals: missing,
            unbalancedIntervals: unbalanced,
            overBudgetIntervals: overBudget,
            isRouteMapProjectionLinear: routeMapSample.isLinearComplexityCompliant,
            signpostMeasureScriptVerified: signpostMeasureScriptVerified,
            violations: violations
        )
    }
}
