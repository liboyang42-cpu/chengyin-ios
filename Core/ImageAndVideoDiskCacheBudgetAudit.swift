import Foundation

/// Policy auditing memory and disk media cache budgets (`memoryLimitMB <= 150`, `diskLimitMB <= 500`),
/// immediate memory-warning eviction, and `I05` business `404`/`DELETED` post media cache purge.
public struct MediaCacheBudgetPolicy: Sendable, Equatable, Identifiable {
    public let id: String
    public let memoryLimitMB: Int
    public let diskLimitMB: Int
    public let purgesOnMemoryWarning: Bool
    public let evictsDeletedOr404MediaImmediately: Bool

    public init(
        id: String,
        memoryLimitMB: Int,
        diskLimitMB: Int,
        purgesOnMemoryWarning: Bool = true,
        evictsDeletedOr404MediaImmediately: Bool = true
    ) {
        self.id = id
        self.memoryLimitMB = memoryLimitMB
        self.diskLimitMB = diskLimitMB
        self.purgesOnMemoryWarning = purgesOnMemoryWarning
        self.evictsDeletedOr404MediaImmediately = evictsDeletedOr404MediaImmediately
    }

    public var isCompliant: Bool {
        (1...150).contains(memoryLimitMB)
            && (1...500).contains(diskLimitMB)
            && purgesOnMemoryWarning
            && evictsDeletedOr404MediaImmediately
    }
}

/// Audits image and video memory/disk cache budgets across the canonical cache pools.
public struct ImageAndVideoDiskCacheBudgetAudit: Sendable, Equatable {
    public static let canonicalPolicies: [MediaCacheBudgetPolicy] = [
        .init(
            id: "square-post-media-cache",
            memoryLimitMB: 64,
            diskLimitMB: 250,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: true
        ),
        .init(
            id: "roam-map-tile-and-poi-cache",
            memoryLimitMB: 48,
            diskLimitMB: 180,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: true
        ),
        .init(
            id: "avatar-and-stamp-asset-cache",
            memoryLimitMB: 32,
            diskLimitMB: 64,
            purgesOnMemoryWarning: true,
            evictsDeletedOr404MediaImmediately: true
        )
    ]

    public init() {}

    public static func evaluate(
        policies: [MediaCacheBudgetPolicy] = canonicalPolicies
    ) -> (totalPools: Int, compliantPools: Int, isCacheBudgetReady: Bool) {
        let total = policies.count
        let compliant = policies.filter(\.isCompliant).count
        let ready = total > 0 && compliant == total
        return (totalPools: total, compliantPools: compliant, isCacheBudgetReady: ready)
    }
}
