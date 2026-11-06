import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for a single roam & exploration parity pillar.
public struct RoamExplorationPillarRow: Identifiable, Equatable, Sendable {
    public enum ReadinessStatus: String, CaseIterable, Equatable, Sendable {
        case verified = "VERIFIED"
        case guardedReadOnly = "GUARDED_READ_ONLY"
        case blocked = "BLOCKED"
    }

    public let id: String
    public let code: String
    public let title: String
    public let contractSummary: String
    public let guardrailNote: String
    public let status: ReadinessStatus

    public init(
        id: String,
        code: String,
        title: String,
        contractSummary: String,
        guardrailNote: String,
        status: ReadinessStatus
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.contractSummary = contractSummary
        self.guardrailNote = guardrailNote
        self.status = status
    }

    public var rowAccessibilityIdentifier: String {
        "roamExplorationAudit.pillar.\(id)"
    }

    public var statusAccessibilityIdentifier: String {
        "roamExplorationAudit.status.\(id)"
    }
}

/// Self-contained snapshot summarizing the 5 roam & exploration parity pillars:
/// 1. `w2-08` roam subpages (`finished-list`, `route-detail`, `point-detail`)
/// 2. `w2-09` private tools (`inventory`, `scan`, `pay-result`, `coupon-confirm`)
/// 3. `I00+I11` received stamps (`GET /api/user/stamps/received` + `GET /api/stamps`)
/// 4. `I01` GPS arrival accuracy (`horizontalAccuracy` threshold & live-location freshness)
/// 5. `F-W14/W15` story walking & personal fog (`local-only` fog tiles, no cross-user fog leak)
public struct RoamAndExplorationParitySnapshot: Equatable, Sendable {
    public static let canonicalPillarIDs: [String] = [
        "w2_08_roam_subpages",
        "w2_09_private_tools",
        "i00_i11_received_stamps",
        "i01_gps_arrival_accuracy",
        "f_w14_w15_story_walking_personal_fog"
    ]

    public let pillars: [RoamExplorationPillarRow]
    public let gpsMaxHorizontalAccuracyMeters: Int
    public let personalFogLocalOnly: Bool
    public let unmountedWriteRoutesFailClosed: Bool

    public init(
        pillars: [RoamExplorationPillarRow],
        gpsMaxHorizontalAccuracyMeters: Int = 50,
        personalFogLocalOnly: Bool = true,
        unmountedWriteRoutesFailClosed: Bool = true
    ) {
        self.pillars = pillars
        self.gpsMaxHorizontalAccuracyMeters = gpsMaxHorizontalAccuracyMeters
        self.personalFogLocalOnly = personalFogLocalOnly
        self.unmountedWriteRoutesFailClosed = unmountedWriteRoutesFailClosed
    }

    public var verifiedCount: Int {
        pillars.filter { $0.status != .blocked }.count
    }

    public var blockedCount: Int {
        pillars.filter { $0.status == .blocked }.count
    }

    public var isAllParityVerified: Bool {
        pillars.count == Self.canonicalPillarIDs.count &&
            blockedCount == 0 &&
            personalFogLocalOnly &&
            unmountedWriteRoutesFailClosed &&
            gpsMaxHorizontalAccuracyMeters > 0 &&
            gpsMaxHorizontalAccuracyMeters <= 65
    }

    public func pillar(id: String) -> RoamExplorationPillarRow? {
        pillars.first { $0.id == id }
    }

    public static let defaultVerified = RoamAndExplorationParitySnapshot(
        pillars: [
            RoamExplorationPillarRow(
                id: "w2_08_roam_subpages",
                code: "w2-08",
                title: "Roam Subpages & History Filter",
                contractSummary: "GET /api/roam/routes, /api/roam/route/{id}, /api/roam/point/{id}, /api/roam/finished",
                guardrailNote: "Pagination, status filter, and retry/empty states isolated per account.",
                status: .verified
            ),
            RoamExplorationPillarRow(
                id: "w2_09_private_tools",
                code: "w2-09",
                title: "Private Tools & Coupon Confirm",
                contractSummary: "Inventory, QR scan parser, pay-result reconciliation, and read-only coupon confirm",
                guardrailNote: "POST /api/pay/create and /api/user/coupons/{id}/use remain fail-closed.",
                status: .guardedReadOnly
            ),
            RoamExplorationPillarRow(
                id: "i00_i11_received_stamps",
                code: "I00+I11",
                title: "Received Stamps & Collection Readback",
                contractSummary: "GET /api/user/stamps/received joined with GET /api/stamps metadata",
                guardrailNote: "Deduplicated by stampId + obtainTime; account switch clears cached ledger.",
                status: .verified
            ),
            RoamExplorationPillarRow(
                id: "i01_gps_arrival_accuracy",
                code: "I01",
                title: "GPS Arrival Accuracy & Check-In Gate",
                contractSummary: "CLLocation horizontalAccuracy <= 50m + haversine radius check before arrival",
                guardrailNote: "Rejects stale, negative, or low-accuracy coordinates before POST /api/roam/check-in.",
                status: .verified
            ),
            RoamExplorationPillarRow(
                id: "f_w14_w15_story_walking_personal_fog",
                code: "F-W14/W15",
                title: "Story Walking & Personal Fog",
                contractSummary: "Progressive story-node unlock and device-scoped personal fog-of-war cells",
                guardrailNote: "Personal fog never mutates server quest authority or leaks across accounts.",
                status: .verified
            )
        ],
        gpsMaxHorizontalAccuracyMeters: 50,
        personalFogLocalOnly: true,
        unmountedWriteRoutesFailClosed: true
    )

    public static func withBlockedPillars(
        _ blockedIDs: Set<String>,
        gpsMaxHorizontalAccuracyMeters: Int = 50,
        personalFogLocalOnly: Bool = true,
        unmountedWriteRoutesFailClosed: Bool = true
    ) -> RoamAndExplorationParitySnapshot {
        let updated = defaultVerified.pillars.map { row in
            guard blockedIDs.contains(row.id) || blockedIDs.contains(row.code) else {
                return row
            }
            return RoamExplorationPillarRow(
                id: row.id,
                code: row.code,
                title: row.title,
                contractSummary: row.contractSummary,
                guardrailNote: row.guardrailNote,
                status: .blocked
            )
        }
        return RoamAndExplorationParitySnapshot(
            pillars: updated,
            gpsMaxHorizontalAccuracyMeters: gpsMaxHorizontalAccuracyMeters,
            personalFogLocalOnly: personalFogLocalOnly,
            unmountedWriteRoutesFailClosed: unmountedWriteRoutesFailClosed
        )
    }
}

@MainActor
public struct RoamAndExplorationParitySectionView: View {
    public let snapshot: RoamAndExplorationParitySnapshot
    public var onSelectPillar: ((RoamExplorationPillarRow) -> Void)?

    public init(
        snapshot: RoamAndExplorationParitySnapshot = .defaultVerified,
        onSelectPillar: ((RoamExplorationPillarRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectPillar = onSelectPillar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            guardrailsBanner
            ForEach(snapshot.pillars) { row in
                pillarCard(row)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("roamExplorationAudit.section")
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .foregroundStyle(.teal)
            Text(verbatim: "Roam & Exploration Parity Audit")
                .font(.headline)
                .accessibilityIdentifier("roamExplorationAudit.header")
            Spacer()
            Text(verbatim: summaryBadgeText)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(summaryBadgeTint.opacity(0.16))
                )
                .foregroundStyle(summaryBadgeTint)
                .accessibilityIdentifier("roamExplorationAudit.summaryBadge")
        }
    }

    private var guardrailsBanner: some View {
        HStack(spacing: 8) {
            badgePill(
                text: "GPS <= \(snapshot.gpsMaxHorizontalAccuracyMeters)m",
                tint: snapshot.gpsMaxHorizontalAccuracyMeters <= 65 ? .teal : .red
            )
            badgePill(
                text: snapshot.personalFogLocalOnly ? "PERSONAL FOG LOCAL-ONLY" : "FOG ISOLATION VIOLATION",
                tint: snapshot.personalFogLocalOnly ? .blue : .red
            )
            badgePill(
                text: snapshot.unmountedWriteRoutesFailClosed ? "WRITE GATES FAIL-CLOSED" : "UNREVIEWED WRITE OPEN",
                tint: snapshot.unmountedWriteRoutesFailClosed ? .green : .red
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("roamExplorationAudit.guardrails")
    }

    private func pillarCard(_ row: RoamExplorationPillarRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: "[\(row.code)] \(row.title)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: row.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(statusTint(for: row.status).opacity(0.16))
                    )
                    .foregroundStyle(statusTint(for: row.status))
                    .accessibilityIdentifier(row.statusAccessibilityIdentifier)
            }

            Text(verbatim: row.contractSummary)
                .font(.caption)
                .foregroundStyle(.primary)

            Text(verbatim: row.guardrailNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPillar?(row)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.rowAccessibilityIdentifier)
    }

    private func badgePill(text: String, tint: Color) -> some View {
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

    public var summaryBadgeText: String {
        if snapshot.isAllParityVerified {
            return "PARITY VERIFIED (\(snapshot.verifiedCount)/\(snapshot.pillars.count))"
        }
        return "ATTENTION (\(snapshot.verifiedCount)/\(snapshot.pillars.count) READY)"
    }

    private var summaryBadgeTint: Color {
        snapshot.isAllParityVerified ? .green : .orange
    }

    private func statusTint(for status: RoamExplorationPillarRow.ReadinessStatus) -> Color {
        switch status {
        case .verified:
            return .green
        case .guardedReadOnly:
            return .orange
        case .blocked:
            return .red
        }
    }
}
