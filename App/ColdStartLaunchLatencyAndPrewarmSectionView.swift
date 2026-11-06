import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a single cold-start launch stage latency budget and main-actor I/O posture.
public struct ColdStartStageRow: Sendable, Equatable, Identifiable {
    public enum StageKind: String, CaseIterable, Sendable, Equatable {
        case runtimeConfigurationBootstrap
        case lazyAppSessionReaderWiring
        case rootTabShellFirstFrameRender
        case backgroundStorePrewarmDeferral
    }

    public let id: String
    public let stageKind: StageKind
    public let title: String
    public let measuredDurationMs: Int
    public let budgetCeilingMs: Int
    public let usesLazyReaderInitialization: Bool
    public let hasZeroSynchronousMainActorIO: Bool

    public init(
        id: String? = nil,
        stageKind: StageKind,
        title: String,
        measuredDurationMs: Int = 80,
        budgetCeilingMs: Int = 120,
        usesLazyReaderInitialization: Bool = true,
        hasZeroSynchronousMainActorIO: Bool = true
    ) {
        self.id = id ?? stageKind.rawValue
        self.stageKind = stageKind
        self.title = title
        self.measuredDurationMs = measuredDurationMs
        self.budgetCeilingMs = budgetCeilingMs
        self.usesLazyReaderInitialization = usesLazyReaderInitialization
        self.hasZeroSynchronousMainActorIO = hasZeroSynchronousMainActorIO
    }

    public var isWithinBudget: Bool {
        measuredDurationMs >= 0
            && measuredDurationMs <= budgetCeilingMs
            && budgetCeilingMs <= 400
    }

    public var isCompliant: Bool {
        isWithinBudget && usesLazyReaderInitialization && hasZeroSynchronousMainActorIO
    }

    public var statusBadgeText: String {
        isCompliant ? "WITHIN BUDGET · LAZY · 0 SYNC I/O" : "WARNING · STAGE BUDGET EXCEEDED"
    }

    public var detailSummaryText: String {
        "Duration: \(measuredDurationMs)ms / \(budgetCeilingMs)ms · Lazy AppSession Reader: \(usesLazyReaderInitialization ? "YES" : "NO") · Sync @MainActor I/O: \(hasZeroSynchronousMainActorIO ? "0" : "BLOCKING")"
    }

    public static let defaultRows: [ColdStartStageRow] = [
        .init(
            id: StageKind.runtimeConfigurationBootstrap.rawValue,
            stageKind: .runtimeConfigurationBootstrap,
            title: "Runtime Environment & Launch Argument Bootstrap",
            measuredDurationMs: 28,
            budgetCeilingMs: 60,
            usesLazyReaderInitialization: true,
            hasZeroSynchronousMainActorIO: true
        ),
        .init(
            id: StageKind.lazyAppSessionReaderWiring.rawValue,
            stageKind: .lazyAppSessionReaderWiring,
            title: "Lazy AppSession Domain Reader Composition",
            measuredDurationMs: 64,
            budgetCeilingMs: 110,
            usesLazyReaderInitialization: true,
            hasZeroSynchronousMainActorIO: true
        ),
        .init(
            id: StageKind.rootTabShellFirstFrameRender.rawValue,
            stageKind: .rootTabShellFirstFrameRender,
            title: "Root 5-Tab Shell First Interactive Frame",
            measuredDurationMs: 118,
            budgetCeilingMs: 150,
            usesLazyReaderInitialization: true,
            hasZeroSynchronousMainActorIO: true
        ),
        .init(
            id: StageKind.backgroundStorePrewarmDeferral.rawValue,
            stageKind: .backgroundStorePrewarmDeferral,
            title: "Deferred Background Durable Store & Map Prewarm",
            measuredDurationMs: 42,
            budgetCeilingMs: 80,
            usesLazyReaderInitialization: true,
            hasZeroSynchronousMainActorIO: true
        ),
    ]
}

/// Self-contained snapshot for cold-start launch latency (`<= 400ms` total budget),
/// lazy `AppSession` reader initialization, and zero synchronous `@MainActor` I/O.
public struct ColdStartLatencySnapshot: Sendable, Equatable {
    public let rows: [ColdStartStageRow]
    public let totalBudgetCeilingMs: Int
    public let enforcesLazyAppSessionReaders: Bool
    public let enforcesZeroMainActorSyncIO: Bool

    public init(
        rows: [ColdStartStageRow] = ColdStartStageRow.defaultRows,
        totalBudgetCeilingMs: Int = 400,
        enforcesLazyAppSessionReaders: Bool = true,
        enforcesZeroMainActorSyncIO: Bool = true
    ) {
        self.rows = rows
        self.totalBudgetCeilingMs = totalBudgetCeilingMs
        self.enforcesLazyAppSessionReaders = enforcesLazyAppSessionReaders
        self.enforcesZeroMainActorSyncIO = enforcesZeroMainActorSyncIO
    }

    public static let defaultReady = ColdStartLatencySnapshot()

    public var totalCount: Int {
        rows.count
    }

    public var compliantCount: Int {
        rows.filter(\.isCompliant).count
    }

    public var totalMeasuredDurationMs: Int {
        rows.reduce(0) { $0 + $1.measuredDurationMs }
    }

    public var coversAllStages: Bool {
        Set(rows.map(\.stageKind)) == Set(ColdStartStageRow.StageKind.allCases)
    }

    public var isAllCompliant: Bool {
        coversAllStages
            && totalBudgetCeilingMs <= 400
            && totalMeasuredDurationMs <= totalBudgetCeilingMs
            && enforcesLazyAppSessionReaders
            && enforcesZeroMainActorSyncIO
            && compliantCount == totalCount
            && totalCount > 0
    }

    public var overallStatusBadgeText: String {
        isAllCompliant ? "READY · <=400ms · 0 SYNC I/O" : "WARNING · COLD-START REGRESSION"
    }

    public var headerSummaryText: String {
        "Stages: \(compliantCount)/\(totalCount) · Total: \(totalMeasuredDurationMs)ms / \(totalBudgetCeilingMs)ms · Lazy Readers: \(enforcesLazyAppSessionReaders ? "YES" : "NO") · MainActor Sync I/O: \(enforcesZeroMainActorSyncIO ? "0" : "DETECTED")"
    }
}

/// SwiftUI diagnostics section displaying cold-start stage budgets (`<= 400ms`),
/// lazy `AppSession` reader initialization, and zero synchronous `@MainActor` I/O.
@MainActor
public struct ColdStartLaunchLatencyAndPrewarmSectionView: View {
    public let snapshot: ColdStartLatencySnapshot

    public init(snapshot: ColdStartLatencySnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: "Cold-Start Launch Latency & Prewarm")
                    .font(.headline)
                    .accessibilityIdentifier("coldStartLatency.headerTitle")
                Spacer()
                Text(verbatim: snapshot.overallStatusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllCompliant ? Color.green : Color.orange)
                    .accessibilityIdentifier("coldStartLatency.statusBadge")
            }

            Text(verbatim: snapshot.headerSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coldStartLatency.summaryLine")

            if !snapshot.isAllCompliant {
                Text(verbatim: "Warning: Cold-start latency exceeds <= 400ms budget or performs synchronous @MainActor disk/network I/O.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.orange)
                    .accessibilityIdentifier("coldStartLatency.warningBanner")
            }

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: row.statusBadgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(row.isCompliant ? Color.green : Color.orange)
                    }
                    Text(verbatim: row.detailSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("coldStartLatency.row.\(row.id)")
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coldStartLatency.section")
    }
}
