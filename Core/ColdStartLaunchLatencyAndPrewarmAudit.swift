import Foundation

public struct ColdStartStageBudgetCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let stageName: String
    public let budgetMs: Int
    public let usesLazySubsystemsOnMainActor: Bool
    public let zeroSyncNetworkOrHeavyDiskIO: Bool

    public var isCompliant: Bool {
        (10...400).contains(budgetMs) &&
            usesLazySubsystemsOnMainActor &&
            zeroSyncNetworkOrHeavyDiskIO
    }

    public init(
        id: String,
        stageName: String,
        budgetMs: Int,
        usesLazySubsystemsOnMainActor: Bool,
        zeroSyncNetworkOrHeavyDiskIO: Bool
    ) {
        self.id = id
        self.stageName = stageName
        self.budgetMs = budgetMs
        self.usesLazySubsystemsOnMainActor = usesLazySubsystemsOnMainActor
        self.zeroSyncNetworkOrHeavyDiskIO = zeroSyncNetworkOrHeavyDiskIO
    }
}

public struct ColdStartLaunchLatencyAndPrewarmAudit: Sendable, Equatable {
    public static let canonicalStages: [ColdStartStageBudgetCheck] = [
        ColdStartStageBudgetCheck(
            id: "process-main-to-questify-app-init",
            stageName: "process-main-to-questify-app-init",
            budgetMs: 80,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: true
        ),
        ColdStartStageBudgetCheck(
            id: "appsession-container-bootstrap",
            stageName: "appsession-container-bootstrap",
            budgetMs: 90,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: true
        ),
        ColdStartStageBudgetCheck(
            id: "first-root-view-skeleton-render",
            stageName: "first-root-view-skeleton-render",
            budgetMs: 110,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: true
        ),
        ColdStartStageBudgetCheck(
            id: "deferred-background-journal-prewarm",
            stageName: "deferred-background-journal-prewarm",
            budgetMs: 90,
            usesLazySubsystemsOnMainActor: true,
            zeroSyncNetworkOrHeavyDiskIO: true
        )
    ]

    public init() {}

    public static func evaluate(
        stages: [ColdStartStageBudgetCheck] = canonicalStages
    ) -> (totalStages: Int, compliantStages: Int, totalBudgetMs: Int, isColdStartFast: Bool) {
        let totalStages = stages.count
        let compliantStages = stages.filter(\.isCompliant).count
        let totalBudgetMs = stages.reduce(0) { $0 + $1.budgetMs }
        let isColdStartFast = totalStages > 0 &&
            compliantStages == totalStages &&
            totalBudgetMs <= 400
        return (
            totalStages: totalStages,
            compliantStages: compliantStages,
            totalBudgetMs: totalBudgetMs,
            isColdStartFast: isColdStartFast
        )
    }
}
