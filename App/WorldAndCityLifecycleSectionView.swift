import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained pillar row representing one of the 3 world & city lifecycle pillars:
/// - `G-W05.5`: Environment branch snapshot isolation,
/// - `H-W19`: Private-home return & single-use proof restore,
/// - `H-W20`: Resident CITY action contract & ordered delta stream coordinator.
public struct WorldCityLifecyclePillarRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case environmentBranchSnapshotIsolation = "G_W05_5_ENVIRONMENT_BRANCH_ISOLATION"
        case privateHomeReturnRestore = "H_W19_PRIVATE_HOME_RETURN_RESTORE"
        case cityActionAndDeltaStream = "H_W20_CITY_ACTION_AND_DELTA_STREAM"
    }

    public let id: String
    public let kind: PillarKind
    public let code: String
    public let title: String
    public let summary: String
    public let statusBadge: String
    public let isVerified: Bool

    public init(
        id: String,
        kind: PillarKind,
        code: String,
        title: String,
        summary: String,
        statusBadge: String = "VERIFIED",
        isVerified: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.code = code
        self.title = title
        self.summary = summary
        self.statusBadge = statusBadge
        self.isVerified = isVerified
    }

    public static let defaultRows: [WorldCityLifecyclePillarRow] = [
        WorldCityLifecyclePillarRow(
            id: "g-w05-5",
            kind: .environmentBranchSnapshotIsolation,
            code: "G-W05.5",
            title: "G-W05.5 — Environment Branch Snapshot Isolation",
            summary: "Pins run and world projections to their exact environment branch revision and blocks cross-branch state bleed."
        ),
        WorldCityLifecyclePillarRow(
            id: "h-w19",
            kind: .privateHomeReturnRestore,
            code: "H-W19",
            title: "H-W19 — Private-Home Return Preflight & Resource Restore",
            summary: "Enforces explicit GLOBAL/RUN/THEME resource scope (never all games), redacted home point, and server-max receipt validation."
        ),
        WorldCityLifecyclePillarRow(
            id: "h-w20",
            kind: .cityActionAndDeltaStream,
            code: "H-W20",
            title: "H-W20 — Resident CITY Action & Ordered Delta Coordinator",
            summary: "Enforces OPEN-only board gate, explicit self-payer quote consent, single in-flight exact-retry fence, and gap-triggered snapshot reload."
        ),
    ]
}

/// Self-contained snapshot backing `WorldAndCityLifecycleSectionView`.
public struct WorldAndCityLifecycleSnapshot: Equatable, CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public let environmentBranchID: String
    public let snapshotPinnedRevision: Int64
    public let crossBranchLeakageDetected: Bool
    public let homeReturnScopeLabel: String
    public let homeReturnRetryableNow: Bool
    public let cityBoardLifecycleCode: String
    public let cityDeltaSequence: Int64
    public let cityNeedsSnapshotReload: Bool
    public let citySingleInFlightLocked: Bool
    public let pillars: [WorldCityLifecyclePillarRow]

    public init(
        environmentBranchID: String = "env-branch-main-v1",
        snapshotPinnedRevision: Int64 = 12,
        crossBranchLeakageDetected: Bool = false,
        homeReturnScopeLabel: String = "GLOBAL:stamina",
        homeReturnRetryableNow: Bool = false,
        cityBoardLifecycleCode: String = "OPEN",
        cityDeltaSequence: Int64 = 24,
        cityNeedsSnapshotReload: Bool = false,
        citySingleInFlightLocked: Bool = false,
        pillars: [WorldCityLifecyclePillarRow] = WorldCityLifecyclePillarRow.defaultRows
    ) {
        self.environmentBranchID = environmentBranchID
        self.snapshotPinnedRevision = snapshotPinnedRevision
        self.crossBranchLeakageDetected = crossBranchLeakageDetected
        self.homeReturnScopeLabel = homeReturnScopeLabel
        self.homeReturnRetryableNow = homeReturnRetryableNow
        self.cityBoardLifecycleCode = cityBoardLifecycleCode
        self.cityDeltaSequence = cityDeltaSequence
        self.cityNeedsSnapshotReload = cityNeedsSnapshotReload
        self.citySingleInFlightLocked = citySingleInFlightLocked
        self.pillars = pillars
    }

    public static let standard = WorldAndCityLifecycleSnapshot()

    public var verifiedPillarCount: Int {
        pillars.filter(\.isVerified).count
    }

    public var allPillarsVerified: Bool {
        pillars.count == 3 && verifiedPillarCount == 3 && !crossBranchLeakageDetected
    }

    public var cityAcceptsNewActions: Bool {
        cityBoardLifecycleCode == "OPEN" && !cityNeedsSnapshotReload && !citySingleInFlightLocked
    }

    public var description: String {
        "WorldAndCityLifecycleSnapshot[redacted]"
    }

    public var debugDescription: String {
        description
    }
}

/// SwiftUI section view rendering the 3 world & city lifecycle pillars (`G-W05.5`, `H-W19`, `H-W20`)
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct WorldAndCityLifecycleSectionView: View {
    public let snapshot: WorldAndCityLifecycleSnapshot

    public init(snapshot: WorldAndCityLifecycleSnapshot = .standard) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            pillarsSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(snapshot.environmentBranchID) (rev \(snapshot.snapshotPinnedRevision))")
            } label: {
                Text(verbatim: "Environment Branch Pin (G-W05.5)")
            }
            .accessibilityIdentifier("worldCityLifecycle.summary.branchIsolation")

            LabeledContent {
                Text(verbatim: "\(snapshot.homeReturnScopeLabel) • Retryable: \(snapshot.homeReturnRetryableNow ? "Yes" : "No")")
            } label: {
                Text(verbatim: "Home Return Scope (H-W19)")
            }
            .accessibilityIdentifier("worldCityLifecycle.summary.homeRestore")

            LabeledContent {
                Text(verbatim: "\(snapshot.cityBoardLifecycleCode) • seq \(snapshot.cityDeltaSequence) • Ready: \(snapshot.cityAcceptsNewActions ? "Yes" : "No")")
            } label: {
                Text(verbatim: "City Action & Delta State (H-W20)")
            }
            .accessibilityIdentifier("worldCityLifecycle.summary.cityCoordinator")

            LabeledContent {
                Text(verbatim: "\(snapshot.verifiedPillarCount)/\(snapshot.pillars.count) Pillars Verified")
            } label: {
                Text(verbatim: "Lifecycle Verification Status")
            }
            .accessibilityIdentifier("worldCityLifecycle.summary.verifiedCount")
        } header: {
            Text(verbatim: "World, Home Restore & City Lifecycle (G-W05.5 / H-W19 / H-W20)")
        } footer: {
            Text(verbatim: "Private-home location values remain redacted and never cross into CITY or world projections.")
                .accessibilityIdentifier("worldCityLifecycle.summary.footer")
        }
    }

    private var pillarsSection: some View {
        Section {
            ForEach(snapshot.pillars) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: row.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: row.statusBadge)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("worldCityLifecycle.pillar.badge.\(row.id)")
                    }
                    Text(verbatim: row.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("worldCityLifecycle.pillar.\(row.id)")
            }
        } header: {
            Text(verbatim: "World & City Lifecycle Pillars")
        }
    }
}
