import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation item for one of the 15 master release & parity sign-off pillars.
public struct MasterSignoffPillarItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let index: Int
    public let title: String
    public let coverageSummary: String
    public let isVerified: Bool
    public let isFailClosed: Bool

    public init(
        id: String,
        index: Int,
        title: String,
        coverageSummary: String,
        isVerified: Bool = true,
        isFailClosed: Bool = true
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.coverageSummary = coverageSummary
        self.isVerified = isVerified
        self.isFailClosed = isFailClosed
    }

    public var statusBadgeText: String {
        (isVerified && isFailClosed) ? "VERIFIED • FAIL-CLOSED" : "PENDING REVIEW"
    }
}

/// Self-contained presentation snapshot for the 15-pillar Master Release & Parity Sign-off Dashboard.
public struct MasterReleaseSignoffDashboardSnapshot: Equatable, Sendable {
    public let pillars: [MasterSignoffPillarItem]
    public let verifiedMiniProgramPages: Int
    public let totalMiniProgramPages: Int
    public let verifiedWave2Scopes: Int
    public let totalWave2Scopes: Int
    public let verifiedWave3Lanes: Int
    public let totalWave3Lanes: Int
    public let verifiedReformPackages: Int
    public let totalReformPackages: Int
    public let verifiedMapVisualItems: Int
    public let totalMapVisualItems: Int
    public let allHighRiskSwitchesFailClosed: Bool

    public init(
        pillars: [MasterSignoffPillarItem] = Self.defaultPillars,
        verifiedMiniProgramPages: Int = 99,
        totalMiniProgramPages: Int = 99,
        verifiedWave2Scopes: Int = 21,
        totalWave2Scopes: Int = 21,
        verifiedWave3Lanes: Int = 13,
        totalWave3Lanes: Int = 13,
        verifiedReformPackages: Int = 19,
        totalReformPackages: Int = 19,
        verifiedMapVisualItems: Int = 41,
        totalMapVisualItems: Int = 41,
        allHighRiskSwitchesFailClosed: Bool = true
    ) {
        self.pillars = pillars
        self.verifiedMiniProgramPages = verifiedMiniProgramPages
        self.totalMiniProgramPages = totalMiniProgramPages
        self.verifiedWave2Scopes = verifiedWave2Scopes
        self.totalWave2Scopes = totalWave2Scopes
        self.verifiedWave3Lanes = verifiedWave3Lanes
        self.totalWave3Lanes = totalWave3Lanes
        self.verifiedReformPackages = verifiedReformPackages
        self.totalReformPackages = totalReformPackages
        self.verifiedMapVisualItems = verifiedMapVisualItems
        self.totalMapVisualItems = totalMapVisualItems
        self.allHighRiskSwitchesFailClosed = allHighRiskSwitchesFailClosed
    }

    public static let defaultPillars: [MasterSignoffPillarItem] = [
        MasterSignoffPillarItem(
            id: "pillar-01-xcx-b",
            index: 1,
            title: "Wave-1 B: TabBar, Home, Discover & Roam Entry Parity",
            coverageSummary: "Public config, home feed, search & roam discovery aligned"
        ),
        MasterSignoffPillarItem(
            id: "pillar-02-xcx-c",
            index: 2,
            title: "Wave-1 C: Play, Task, Scan, Audio & Poster Parity",
            coverageSummary: "GCJ-02 arrival, QR scan, audio lifecycle & poster share aligned"
        ),
        MasterSignoffPillarItem(
            id: "pillar-03-xcx-d",
            index: 3,
            title: "Wave-1 D: Square, Topic, IM Inbox & Social Parity",
            coverageSummary: "Square feed/workspace, topic detail & IM inbox tabs aligned"
        ),
        MasterSignoffPillarItem(
            id: "pillar-04-xcx-e",
            index: 4,
            title: "Wave-1 E: Account, Merchant, Club & Creator Parity",
            coverageSummary: "Profile, merchant 4-step apply, club access & creator shelf aligned"
        ),
        MasterSignoffPillarItem(
            id: "pillar-05-reform-f",
            index: 5,
            title: "Wave-1 F: World Reform W02–W10 Core Contracts",
            coverageSummary: "Publish media, run authority CAS, rewards, NPC AI & in-store game"
        ),
        MasterSignoffPillarItem(
            id: "pillar-06-reform-g",
            index: 6,
            title: "Wave-1 G: World Reform W11–W20 & U01–U08 Contracts",
            coverageSummary: "Location share, side quests, env branch, qmod & home return restore"
        ),
        MasterSignoffPillarItem(
            id: "pillar-07-map-h",
            index: 7,
            title: "Wave-1 H: Map Visual Foundation MV01–MV41",
            coverageSummary: "41/41 map visual tokens, coordinate observation & personal fog ledger"
        ),
        MasterSignoffPillarItem(
            id: "pillar-08-wave2-auth-wallet",
            index: 8,
            title: "Wave-2 w2-01..w2-07: Auth, Profile, Wallet & Growth",
            coverageSummary: "CN/US session isolation, fail-closed wallet/withdrawal & growth center"
        ),
        MasterSignoffPillarItem(
            id: "pillar-09-wave2-roam-play",
            index: 9,
            title: "Wave-2 w2-08..w2-14: Roam, Play Runtime & Team",
            coverageSummary: "Roam private tools, play runtime status/auxiliary binding & teams"
        ),
        MasterSignoffPillarItem(
            id: "pillar-10-wave2-merchant-club",
            index: 10,
            title: "Wave-2 w2-15..w2-21: Square, Merchant, Club & Editor",
            coverageSummary: "Merchant store parity, club workspace, official events & route editor"
        ),
        MasterSignoffPillarItem(
            id: "pillar-11-wave3-i00-i05",
            index: 11,
            title: "Wave-3 I00–I05: Session Admission, GPS, Journal & Privacy",
            coverageSummary: "I00 role gate, I01 GPS 80m hint, I02 game journal, I04 ledger & I05 revocation"
        ),
        MasterSignoffPillarItem(
            id: "pillar-12-wave3-i06-bk",
            index: 12,
            title: "Wave-3 I06–I11 & BK: Audio, NPC Delete, Schedule & Signposts",
            coverageSummary: "I06 audio, I07 rank, I08 NPC delete OFF, I09 schedule, I10 signposts, I11 stamps & BK"
        ),
        MasterSignoffPillarItem(
            id: "pillar-13-wave4-bridges",
            index: 13,
            title: "Wave-4 Host Bridges & Coordinators",
            coverageSummary: "All 15 Core host bridges & coordinators wired with zero live I/O"
        ),
        MasterSignoffPillarItem(
            id: "pillar-14-wave5-sections",
            index: 14,
            title: "Wave-5 SwiftUI Host Section Views",
            coverageSummary: "Deterministic verbatim SwiftUI host sections & accessibility hooks"
        ),
        MasterSignoffPillarItem(
            id: "pillar-15-release-preflight",
            index: 15,
            title: "Release Pre-Flight, Signing & UI Readiness Contract",
            coverageSummary: "Base.xcconfig safe defaults, legacy IP rejection & UI readiness anchors"
        )
    ]

    public static let verifiedDefault = MasterReleaseSignoffDashboardSnapshot()

    public var verifiedPillarCount: Int {
        pillars.filter { $0.isVerified && $0.isFailClosed }.count
    }

    public var isReadyForSignoff: Bool {
        pillars.count == 15 &&
        verifiedPillarCount == 15 &&
        verifiedMiniProgramPages == totalMiniProgramPages &&
        verifiedWave2Scopes == totalWave2Scopes &&
        verifiedWave3Lanes == totalWave3Lanes &&
        verifiedReformPackages == totalReformPackages &&
        verifiedMapVisualItems == totalMapVisualItems &&
        allHighRiskSwitchesFailClosed
    }
}

/// Master Release & Parity Sign-off Dashboard SwiftUI View (`Batch 10 — Lane 105`).
@MainActor
public struct MasterReleaseSignoffDashboardView: View {
    public let snapshot: MasterReleaseSignoffDashboardSnapshot

    public init(snapshot: MasterReleaseSignoffDashboardSnapshot = .verifiedDefault) {
        self.snapshot = snapshot
    }

    public var pillarsBadgeText: String {
        "\(snapshot.verifiedPillarCount)/\(snapshot.pillars.count) Pillars Verified"
    }

    public var miniProgramPagesMetricText: String {
        "\(snapshot.verifiedMiniProgramPages)/\(snapshot.totalMiniProgramPages) Mini-Program Pages"
    }

    public var wave2ScopesMetricText: String {
        "\(snapshot.verifiedWave2Scopes)/\(snapshot.totalWave2Scopes) Wave-2 Scopes"
    }

    public var wave3LanesMetricText: String {
        "\(snapshot.verifiedWave3Lanes)/\(snapshot.totalWave3Lanes) Wave-3 Lanes"
    }

    public var reformPackagesMetricText: String {
        "\(snapshot.verifiedReformPackages)/\(snapshot.totalReformPackages) Reform Packages"
    }

    public var mapVisualMetricText: String {
        "\(snapshot.verifiedMapVisualItems)/\(snapshot.totalMapVisualItems) Map Visual Items"
    }

    public var highRiskSwitchesBannerText: String {
        snapshot.allHighRiskSwitchesFailClosed
            ? "All High-Risk Switches Fail-Closed"
            : "High-Risk Switches: REVIEW REQUIRED"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Master Release & Parity Sign-off Dashboard")
                    .font(.headline)
                    .accessibilityIdentifier("masterReleaseDashboard.title")
                Spacer()
                Text(verbatim: pillarsBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isReadyForSignoff ? Color.green : Color.orange)
                    .accessibilityIdentifier("masterReleaseDashboard.pillarsBadge")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(verbatim: miniProgramPagesMetricText)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("masterReleaseDashboard.miniProgramPagesMetric")
                    Text(verbatim: wave2ScopesMetricText)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("masterReleaseDashboard.wave2ScopesMetric")
                    Text(verbatim: wave3LanesMetricText)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("masterReleaseDashboard.wave3LanesMetric")
                }
                HStack(spacing: 12) {
                    Text(verbatim: reformPackagesMetricText)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("masterReleaseDashboard.reformPackagesMetric")
                    Text(verbatim: mapVisualMetricText)
                        .font(.caption.monospacedDigit())
                        .accessibilityIdentifier("masterReleaseDashboard.mapVisualMetric")
                }
            }
            .foregroundStyle(.secondary)

            Text(verbatim: highRiskSwitchesBannerText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(snapshot.allHighRiskSwitchesFailClosed ? Color.green : Color.red)
                .accessibilityIdentifier("masterReleaseDashboard.highRiskSwitchesBanner")

            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.pillars) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "#\(item.index) \(item.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: item.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle((item.isVerified && item.isFailClosed) ? Color.green : Color.orange)
                        }
                        Text(verbatim: item.coverageSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("masterReleaseDashboard.pillarList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("masterReleaseDashboard.section")
    }
}
