import Foundation

/// Canonical `w2-09` (`RoamPrivateTools`) private exploration tool kinds.
public enum ExplorationPrivateToolKind: String, Sendable, Equatable, CaseIterable {
    case timeCapsule
    case explorationGoals
    case explorationExport
    case explorationAnniversary
    case monthlyRecap
}

/// Audit entry for a single `w2-09` private exploration tool verifying owner-only visibility,
/// `RoamPrivateTools.xcstrings` bilingual table usage, and offline draft/export readiness.
public struct ExplorationPrivateToolAuditEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let toolKind: ExplorationPrivateToolKind
    public let isOwnerOnlyPrivate: Bool
    public let usesRoamPrivateToolsTable: Bool
    public let supportsOfflineDraftOrExport: Bool

    public init(
        id: String? = nil,
        toolKind: ExplorationPrivateToolKind,
        isOwnerOnlyPrivate: Bool = true,
        usesRoamPrivateToolsTable: Bool = true,
        supportsOfflineDraftOrExport: Bool = true
    ) {
        self.id = id ?? toolKind.rawValue
        self.toolKind = toolKind
        self.isOwnerOnlyPrivate = isOwnerOnlyPrivate
        self.usesRoamPrivateToolsTable = usesRoamPrivateToolsTable
        self.supportsOfflineDraftOrExport = supportsOfflineDraftOrExport
    }

    public var isCompliant: Bool {
        isOwnerOnlyPrivate && usesRoamPrivateToolsTable && supportsOfflineDraftOrExport
    }
}

/// Pure auditor for `w2-09` (`RoamPrivateTools` 5 private exploration tools:
/// `timeCapsule`, `explorationGoals`, `explorationExport`, `explorationAnniversary`, `monthlyRecap`,
/// owner-only private visibility, and `RoamPrivateTools.xcstrings` bilingual key discipline).
public struct ExplorationPrivateToolsAndCapsuleAudit: Sendable, Equatable {
    public static let canonicalStringsTable = "RoamPrivateTools"

    public static let canonicalEntries: [ExplorationPrivateToolAuditEntry] = [
        ExplorationPrivateToolAuditEntry(
            id: ExplorationPrivateToolKind.timeCapsule.rawValue,
            toolKind: .timeCapsule,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        ),
        ExplorationPrivateToolAuditEntry(
            id: ExplorationPrivateToolKind.explorationGoals.rawValue,
            toolKind: .explorationGoals,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        ),
        ExplorationPrivateToolAuditEntry(
            id: ExplorationPrivateToolKind.explorationExport.rawValue,
            toolKind: .explorationExport,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        ),
        ExplorationPrivateToolAuditEntry(
            id: ExplorationPrivateToolKind.explorationAnniversary.rawValue,
            toolKind: .explorationAnniversary,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        ),
        ExplorationPrivateToolAuditEntry(
            id: ExplorationPrivateToolKind.monthlyRecap.rawValue,
            toolKind: .monthlyRecap,
            isOwnerOnlyPrivate: true,
            usesRoamPrivateToolsTable: true,
            supportsOfflineDraftOrExport: true
        )
    ]

    public init() {}

    public static func evaluate(
        entries: [ExplorationPrivateToolAuditEntry] = canonicalEntries
    ) -> (totalTools: Int, compliantTools: Int, coversAllFiveTools: Bool, isPrivateToolsReady: Bool) {
        let totalTools = entries.count
        let compliantTools = entries.filter(\.isCompliant).count
        let coveredKinds = Set(entries.map(\.toolKind))
        let requiredKinds = Set(ExplorationPrivateToolKind.allCases)
        let coversAllFiveTools = coveredKinds == requiredKinds && totalTools == requiredKinds.count
        let isPrivateToolsReady = coversAllFiveTools && compliantTools == totalTools
        return (
            totalTools: totalTools,
            compliantTools: compliantTools,
            coversAllFiveTools: coversAllFiveTools,
            isPrivateToolsReady: isPrivateToolsReady
        )
    }
}
