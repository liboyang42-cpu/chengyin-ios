import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one commerce & wallet safety pillar.
public struct CommerceSafetyPillarRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let title: String
    public let policySummary: String
    public let isFailClosedCompliant: Bool
    public let liveCashMutationEnabled: Bool

    public init(
        id: String,
        code: String,
        title: String,
        policySummary: String,
        isFailClosedCompliant: Bool = true,
        liveCashMutationEnabled: Bool = false
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.policySummary = policySummary
        self.isFailClosedCompliant = isFailClosedCompliant
        self.liveCashMutationEnabled = liveCashMutationEnabled
    }

    public var statusBadgeText: String {
        if isFailClosedCompliant && !liveCashMutationEnabled {
            return "FAIL-CLOSED (SAFE)"
        }
        return "VIOLATION (REVIEW REQUIRED)"
    }
}

/// Self-contained presentation snapshot for the 5 commerce & wallet safety pillars:
/// 1. `w2-03` wallet safety
/// 2. `w2-05` fail-closed withdrawal gate
/// 3. `I04` points ledger readback
/// 4. `G-W06/W07` `UNKNOWN` refund lock & staff redemption split
/// 5. `W17.4` non-cash reward policy
public struct CommerceAndWalletSafetySnapshot: Equatable, Sendable {
    public let pillars: [CommerceSafetyPillarRow]
    public let unknownRefundLockedCount: Int
    public let pointsWithdrawableAllowed: Bool

    public init(
        pillars: [CommerceSafetyPillarRow] = Self.defaultPillars,
        unknownRefundLockedCount: Int = 0,
        pointsWithdrawableAllowed: Bool = false
    ) {
        self.pillars = pillars
        self.unknownRefundLockedCount = max(0, unknownRefundLockedCount)
        self.pointsWithdrawableAllowed = pointsWithdrawableAllowed
    }

    public static let defaultPillars: [CommerceSafetyPillarRow] = [
        CommerceSafetyPillarRow(
            id: "w2-03",
            code: "w2-03",
            title: "Wallet Safety & Read-Only Ledger",
            policySummary: "Balances and transactions are server-read only; zero client-side balance fabrication or direct cash top-up",
            isFailClosedCompliant: true,
            liveCashMutationEnabled: false
        ),
        CommerceSafetyPillarRow(
            id: "w2-05",
            code: "w2-05",
            title: "Fail-Closed Withdrawal Gate",
            policySummary: "Payout and withdrawal endpoints remain hard-off until per-market entity and compliance sign-off",
            isFailClosedCompliant: true,
            liveCashMutationEnabled: false
        ),
        CommerceSafetyPillarRow(
            id: "I04",
            code: "I04",
            title: "Asset & Points Ledger Readback",
            policySummary: "WalletLedgerRow (currentPoints/eventId) and OrderCancellationObservation (pointsUsed/pointsReturned) require authoritative readback",
            isFailClosedCompliant: true,
            liveCashMutationEnabled: false
        ),
        CommerceSafetyPillarRow(
            id: "G-W06-W07",
            code: "G-W06/W07",
            title: "UNKNOWN Refund Lock & Staff Redemption Split",
            policySummary: "Uncertain refund outcomes stay locked until receipt readback; player ticket preview is strictly separated from staff verification",
            isFailClosedCompliant: true,
            liveCashMutationEnabled: false
        ),
        CommerceSafetyPillarRow(
            id: "W17.4",
            code: "W17.4",
            title: "Non-Cash Reward Policy",
            policySummary: "Points, badges, and coupons are non-withdrawable and non-cash; zero client-supplied reward amounts",
            isFailClosedCompliant: true,
            liveCashMutationEnabled: false
        )
    ]

    public static let failClosedDefault = CommerceAndWalletSafetySnapshot()

    public var isAllCompliant: Bool {
        pillars.count == 5 &&
        !pointsWithdrawableAllowed &&
        pillars.allSatisfy { $0.isFailClosedCompliant && !$0.liveCashMutationEnabled }
    }

    public var compliantPillarCount: Int {
        pillars.filter { $0.isFailClosedCompliant && !$0.liveCashMutationEnabled }.count
    }
}

/// SwiftUI Section View rendering the 5 commerce & wallet safety pillars using `Text(verbatim:)` throughout.
@MainActor
public struct CommerceAndWalletSafetySectionView: View {
    public let snapshot: CommerceAndWalletSafetySnapshot

    public init(snapshot: CommerceAndWalletSafetySnapshot = .failClosedDefault) {
        self.snapshot = snapshot
    }

    public var overallGateBadgeText: String {
        snapshot.isAllCompliant
            ? "Commerce & Wallet Gate: FAIL-CLOSED (\(snapshot.compliantPillarCount)/\(snapshot.pillars.count) Pillars Safe)"
            : "Commerce & Wallet Gate: ATTENTION REQUIRED (\(snapshot.compliantPillarCount)/\(snapshot.pillars.count) Pillars Safe)"
    }

    public var refundLockBannerText: String {
        if snapshot.unknownRefundLockedCount > 0 {
            return "UNKNOWN Refund Lock: \(snapshot.unknownRefundLockedCount) pending order(s) locked awaiting server readback"
        }
        return "UNKNOWN Refund Lock: 0 pending locks (readback-only resolution active)"
    }

    public var nonCashPolicyBannerText: String {
        snapshot.pointsWithdrawableAllowed
            ? "W17.4 Non-Cash Policy: VIOLATION — points marked withdrawable"
            : "W17.4 Non-Cash Policy: ENFORCED — points & coupons are non-withdrawable"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Commerce & Wallet Safety Pillars")
                    .font(.headline)
                    .accessibilityIdentifier("commerceWalletSafety.title")
                Spacer()
                Text(verbatim: overallGateBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllCompliant ? Color.green : Color.red)
                    .accessibilityIdentifier("commerceWalletSafety.overallBadge")
            }

            Text(verbatim: refundLockBannerText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.unknownRefundLockedCount > 0 ? Color.orange : Color.secondary)
                .accessibilityIdentifier("commerceWalletSafety.refundLockBanner")

            Text(verbatim: nonCashPolicyBannerText)
                .font(.footnote)
                .foregroundStyle(snapshot.pointsWithdrawableAllowed ? Color.red : Color.secondary)
                .accessibilityIdentifier("commerceWalletSafety.nonCashPolicyBanner")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.pillars) { pillar in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(pillar.code)] \(pillar.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: pillar.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(
                                    (pillar.isFailClosedCompliant && !pillar.liveCashMutationEnabled)
                                        ? Color.green
                                        : Color.red
                                )
                        }
                        Text(verbatim: pillar.policySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("commerceWalletSafety.pillarList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("commerceWalletSafety.section")
    }
}
