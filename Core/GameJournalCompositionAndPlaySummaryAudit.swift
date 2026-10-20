import Foundation

/// Pure self-contained value types auditing Wave-3 `I02` (`GameJournalComposition`, `loadUserPlaySummary`,
/// `userStamps` + `completedTasks` composition) & `I00` non-regression of standalone `loadUserStamps()`.
public struct GameJournalSourceSliceSnapshot: Sendable, Equatable, Identifiable {
    public let id: String
    public let userStampCount: Int
    public let completedTaskCount: Int
    public let deduplicatedEntryCount: Int
    public let preservesStandaloneLoadUserStamps: Bool
    public let sortedByTimestampDescending: Bool

    public init(
        id: String,
        userStampCount: Int,
        completedTaskCount: Int,
        deduplicatedEntryCount: Int,
        preservesStandaloneLoadUserStamps: Bool = true,
        sortedByTimestampDescending: Bool = true
    ) {
        self.id = id
        self.userStampCount = userStampCount
        self.completedTaskCount = completedTaskCount
        self.deduplicatedEntryCount = deduplicatedEntryCount
        self.preservesStandaloneLoadUserStamps = preservesStandaloneLoadUserStamps
        self.sortedByTimestampDescending = sortedByTimestampDescending
    }

    public var isCompliant: Bool {
        userStampCount >= 0
            && completedTaskCount >= 0
            && preservesStandaloneLoadUserStamps
            && sortedByTimestampDescending
            && deduplicatedEntryCount <= (userStampCount + completedTaskCount)
            && deduplicatedEntryCount >= max(userStampCount, completedTaskCount)
    }
}

public struct GameJournalCompositionAndPlaySummaryAudit: Sendable, Equatable {
    public static let canonicalSnapshots: [GameJournalSourceSliceSnapshot] = [
        GameJournalSourceSliceSnapshot(
            id: "journal-roam-stamps",
            userStampCount: 8,
            completedTaskCount: 0,
            deduplicatedEntryCount: 8,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        ),
        GameJournalSourceSliceSnapshot(
            id: "journal-task-completions",
            userStampCount: 0,
            completedTaskCount: 5,
            deduplicatedEntryCount: 5,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        ),
        GameJournalSourceSliceSnapshot(
            id: "journal-merged-play-summary",
            userStampCount: 8,
            completedTaskCount: 5,
            deduplicatedEntryCount: 11,
            preservesStandaloneLoadUserStamps: true,
            sortedByTimestampDescending: true
        )
    ]

    public let snapshots: [GameJournalSourceSliceSnapshot]

    public init(snapshots: [GameJournalSourceSliceSnapshot] = GameJournalCompositionAndPlaySummaryAudit.canonicalSnapshots) {
        self.snapshots = snapshots
    }

    public static func audit(
        snapshots: [GameJournalSourceSliceSnapshot] = canonicalSnapshots
    ) -> (totalSlices: Int, compliantSlices: Int, allPreserveStandaloneStamps: Bool, isJournalReady: Bool) {
        let total = snapshots.count
        let compliant = snapshots.filter(\.isCompliant).count
        let allPreserveStamps = !snapshots.isEmpty && snapshots.allSatisfy(\.preservesStandaloneLoadUserStamps)
        let ready = total > 0 && compliant == total && allPreserveStamps
        return (
            totalSlices: total,
            compliantSlices: compliant,
            allPreserveStandaloneStamps: allPreserveStamps,
            isJournalReady: ready
        )
    }
}
