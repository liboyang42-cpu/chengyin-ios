import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained domain coverage row for the 99-page WeChat mini-program parity matrix.
public struct MiniProgramDomainCoverageRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let domainTitle: String
    public let coveredPageCount: Int
    public let totalPageCount: Int
    public let wave2ScopeIDs: [String]
    public let failClosedWriteGates: [String]

    public init(
        id: String,
        domainTitle: String,
        coveredPageCount: Int,
        totalPageCount: Int,
        wave2ScopeIDs: [String],
        failClosedWriteGates: [String]
    ) {
        self.id = id
        self.domainTitle = domainTitle
        self.coveredPageCount = coveredPageCount
        self.totalPageCount = totalPageCount
        self.wave2ScopeIDs = wave2ScopeIDs
        self.failClosedWriteGates = failClosedWriteGates
    }

    public var isFullyAligned: Bool {
        totalPageCount > 0 && coveredPageCount == totalPageCount
    }

    public var coverageSummaryText: String {
        "\(domainTitle) · \(coveredPageCount)/\(totalPageCount) pages · Scopes: \(wave2ScopeIDs.joined(separator: ", "))"
    }

    public var failClosedGateBadgeText: String {
        "Fail-Closed Gates (\(failClosedWriteGates.count)): \(failClosedWriteGates.joined(separator: ", ")) [OFF]"
    }
}

/// Self-contained Wave-2 scope badge entry (`w2-01` .. `w2-21`).
public struct MiniProgramWave2ScopeBadge: Identifiable, Equatable, Sendable {
    public let id: String
    public let domainID: String
    public let summary: String
    public let isIntegrated: Bool

    public init(id: String, domainID: String, summary: String, isIntegrated: Bool = true) {
        self.id = id
        self.domainID = domainID
        self.summary = summary
        self.isIntegrated = isIntegrated
    }
}

/// Renders the 99-page WeChat mini-program parity alignment matrix across the 4 domains
/// (`Domain B`..`Domain E`), all 21 Wave-2 scopes (`w2-01`..`w2-21`), and fail-closed write
/// gate badges using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct MiniProgram99PageParitySectionView: View {
    public let domainRows: [MiniProgramDomainCoverageRow]
    public let wave2Badges: [MiniProgramWave2ScopeBadge]

    public init(
        domainRows: [MiniProgramDomainCoverageRow] = Self.defaultDomainRows,
        wave2Badges: [MiniProgramWave2ScopeBadge] = Self.defaultWave2Badges
    ) {
        self.domainRows = domainRows
        self.wave2Badges = wave2Badges
    }

    public static let defaultDomainRows: [MiniProgramDomainCoverageRow] = [
        .init(
            id: "domain-B",
            domainTitle: "Domain B: Main/Home/Square/Profile",
            coveredPageCount: 26,
            totalPageCount: 26,
            wave2ScopeIDs: ["w2-01", "w2-02", "w2-03", "w2-07", "w2-11"],
            failClosedWriteGates: ["smsSend=OFF", "squareLivePublish=OFF", "topicLikeWrite=OFF"]
        ),
        .init(
            id: "domain-C",
            domainTitle: "Domain C: Roam/Play/Game",
            coveredPageCount: 24,
            totalPageCount: 24,
            wave2ScopeIDs: ["w2-04", "w2-05", "w2-06", "w2-14"],
            failClosedWriteGates: ["aggregatedQuery=OFF", "sideQuestAccept=OFF", "fogRevealSync=OFF", "runAuthority=OFF"]
        ),
        .init(
            id: "domain-D",
            domainTitle: "Domain D: Social/Team/Club",
            coveredPageCount: 21,
            totalPageCount: 21,
            wave2ScopeIDs: ["w2-08", "w2-09", "w2-10"],
            failClosedWriteGates: ["locationShare=OFF", "friendMultiInvite=OFF", "teamFirstMeeting=OFF", "meetingNFC=OFF"]
        ),
        .init(
            id: "domain-E",
            domainTitle: "Domain E: Merchant/Wallet/Order/Publish",
            coveredPageCount: 28,
            totalPageCount: 28,
            wave2ScopeIDs: ["w2-12", "w2-13", "w2-15", "w2-16", "w2-17", "w2-18", "w2-19", "w2-20", "w2-21"],
            failClosedWriteGates: ["paymentAndCash=OFF", "merchantAuthoringPublish=OFF", "sponsoredCashPool=OFF", "publishMedia=OFF"]
        )
    ]

    public static let defaultWave2Badges: [MiniProgramWave2ScopeBadge] = [
        .init(id: "w2-01", domainID: "domain-B", summary: "Auth & Session Boundary"),
        .init(id: "w2-02", domainID: "domain-B", summary: "Home & Featured Discovery"),
        .init(id: "w2-03", domainID: "domain-B", summary: "Topic Detail & Ratings"),
        .init(id: "w2-04", domainID: "domain-C", summary: "Play Runtime & Story Order"),
        .init(id: "w2-05", domainID: "domain-C", summary: "Roam Map & Tile Memory"),
        .init(id: "w2-06", domainID: "domain-C", summary: "Search Map & Walking Route"),
        .init(id: "w2-07", domainID: "domain-B", summary: "Creative Square Workspace"),
        .init(id: "w2-08", domainID: "domain-D", summary: "Social Comments & Likes"),
        .init(id: "w2-09", domainID: "domain-D", summary: "Team Lobby & Invites"),
        .init(id: "w2-10", domainID: "domain-D", summary: "Activity Registration & Club"),
        .init(id: "w2-11", domainID: "domain-B", summary: "Profile, Favorites & History"),
        .init(id: "w2-12", domainID: "domain-E", summary: "Coupons & QR Redemption"),
        .init(id: "w2-13", domainID: "domain-E", summary: "Member Orders & Aftercare"),
        .init(id: "w2-14", domainID: "domain-C", summary: "Workshop & Purchased Library"),
        .init(id: "w2-15", domainID: "domain-E", summary: "Pro Editor & Topic Publish"),
        .init(id: "w2-16", domainID: "domain-E", summary: "Merchant Workbench & Store"),
        .init(id: "w2-17", domainID: "domain-E", summary: "Merchant AI NPC & Game Nodes"),
        .init(id: "w2-18", domainID: "domain-E", summary: "Merchant Marketing & Perks"),
        .init(id: "w2-19", domainID: "domain-E", summary: "Merchant Ledger & Orders"),
        .init(id: "w2-20", domainID: "domain-E", summary: "Merchant Team & Roles"),
        .init(id: "w2-21", domainID: "domain-E", summary: "Coop Finance & Asset Center")
    ]

    // MARK: - Derived Projections

    public var totalCoveredPages: Int {
        domainRows.reduce(0) { $0 + $1.coveredPageCount }
    }

    public var totalExpectedPages: Int {
        domainRows.reduce(0) { $0 + $1.totalPageCount }
    }

    public var integratedWave2Count: Int {
        wave2Badges.filter(\.isIntegrated).count
    }

    public var overallHeaderBadgeText: String {
        "99-Page Parity: \(totalCoveredPages)/\(totalExpectedPages) · Wave-2: \(integratedWave2Count)/\(wave2Badges.count) · Write Gates: FAIL-CLOSED"
    }

    public var domainTitlesSummaryText: String {
        domainRows.map(\.domainTitle).joined(separator: " | ")
    }

    public var wave2ScopeIDsSummaryText: String {
        wave2Badges.map(\.id).joined(separator: ", ")
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            domainsSection
            wave2ScopesSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniProgramParity.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Mini-Program 99-Page Parity & Wave-2 Alignment")
                    .font(.headline)
                Spacer()
                Text(verbatim: totalCoveredPages == 99 && integratedWave2Count == 21 ? "ALIGNED (99/99)" : "PARTIAL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(totalCoveredPages == 99 && integratedWave2Count == 21 ? Color.green : Color.orange)
                    .accessibilityIdentifier("miniProgramParity.statusBadge")
            }
            Text(verbatim: overallHeaderBadgeText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("miniProgramParity.overallSummary")
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Alignment Domains (4)")
                .font(.subheadline.weight(.semibold))

            ForEach(domainRows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.domainTitle)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: "\(row.coveredPageCount)/\(row.totalPageCount) pages")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.isFullyAligned ? Color.green : Color.orange)
                    }
                    Text(verbatim: row.coverageSummaryText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: row.failClosedGateBadgeText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("miniProgramParity.domainGates.\(row.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("miniProgramParity.domainRow.\(row.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniProgramParity.domainsSection")
    }

    private var wave2ScopesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Wave-2 Scopes (\(integratedWave2Count)/\(wave2Badges.count))")
                .font(.subheadline.weight(.semibold))

            Text(verbatim: wave2ScopeIDsSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("miniProgramParity.wave2ScopeIDs")

            ForEach(wave2Badges) { badge in
                HStack {
                    Text(verbatim: "\(badge.id) · \(badge.summary)")
                        .font(.caption2.monospaced())
                    Spacer()
                    Text(verbatim: badge.isIntegrated ? "INTEGRATED [FAIL-CLOSED]" : "PENDING")
                        .font(.caption2.monospaced())
                        .foregroundStyle(badge.isIntegrated ? Color.secondary : Color.orange)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("miniProgramParity.wave2Row.\(badge.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniProgramParity.wave2Section")
    }
}
