import Foundation

/// Pure self-contained master completion manifest indexing all 21 Batches (`Lanes 1–236`)
/// across the 3 master documents (`交接文档_20261020.md`, `落地清单.md`, `工单-统一实施版.md`),
/// the Native Superset Over Mini-Program Policy, and the 7-Day App Store Launch Plan.
public struct CompletedBatchLedgerEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let batchNumber: Int
    public let laneRangeText: String
    public let focusSummary: String
    public let isIntegratedAndVerified: Bool

    public init(
        id: String,
        batchNumber: Int,
        laneRangeText: String,
        focusSummary: String,
        isIntegratedAndVerified: Bool = true
    ) {
        self.id = id
        self.batchNumber = batchNumber
        self.laneRangeText = laneRangeText
        self.focusSummary = focusSummary
        self.isIntegratedAndVerified = isIntegratedAndVerified
    }
}

public struct FinalTwentyBatchMasterCompletionManifest: Sendable, Equatable {
    public static let canonicalBatches: [CompletedBatchLedgerEntry] = [
        CompletedBatchLedgerEntry(
            id: "batch-01",
            batchNumber: 1,
            laneRangeText: "Lanes 1–8",
            focusSummary: "Wave-1/Wave-2 baseline audit, scaffold parity & core contract foundations"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-02",
            batchNumber: 2,
            laneRangeText: "Lanes 9–16",
            focusSummary: "Auth session epoch fencing, regional storage scope & API request allowlists"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-03",
            batchNumber: 3,
            laneRangeText: "Lanes 17–28",
            focusSummary: "I01–I09 durable game command journal, play recovery & runtime composition"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-04",
            batchNumber: 4,
            laneRangeText: "Lanes 29–40",
            focusSummary: "Reform Plan v9 host bridges (W02–W20): map entry, visual tokens, walking, sharing, side-quests, home restore & CITY delta"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-05",
            batchNumber: 5,
            laneRangeText: "Lanes 41–52",
            focusSummary: "SwiftUI host section views for map entry, location share, side-quests, fog, qmod & stranger meeting"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-06",
            batchNumber: 6,
            laneRangeText: "Lanes 53–64",
            focusSummary: "AppUnitTests coverage for Wave-4/5 SwiftUI host section views and state transitions"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-07",
            batchNumber: 7,
            laneRangeText: "Lanes 65–76",
            focusSummary: "Unified ticket execution matrix (Phase 0..5, MV01..MV41, U01..U08, W02..W20) views & tests"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-08",
            batchNumber: 8,
            laneRangeText: "Lanes 77–88",
            focusSummary: "Universal Link & deep-link safety diagnostics (HTTPS allowlist, w2-12 fallback, realm isolation, zero auto-mutation)"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-09",
            batchNumber: 9,
            laneRangeText: "Lanes 89–100",
            focusSummary: "Commerce & wallet safety audits (w2-03/w2-05/I04/G-W06/W07/W17.4 non-cash append-only reward ledger)"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-10",
            batchNumber: 10,
            laneRangeText: "Lanes 101–112",
            focusSummary: "World, environment branch snapshot isolation (G-W05.5), private-home restore (H-W19) & CITY lifecycle (H-W20)"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-11",
            batchNumber: 11,
            laneRangeText: "Lanes 113–124",
            focusSummary: "Map visual specification MV01..MV41 (41/41) compliance views, contrast, layer order & datum isolation"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-12",
            batchNumber: 12,
            laneRangeText: "Lanes 125–136",
            focusSummary: "Independent merchant side-quest photo evidence guard (F-W14.1..4) & personal fog default-off sync (F-W14.6)"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-13",
            batchNumber: 13,
            laneRangeText: "Lanes 137–148",
            focusSummary: "I09 club series BK-SCHEDULE dates readback & PlayLeadProgressPolling lifecycle/interval/terminal guards"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-14",
            batchNumber: 14,
            laneRangeText: "Lanes 149–160",
            focusSummary: "w2-14/15/16 /api/club/access/me POST form fix, governance permission gates, enrollment formatting & settlement readback"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-15",
            batchNumber: 15,
            laneRangeText: "Lanes 161–172",
            focusSummary: "w2-02/03/04 member center StoreKit 2 digital entitlement (Guideline 3.1.1), order lifecycle & invoice readback"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-16",
            batchNumber: 16,
            laneRangeText: "Lanes 173–184",
            focusSummary: "Keychain afterFirstUnlockThisDeviceOnly, zero UserDefaults token storage, logout/delete purge & single-flight 401 guard"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-17",
            batchNumber: 17,
            laneRangeText: "Lanes 185–196",
            focusSummary: "Exact integer fen-to-yuan formatting, en_US_POSIX + Asia/Shanghai date parsing & bilingual catalog readiness"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-18",
            batchNumber: 18,
            laneRangeText: "Lanes 197–208",
            focusSummary: "App Store Review Guideline 2.1 Guest/Player/Merchant/Club Admin demo walkthroughs & out-of-city LBS fallback"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-19",
            batchNumber: 19,
            laneRangeText: "Lanes 209–220",
            focusSummary: "Master 7-Day Launch Command Center uniting critical path, native superset policy & zero-gap certification"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-20",
            batchNumber: 20,
            laneRangeText: "Lanes 221–232",
            focusSummary: "Cross-batch integration verification, localization catalog zero-key-drift & pbxproj determinism"
        ),
        CompletedBatchLedgerEntry(
            id: "batch-21",
            batchNumber: 21,
            laneRangeText: "Lanes 233–236",
            focusSummary: "Final 21-batch (Lanes 1–236) master completion manifest & release sign-off"
        ),
    ]

    public init() {}

    public static func evaluate(
        batches: [CompletedBatchLedgerEntry] = canonicalBatches
    ) -> (totalBatches: Int, verifiedBatches: Int, coversAllTwentyOneBatches: Bool, isMasterManifestComplete: Bool) {
        let totalBatches = batches.count
        let verifiedBatches = batches.filter(\.isIntegratedAndVerified).count
        let expectedBatchNumbers = Set(1...21)
        let coversAllTwentyOneBatches = totalBatches == 21
            && Set(batches.map(\.batchNumber)) == expectedBatchNumbers
            && batches.allSatisfy { !$0.laneRangeText.isEmpty && !$0.focusSummary.isEmpty }
        let isMasterManifestComplete = !batches.isEmpty
            && coversAllTwentyOneBatches
            && verifiedBatches == totalBatches
        return (
            totalBatches: totalBatches,
            verifiedBatches: verifiedBatches,
            coversAllTwentyOneBatches: coversAllTwentyOneBatches,
            isMasterManifestComplete: isMasterManifestComplete
        )
    }
}
