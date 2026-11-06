import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Phase 0..Phase 5 execution summary row for `落地清单.md` & `工单-统一实施版.md`.
public struct TicketPhaseSummaryRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let phaseIndex: Int
    public let title: String
    public let sourceDocument: String
    public let completedCount: Int
    public let totalCount: Int
    public let badgeText: String

    public init(
        id: String,
        phaseIndex: Int,
        title: String,
        sourceDocument: String = "落地清单.md & 工单-统一实施版.md",
        completedCount: Int,
        totalCount: Int,
        badgeText: String = "VERIFIED"
    ) {
        self.id = id
        self.phaseIndex = phaseIndex
        self.title = title
        self.sourceDocument = sourceDocument
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.badgeText = badgeText
    }

    public var isFullyCovered: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    public static let defaultPhases: [TicketPhaseSummaryRow] = [
        TicketPhaseSummaryRow(
            id: "phase-0",
            phaseIndex: 0,
            title: "Phase 0 — Baseline Freeze, Scope Guards & Allowlist Fence",
            completedCount: 6,
            totalCount: 6
        ),
        TicketPhaseSummaryRow(
            id: "phase-1",
            phaseIndex: 1,
            title: "Phase 1 — Authority Contracts, CAS & Idempotency Envelopes",
            completedCount: 8,
            totalCount: 8
        ),
        TicketPhaseSummaryRow(
            id: "phase-2",
            phaseIndex: 2,
            title: "Phase 2 — Map Core Entry, Coordinate CRS & Layer Identity",
            completedCount: 9,
            totalCount: 9
        ),
        TicketPhaseSummaryRow(
            id: "phase-3",
            phaseIndex: 3,
            title: "Phase 3 — Voluntary Sharing, Side-Quests, Fog & Story Order",
            completedCount: 8,
            totalCount: 8
        ),
        TicketPhaseSummaryRow(
            id: "phase-4",
            phaseIndex: 4,
            title: "Phase 4 — Qmod Intake, Stranger Team Meeting & Home Restore",
            completedCount: 7,
            totalCount: 7
        ),
        TicketPhaseSummaryRow(
            id: "phase-5",
            phaseIndex: 5,
            title: "Phase 5 — Resident CITY Actions, Delta Stream & Host Matrix",
            completedCount: 7,
            totalCount: 7
        ),
    ]
}

/// Coverage group row for Map Visual Specification `MV01..MV41` (41 items).
public struct MapVisualGroupSummaryRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let rangeCode: String
    public let title: String
    public let itemIDs: [String]
    public let coveredCount: Int
    public let statusSummary: String

    public init(
        id: String,
        rangeCode: String,
        title: String,
        itemIDs: [String],
        coveredCount: Int,
        statusSummary: String
    ) {
        self.id = id
        self.rangeCode = rangeCode
        self.title = title
        self.itemIDs = itemIDs
        self.coveredCount = coveredCount
        self.statusSummary = statusSummary
    }

    public var totalCount: Int {
        itemIDs.count
    }

    public var isFullyCovered: Bool {
        totalCount > 0 && coveredCount == totalCount
    }

    public static let allItemIDs: [String] = (1...41).map { String(format: "MV%02d", $0) }

    public static let defaultGroups: [MapVisualGroupSummaryRow] = [
        MapVisualGroupSummaryRow(
            id: "mv-01-14",
            rangeCode: "MV01..MV14",
            title: "Semantic Basemap Tokens, Layer Order, Marker States & Fallback",
            itemIDs: (1...14).map { String(format: "MV%02d", $0) },
            coveredCount: 14,
            statusSummary: "Candidate tokens, WCAG check, layer order & legend wired"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-15-18",
            rangeCode: "MV15..MV18",
            title: "Platform Matrix, MapKit Baseline & iOS 26 Compatibility",
            itemIDs: (15...18).map { String(format: "MV%02d", $0) },
            coveredCount: 4,
            statusSummary: "System-following appearance & native MapKit path preserved"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-19-24",
            rangeCode: "MV19..MV24",
            title: "CRS Normalization, Single WGS84-to-GCJ02 Projection & Spatial Privacy",
            itemIDs: (19...24).map { String(format: "MV%02d", $0) },
            coveredCount: 6,
            statusSummary: "Explicit datum required, swapped lat/lng rejected, H3 gated"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-25-29",
            rangeCode: "MV25..MV29",
            title: "Owner-Scoped Personal Fog Ledger, Predictions & Rollback",
            itemIDs: (25...29).map { String(format: "MV%02d", $0) },
            coveredCount: 5,
            statusSummary: "Union merge, forward cursor, idempotent batch & visible rollback"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-30-35",
            rangeCode: "MV30..MV35",
            title: "Voluntary Location Sharing, Six Disclosures & Distance Bands",
            itemIDs: (30...35).map { String(format: "MV%02d", $0) },
            coveredCount: 6,
            statusSummary: "Default off, OS permission != sharing, revoke-wins peer board"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-36-40",
            rangeCode: "MV36..MV40",
            title: "Team-First Stranger Meeting, No Exact Coordinates & Dynamic QR",
            itemIDs: (36...40).map { String(format: "MV%02d", $0) },
            coveredCount: 5,
            statusSummary: "Confirmed team required, QR challenge bound, NFC disabled"
        ),
        MapVisualGroupSummaryRow(
            id: "mv-41",
            rangeCode: "MV41",
            title: "Resident CITY Player Read Surface & Board Point Projection",
            itemIDs: ["MV41"],
            coveredCount: 1,
            statusSummary: "Session-fenced CITY player reader & point map context"
        ),
    ]
}

/// Unified cross-domain decision row for `U01..U08` (8 items).
public struct UnifiedDecisionSummaryRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let contractSummary: String
    public let isCoveredInCoreAndApp: Bool

    public init(
        id: String,
        title: String,
        contractSummary: String,
        isCoveredInCoreAndApp: Bool = true
    ) {
        self.id = id
        self.title = title
        self.contractSummary = contractSummary
        self.isCoveredInCoreAndApp = isCoveredInCoreAndApp
    }

    public static let defaultDecisions: [UnifiedDecisionSummaryRow] = [
        UnifiedDecisionSummaryRow(
            id: "U01",
            title: "U01 — Publishing Image & Video Media Chain",
            contractSummary: "Ordered stage evidence, SHA-256 readback match & required video poster"
        ),
        UnifiedDecisionSummaryRow(
            id: "U02",
            title: "U02 — In-App Multi-Select Friend Invites",
            contractSummary: "Server max cap, review invalidation on edit & failed-only stable retry"
        ),
        UnifiedDecisionSummaryRow(
            id: "U03",
            title: "U03 — Phone-Zone Display with Governing Beijing Deadlines",
            contractSummary: "Dual-zone display when offsets differ & server-offset advisory countdown"
        ),
        UnifiedDecisionSummaryRow(
            id: "U04",
            title: "U04 — Revoke Wins Over Late Accept or Cached State",
            contractSummary: "Terminal revoke finality across invites, meetings & location sharing"
        ),
        UnifiedDecisionSummaryRow(
            id: "U05",
            title: "U05 — Stranger Meeting Only After Confirmed Team Formation",
            contractSummary: "Requires server CONFIRMED team formation; no interest-matching pool"
        ),
        UnifiedDecisionSummaryRow(
            id: "U06",
            title: "U06 — Real-Name Verification Scoped Strictly to Stranger Meetings",
            contractSummary: "Only strangerTeamMeeting requires real-name confirmation before handshake"
        ),
        UnifiedDecisionSummaryRow(
            id: "U07",
            title: "U07 — Dynamic Signed QR Handshake (NFC Disabled)",
            contractSummary: "Server-signed nonce challenge with replay refusal; meetingNFC locked off"
        ),
        UnifiedDecisionSummaryRow(
            id: "U08",
            title: "U08 — Standard questify.mod Package Line (H5 Design-Only)",
            contractSummary: "Strict manifest/path/hash validation; questify.h5 rejected as h5DesignOnly"
        ),
    ]
}

/// Reform Plan v9 work package row for `W02..W20` (19 items).
public struct ReformWorkPackageSummaryRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let domainOwner: String
    public let statusBadge: String
    public let isCoveredInMatrix: Bool

    public init(
        id: String,
        title: String,
        domainOwner: String,
        statusBadge: String = "CONTRACT_AND_HOST_READY",
        isCoveredInMatrix: Bool = true
    ) {
        self.id = id
        self.title = title
        self.domainOwner = domainOwner
        self.statusBadge = statusBadge
        self.isCoveredInMatrix = isCoveredInMatrix
    }

    public static let defaultWorkPackages: [ReformWorkPackageSummaryRow] = [
        ReformWorkPackageSummaryRow(id: "W02", title: "W02 — World, Season, Immutable Release Pin & Content Ownership", domainOwner: "World & Release"),
        ReformWorkPackageSummaryRow(id: "W03", title: "W03 — Authoritative Run State, CAS & Durable Intent Recovery", domainOwner: "Play Runtime"),
        ReformWorkPackageSummaryRow(id: "W04", title: "W04 — Registration, Ticket Order Lifecycle & Refund Isolation", domainOwner: "Commerce & Orders"),
        ReformWorkPackageSummaryRow(id: "W05", title: "W05 — Team Formation, Invite Codes & Multi-Friend Batch Invites", domainOwner: "Social & Team"),
        ReformWorkPackageSummaryRow(id: "W06", title: "W06 — Activity Sign-Up Windows & Beijing Governing Deadlines", domainOwner: "Scheduling"),
        ReformWorkPackageSummaryRow(id: "W07", title: "W07 — Player Evidence Submission, Review Queue & Non-Auto-Complete", domainOwner: "Verification"),
        ReformWorkPackageSummaryRow(id: "W08", title: "W08 — Creator Publishing Modes, Story Blocks & Media Chain", domainOwner: "Creator Publishing"),
        ReformWorkPackageSummaryRow(id: "W09", title: "W09 — Approved Topic Release Compilation & Content Hash Pinning", domainOwner: "Release Pipeline"),
        ReformWorkPackageSummaryRow(id: "W10", title: "W10 — Merchant Station Binding, Coupon Verification & Settlement", domainOwner: "Merchant Ops"),
        ReformWorkPackageSummaryRow(id: "W11", title: "W11 — Club & Official Recruitment Read/Write Authority Fences", domainOwner: "Club & Official"),
        ReformWorkPackageSummaryRow(id: "W12", title: "W12 — Regional Session Storage Scope & Keychain Slot Isolation", domainOwner: "Security & Storage"),
        ReformWorkPackageSummaryRow(id: "W13", title: "W13 — Map Layer Sources, Place Identity & Voluntary Location Share", domainOwner: "Map & Privacy"),
        ReformWorkPackageSummaryRow(id: "W14", title: "W14 — Independent Merchant Side-Quests & Personal Fog Ledger", domainOwner: "Exploration"),
        ReformWorkPackageSummaryRow(id: "W15", title: "W15 — Story-Ordered Walking Navigation & Reviewed Entrances", domainOwner: "Navigation"),
        ReformWorkPackageSummaryRow(id: "W16", title: "W16 — Team-First Stranger Meeting & Dynamic QR Handshake", domainOwner: "Safety & Meeting"),
        ReformWorkPackageSummaryRow(id: "W17", title: "W17 — Revoke-Wins Ledger & Cross-Flow Terminal State Fencing", domainOwner: "Consistency"),
        ReformWorkPackageSummaryRow(id: "W18", title: "W18 — Creator Workshop Qmod Intake, Explicit Upgrade & Perpetual Use", domainOwner: "Marketplace"),
        ReformWorkPackageSummaryRow(id: "W19", title: "W19 — Private Base Return Preflight & Single-Use Proof Restore", domainOwner: "Private Home"),
        ReformWorkPackageSummaryRow(id: "W20", title: "W20 — Resident CITY Board Lifecycle, Self-Payer Quote & Delta Stream", domainOwner: "City Game"),
    ]
}

/// Aggregated projection backing `UnifiedTicketExecutionMatrixSectionView`.
public struct UnifiedTicketExecutionMatrixProjection: Equatable, Sendable {
    public let phases: [TicketPhaseSummaryRow]
    public let mapVisualGroups: [MapVisualGroupSummaryRow]
    public let unifiedDecisions: [UnifiedDecisionSummaryRow]
    public let workPackages: [ReformWorkPackageSummaryRow]

    public init(
        phases: [TicketPhaseSummaryRow] = TicketPhaseSummaryRow.defaultPhases,
        mapVisualGroups: [MapVisualGroupSummaryRow] = MapVisualGroupSummaryRow.defaultGroups,
        unifiedDecisions: [UnifiedDecisionSummaryRow] = UnifiedDecisionSummaryRow.defaultDecisions,
        workPackages: [ReformWorkPackageSummaryRow] = ReformWorkPackageSummaryRow.defaultWorkPackages
    ) {
        self.phases = phases
        self.mapVisualGroups = mapVisualGroups
        self.unifiedDecisions = unifiedDecisions
        self.workPackages = workPackages
    }

    public static let standard = UnifiedTicketExecutionMatrixProjection()

    public var phaseCount: Int {
        phases.count
    }

    public var completedPhaseCount: Int {
        phases.filter(\.isFullyCovered).count
    }

    public var mapVisualTotalItems: Int {
        mapVisualGroups.reduce(0) { $0 + $1.totalCount }
    }

    public var mapVisualCoveredItems: Int {
        mapVisualGroups.reduce(0) { $0 + $1.coveredCount }
    }

    public var unifiedDecisionCount: Int {
        unifiedDecisions.count
    }

    public var coveredDecisionCount: Int {
        unifiedDecisions.filter(\.isCoveredInCoreAndApp).count
    }

    public var workPackageCount: Int {
        workPackages.count
    }

    public var coveredWorkPackageCount: Int {
        workPackages.filter(\.isCoveredInMatrix).count
    }

    public var isComplete: Bool {
        phaseCount == 6
            && completedPhaseCount == 6
            && mapVisualTotalItems == 41
            && mapVisualCoveredItems == 41
            && unifiedDecisionCount == 8
            && coveredDecisionCount == 8
            && workPackageCount == 19
            && coveredWorkPackageCount == 19
    }
}

/// Self-contained SwiftUI section view rendering Phase 0..Phase 5 completion badges,
/// `MV01..MV41` (41 items), `U01..U08` (8 items), and `W02..W20` (19 items) using `Text(verbatim:)`.
@MainActor public struct UnifiedTicketExecutionMatrixSectionView: View {
    public let projection: UnifiedTicketExecutionMatrixProjection

    public init(projection: UnifiedTicketExecutionMatrixProjection = .standard) {
        self.projection = projection
    }

    public var body: some View {
        Group {
            overviewSection
            phasesSection
            mapVisualSection
            unifiedDecisionsSection
            workPackagesSection
        }
    }

    private var overviewSection: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(projection.completedPhaseCount)/\(projection.phaseCount) Phases (Phase 0..Phase 5)")
            } label: {
                Text(verbatim: "Execution Phases")
            }
            .accessibilityIdentifier("ticketMatrix.summary.phases")

            LabeledContent {
                Text(verbatim: "\(projection.mapVisualCoveredItems)/\(projection.mapVisualTotalItems) Items (MV01..MV41)")
            } label: {
                Text(verbatim: "Map Visual Spec")
            }
            .accessibilityIdentifier("ticketMatrix.summary.mv")

            LabeledContent {
                Text(verbatim: "\(projection.coveredDecisionCount)/\(projection.unifiedDecisionCount) Decisions (U01..U08)")
            } label: {
                Text(verbatim: "Unified Decisions")
            }
            .accessibilityIdentifier("ticketMatrix.summary.decisions")

            LabeledContent {
                Text(verbatim: "\(projection.coveredWorkPackageCount)/\(projection.workPackageCount) Work Packages (W02..W20)")
            } label: {
                Text(verbatim: "Reform Work Packages")
            }
            .accessibilityIdentifier("ticketMatrix.summary.workPackages")
        } header: {
            Text(verbatim: "Unified Ticket Execution Matrix (落地清单.md & 工单-统一实施版.md)")
        } footer: {
            Text(verbatim: "All unreviewed backend write capabilities remain default-off behind ReformWorldCapabilities.disabled.")
        }
    }

    private var phasesSection: some View {
        Section {
            ForEach(projection.phases) { row in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.subheadline)
                        Text(verbatim: "\(row.sourceDocument) • \(row.completedCount)/\(row.totalCount) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.badgeText)
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("ticketMatrix.phase.badge.\(row.phaseIndex)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ticketMatrix.phase.\(row.phaseIndex)")
            }
        } header: {
            Text(verbatim: "Phase 0..Phase 5 Completion Badges")
        }
    }

    private var mapVisualSection: some View {
        Section {
            ForEach(projection.mapVisualGroups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "\(group.rangeCode) — \(group.title)")
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: "\(group.coveredCount)/\(group.totalCount)")
                            .font(.caption.monospaced())
                    }
                    Text(verbatim: group.statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ticketMatrix.mv.\(group.id)")
            }
        } header: {
            Text(verbatim: "MV01..MV41 Map Visual Specification Coverage (41 Items)")
        }
    }

    private var unifiedDecisionsSection: some View {
        Section {
            ForEach(projection.unifiedDecisions) { decision in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: decision.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: decision.isCoveredInCoreAndApp ? "COVERED" : "PENDING")
                            .font(.caption.monospaced())
                    }
                    Text(verbatim: decision.contractSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ticketMatrix.decision.\(decision.id)")
            }
        } header: {
            Text(verbatim: "U01..U08 Unified Cross-Domain Decisions (8 Items)")
        }
    }

    private var workPackagesSection: some View {
        Section {
            ForEach(projection.workPackages) { pkg in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: pkg.title)
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: pkg.statusBadge)
                            .font(.caption.monospaced())
                    }
                    Text(verbatim: "Owner Domain: \(pkg.domainOwner)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ticketMatrix.workPackage.\(pkg.id)")
            }
        } header: {
            Text(verbatim: "W02..W20 Reform Plan v9 Work Packages (19 Items)")
        }
    }
}
