import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one club access, governance, enrollment, or settlement parity pillar.
public struct ClubAccessSettlementRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let title: String
    public let contractDetail: String
    public let isPermissionScoped: Bool
    public let liveMutationOrPayoutEnabled: Bool

    public init(
        id: String,
        code: String,
        title: String,
        contractDetail: String,
        isPermissionScoped: Bool = true,
        liveMutationOrPayoutEnabled: Bool = false
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.contractDetail = contractDetail
        self.isPermissionScoped = isPermissionScoped
        self.liveMutationOrPayoutEnabled = liveMutationOrPayoutEnabled
    }

    public var statusBadgeText: String {
        if isPermissionScoped && !liveMutationOrPayoutEnabled {
            return "SCOPED • FAIL-CLOSED"
        }
        return "ATTENTION REQUIRED"
    }
}

/// Self-contained presentation snapshot for:
/// 1. `/api/club/access/me` POST form
/// 2. `ClubGovernanceCoordinator` permission checks
/// 3. `ClubEnrollmentReader`
/// 4. `w2-16` settlement parity
public struct ClubAccessAndSettlementSnapshot: Equatable, Sendable {
    public let rows: [ClubAccessSettlementRow]
    public let accessMeUsesPOSTForm: Bool
    public let governanceRoleVerified: Bool
    public let liveSettlementPayoutEnabled: Bool

    public init(
        rows: [ClubAccessSettlementRow] = Self.defaultRows,
        accessMeUsesPOSTForm: Bool = true,
        governanceRoleVerified: Bool = true,
        liveSettlementPayoutEnabled: Bool = false
    ) {
        self.rows = rows
        self.accessMeUsesPOSTForm = accessMeUsesPOSTForm
        self.governanceRoleVerified = governanceRoleVerified
        self.liveSettlementPayoutEnabled = liveSettlementPayoutEnabled
    }

    public static let defaultRows: [ClubAccessSettlementRow] = [
        ClubAccessSettlementRow(
            id: "club-access-me-post",
            code: "POST /api/club/access/me",
            title: "Club Access Me POST Form Contract",
            contractDetail: "Dispatches POST form-encoded /api/club/access/me bound to account, epoch, and token; missing openness or role facts fail conservatively",
            isPermissionScoped: true,
            liveMutationOrPayoutEnabled: false
        ),
        ClubAccessSettlementRow(
            id: "club-governance-coordinator",
            code: "ClubGovernanceCoordinator",
            title: "Club Governance Permission & Baseline Checks",
            contractDetail: "Requires fresh server leader role/owned clubs; rechecks current eligibility on profile, settings, and member role reviews while keeping live writes OFF",
            isPermissionScoped: true,
            liveMutationOrPayoutEnabled: false
        ),
        ClubAccessSettlementRow(
            id: "club-enrollment-reader",
            code: "ClubEnrollmentReader",
            title: "Club Enrollment & Waitlist Read Parity",
            contractDetail: "Reads server-authoritative enrollment and waitlist status without inventing sale-window admission rules (E01-13 NO_SOURCE_CHANGE)",
            isPermissionScoped: true,
            liveMutationOrPayoutEnabled: false
        ),
        ClubAccessSettlementRow(
            id: "w2-16-settlement-parity",
            code: "w2-16",
            title: "Club Settlement & Revenue Read Parity",
            contractDetail: "Displays read-only settlement summaries and order ledger state; cash withdrawal and financial governance mutations stay hard-off",
            isPermissionScoped: true,
            liveMutationOrPayoutEnabled: false
        )
    ]

    public static let failClosedDefault = ClubAccessAndSettlementSnapshot()

    public var isAllScopedAndFailClosed: Bool {
        rows.count == 4 &&
        accessMeUsesPOSTForm &&
        governanceRoleVerified &&
        !liveSettlementPayoutEnabled &&
        rows.allSatisfy { $0.isPermissionScoped && !$0.liveMutationOrPayoutEnabled }
    }
}

/// SwiftUI Section View rendering `/api/club/access/me` POST form, `ClubGovernanceCoordinator` permission checks,
/// `ClubEnrollmentReader`, and `w2-16` settlement parity using `Text(verbatim:)` throughout.
@MainActor
public struct ClubAccessAndSettlementSectionView: View {
    public let snapshot: ClubAccessAndSettlementSnapshot

    public init(snapshot: ClubAccessAndSettlementSnapshot = .failClosedDefault) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllScopedAndFailClosed
            ? "Club Access & Settlement Gate: FAIL-CLOSED (4/4 Scoped)"
            : "Club Access & Settlement Gate: REVIEW REQUIRED"
    }

    public var accessMeRouteSummaryText: String {
        snapshot.accessMeUsesPOSTForm
            ? "Access Route: POST /api/club/access/me (Form-Encoded • Session-Scoped)"
            : "Access Route: MISMATCH (Expected POST Form-Encoded /api/club/access/me)"
    }

    public var governanceSummaryText: String {
        snapshot.governanceRoleVerified
            ? "ClubGovernanceCoordinator: Fresh server role & baseline checks active; live writes OFF"
            : "ClubGovernanceCoordinator: Unverified role fallback detected"
    }

    public var settlementParitySummaryText: String {
        snapshot.liveSettlementPayoutEnabled
            ? "w2-16 Settlement & ClubEnrollmentReader: VIOLATION — live payout enabled"
            : "w2-16 Settlement & ClubEnrollmentReader: Read-only parity • Payouts OFF"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Club Access, Governance & w2-16 Settlement Parity")
                    .font(.headline)
                    .accessibilityIdentifier("clubAccessSettlement.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllScopedAndFailClosed ? Color.green : Color.orange)
                    .accessibilityIdentifier("clubAccessSettlement.statusBadge")
            }

            Text(verbatim: accessMeRouteSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.accessMeUsesPOSTForm ? Color.secondary : Color.red)
                .accessibilityIdentifier("clubAccessSettlement.accessMeRouteSummary")

            Text(verbatim: governanceSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.governanceRoleVerified ? Color.secondary : Color.red)
                .accessibilityIdentifier("clubAccessSettlement.governanceSummary")

            Text(verbatim: settlementParitySummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.liveSettlementPayoutEnabled ? Color.red : Color.secondary)
                .accessibilityIdentifier("clubAccessSettlement.settlementParitySummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.code)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(
                                    (row.isPermissionScoped && !row.liveMutationOrPayoutEnabled)
                                        ? Color.green
                                        : Color.orange
                                )
                        }
                        Text(verbatim: row.contractDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("clubAccessSettlement.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clubAccessSettlement.section")
    }
}
