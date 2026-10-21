import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained App Store 7-day phased release stage row for `ProductionCanaryRolloutAndPhasedReleaseSectionView`.
public struct PhasedReleaseStageRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let dayNumber: Int
    public let rolloutPercentage: Int
    public let observedCrashFreePercentage: Double
    public let instantRollbackArmed: Bool

    public init(
        id: String? = nil,
        dayNumber: Int,
        rolloutPercentage: Int,
        observedCrashFreePercentage: Double = 99.85,
        instantRollbackArmed: Bool = true
    ) {
        self.id = id ?? "day-\(dayNumber)"
        self.dayNumber = dayNumber
        self.rolloutPercentage = rolloutPercentage
        self.observedCrashFreePercentage = observedCrashFreePercentage
        self.instantRollbackArmed = instantRollbackArmed
    }

    public static let minimumCrashFreeSLA: Double = 99.5

    public var meetsCrashFreeSLA: Bool {
        observedCrashFreePercentage >= Self.minimumCrashFreeSLA
    }

    public var isCompliant: Bool {
        (1...7).contains(dayNumber) &&
            (1...100).contains(rolloutPercentage) &&
            meetsCrashFreeSLA &&
            instantRollbackArmed
    }

    public var rowAccessibilityIdentifier: String {
        "canaryPhasedRelease.stage.\(id)"
    }

    public var statusAccessibilityIdentifier: String {
        "canaryPhasedRelease.status.\(id)"
    }
}

/// Self-contained snapshot covering App Store 7-day phased rollout (`1% -> 100%`),
/// `>= 99.5%` crash-free SLA gate, and instant feature-flag rollback readiness.
public struct CanaryPhasedReleaseSnapshot: Sendable, Equatable {
    public static let canonicalPercentages: [Int] = [1, 2, 5, 10, 20, 50, 100]

    public let stages: [PhasedReleaseStageRow]
    public let minimumCrashFreeSLAPercentage: Double
    public let instantFeatureFlagKillSwitchReady: Bool

    public init(
        stages: [PhasedReleaseStageRow],
        minimumCrashFreeSLAPercentage: Double = PhasedReleaseStageRow.minimumCrashFreeSLA,
        instantFeatureFlagKillSwitchReady: Bool = true
    ) {
        self.stages = stages
        self.minimumCrashFreeSLAPercentage = minimumCrashFreeSLAPercentage
        self.instantFeatureFlagKillSwitchReady = instantFeatureFlagKillSwitchReady
    }

    public var slaBreachedStageIDs: [String] {
        stages
            .filter { $0.observedCrashFreePercentage < minimumCrashFreeSLAPercentage || !$0.instantRollbackArmed }
            .map(\.id)
    }

    public var isAllReady: Bool {
        stages.count == 7 &&
            stages.map(\.rolloutPercentage) == Self.canonicalPercentages &&
            instantFeatureFlagKillSwitchReady &&
            slaBreachedStageIDs.isEmpty &&
            stages.allSatisfy(\.isCompliant)
    }

    public static let defaultReady = CanaryPhasedReleaseSnapshot(
        stages: [
            PhasedReleaseStageRow(dayNumber: 1, rolloutPercentage: 1, observedCrashFreePercentage: 99.92),
            PhasedReleaseStageRow(dayNumber: 2, rolloutPercentage: 2, observedCrashFreePercentage: 99.90),
            PhasedReleaseStageRow(dayNumber: 3, rolloutPercentage: 5, observedCrashFreePercentage: 99.88),
            PhasedReleaseStageRow(dayNumber: 4, rolloutPercentage: 10, observedCrashFreePercentage: 99.86),
            PhasedReleaseStageRow(dayNumber: 5, rolloutPercentage: 20, observedCrashFreePercentage: 99.84),
            PhasedReleaseStageRow(dayNumber: 6, rolloutPercentage: 50, observedCrashFreePercentage: 99.82),
            PhasedReleaseStageRow(dayNumber: 7, rolloutPercentage: 100, observedCrashFreePercentage: 99.80)
        ],
        minimumCrashFreeSLAPercentage: 99.5,
        instantFeatureFlagKillSwitchReady: true
    )

    public static func withCrashFreeSLAViolation(
        onDay dayNumber: Int,
        observedCrashFreePercentage: Double = 98.40
    ) -> CanaryPhasedReleaseSnapshot {
        let updated = defaultReady.stages.map { row in
            guard row.dayNumber == dayNumber else {
                return row
            }
            return PhasedReleaseStageRow(
                id: row.id,
                dayNumber: row.dayNumber,
                rolloutPercentage: row.rolloutPercentage,
                observedCrashFreePercentage: observedCrashFreePercentage,
                instantRollbackArmed: row.instantRollbackArmed
            )
        }
        return CanaryPhasedReleaseSnapshot(
            stages: updated,
            minimumCrashFreeSLAPercentage: defaultReady.minimumCrashFreeSLAPercentage,
            instantFeatureFlagKillSwitchReady: defaultReady.instantFeatureFlagKillSwitchReady
        )
    }
}

@MainActor
public struct ProductionCanaryRolloutAndPhasedReleaseSectionView: View {
    public let snapshot: CanaryPhasedReleaseSnapshot
    public var onSelectStage: ((PhasedReleaseStageRow) -> Void)?

    public init(
        snapshot: CanaryPhasedReleaseSnapshot = .defaultReady,
        onSelectStage: ((PhasedReleaseStageRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectStage = onSelectStage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            slaAndRollbackBanner
            ForEach(snapshot.stages) { stage in
                stageCard(stage)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canaryPhasedRelease.section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.teal)
            Text(verbatim: "Production Canary & 7-Day Phased Release")
                .font(.headline)
                .accessibilityIdentifier("canaryPhasedRelease.header")
            Spacer()
            Text(verbatim: headerBadgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(headerBadgeTint.opacity(0.16))
                )
                .foregroundStyle(headerBadgeTint)
                .accessibilityIdentifier("canaryPhasedRelease.summaryBadge")
        }
    }

    private var slaAndRollbackBanner: some View {
        HStack(spacing: 8) {
            pill(
                text: String(format: "SLA Gate >= %.1f%%", snapshot.minimumCrashFreeSLAPercentage),
                tint: snapshot.slaBreachedStageIDs.isEmpty ? .green : .red
            )
            pill(
                text: snapshot.instantFeatureFlagKillSwitchReady ? "INSTANT ROLLBACK ARMED" : "ROLLBACK UNARMED",
                tint: snapshot.instantFeatureFlagKillSwitchReady ? .blue : .red
            )
            pill(
                text: "Days 1..7 (1% -> 100%)",
                tint: .teal
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canaryPhasedRelease.slaBanner")
    }

    private func stageCard(_ stage: PhasedReleaseStageRow) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "Day \(stage.dayNumber) · \(stage.rolloutPercentage)%")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(verbatim: String(format: "Crash-Free %.2f%%", stage.observedCrashFreePercentage))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(verbatim: stage.isCompliant ? "SLA PASS" : "PAUSE / ROLLBACK")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill((stage.isCompliant ? Color.green : Color.red).opacity(0.16))
                )
                .foregroundStyle(stage.isCompliant ? Color.green : Color.red)
                .accessibilityIdentifier(stage.statusAccessibilityIdentifier)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectStage?(stage)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(stage.rowAccessibilityIdentifier)
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    public var headerBadgeText: String {
        if snapshot.isAllReady {
            return "7-DAY PHASED ROLLOUT READY"
        }
        return "SLA BREACH (\(snapshot.slaBreachedStageIDs.count) STAGE)"
    }

    private var headerBadgeTint: Color {
        snapshot.isAllReady ? .green : .red
    }
}
