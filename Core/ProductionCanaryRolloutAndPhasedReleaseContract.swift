import Foundation

public struct PhasedReleaseStageCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let releaseDay: Int
    public let rolloutPercentage: Int
    public let minCrashFreePerMille: Int
    public let supportsInstantFeatureFlagRollback: Bool

    public var isCompliant: Bool {
        (1...7).contains(releaseDay) &&
            (1...100).contains(rolloutPercentage) &&
            minCrashFreePerMille >= 995 &&
            supportsInstantFeatureFlagRollback
    }

    public init(
        id: String,
        releaseDay: Int,
        rolloutPercentage: Int,
        minCrashFreePerMille: Int,
        supportsInstantFeatureFlagRollback: Bool
    ) {
        self.id = id
        self.releaseDay = releaseDay
        self.rolloutPercentage = rolloutPercentage
        self.minCrashFreePerMille = minCrashFreePerMille
        self.supportsInstantFeatureFlagRollback = supportsInstantFeatureFlagRollback
    }
}

public struct ProductionCanaryRolloutAndPhasedReleaseContract: Sendable, Equatable {
    public static let canonicalStages: [PhasedReleaseStageCheck] = [
        PhasedReleaseStageCheck(
            id: "phased-release-day-1",
            releaseDay: 1,
            rolloutPercentage: 1,
            minCrashFreePerMille: 997,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-2",
            releaseDay: 2,
            rolloutPercentage: 2,
            minCrashFreePerMille: 997,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-3",
            releaseDay: 3,
            rolloutPercentage: 5,
            minCrashFreePerMille: 996,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-4",
            releaseDay: 4,
            rolloutPercentage: 10,
            minCrashFreePerMille: 996,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-5",
            releaseDay: 5,
            rolloutPercentage: 20,
            minCrashFreePerMille: 995,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-6",
            releaseDay: 6,
            rolloutPercentage: 50,
            minCrashFreePerMille: 995,
            supportsInstantFeatureFlagRollback: true
        ),
        PhasedReleaseStageCheck(
            id: "phased-release-day-7",
            releaseDay: 7,
            rolloutPercentage: 100,
            minCrashFreePerMille: 995,
            supportsInstantFeatureFlagRollback: true
        )
    ]

    public init() {}

    public static func evaluate(
        stages: [PhasedReleaseStageCheck] = canonicalStages
    ) -> (totalStages: Int, compliantStages: Int, isCanaryPlanReady: Bool) {
        let totalStages = stages.count
        let compliantStages = stages.filter(\.isCompliant).count
        let isCanaryPlanReady = totalStages == 7 && compliantStages == totalStages
        return (
            totalStages: totalStages,
            compliantStages: compliantStages,
            isCanaryPlanReady: isCanaryPlanReady
        )
    }
}
