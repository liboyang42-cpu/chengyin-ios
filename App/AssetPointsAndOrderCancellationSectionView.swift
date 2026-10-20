import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for `I04` points ledger readback and order cancellation points conservation.
public struct AssetPointsCancellationRow: Identifiable, Equatable, Sendable {
    public enum ConservationState: String, Equatable, Sendable {
        case conservedByAuthority
        case awaitingServerReadback
        case discrepancyDetected
    }

    public let id: String
    public let orderNumber: String
    public let deductedPoints: Int
    public let refundedPointsFromAuthority: Int?
    public let state: ConservationState
    public let note: String

    public init(
        id: String,
        orderNumber: String,
        deductedPoints: Int,
        refundedPointsFromAuthority: Int?,
        state: ConservationState,
        note: String
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.deductedPoints = deductedPoints
        self.refundedPointsFromAuthority = refundedPointsFromAuthority
        self.state = state
        self.note = note
    }

    public var badgeText: String {
        switch state {
        case .conservedByAuthority:
            return "CONSERVED"
        case .awaitingServerReadback:
            return "PENDING_READBACK"
        case .discrepancyDetected:
            return "MISMATCH"
        }
    }

    public var deltaSummaryText: String {
        if let refunded = refundedPointsFromAuthority {
            return "扣减 -\(deductedPoints) · 权威退回 +\(refunded)"
        }
        return "扣减 -\(deductedPoints) · 退回待服务端回读"
    }
}

/// Self-contained snapshot for `I04` points ledger readback and order cancellation points conservation.
public struct AssetPointsAndOrderCancellationSnapshot: Equatable, Sendable {
    public let ownerScope: String
    public let authoritativeBalancePoints: Int?
    public let rows: [AssetPointsCancellationRow]

    public init(
        ownerScope: String,
        authoritativeBalancePoints: Int?,
        rows: [AssetPointsCancellationRow]
    ) {
        self.ownerScope = ownerScope
        self.authoritativeBalancePoints = authoritativeBalancePoints
        self.rows = rows
    }

    public static let defaultConservationSnapshot = AssetPointsAndOrderCancellationSnapshot(
        ownerScope: "member-i04-baseline",
        authoritativeBalancePoints: 1280,
        rows: [
            AssetPointsCancellationRow(
                id: "ord-cancel-101",
                orderNumber: "CY202610200101",
                deductedPoints: 200,
                refundedPointsFromAuthority: 200,
                state: .conservedByAuthority,
                note: "订单取消后经服务端流水回读确认 200 积分原路退回，本地不自造余额"
            ),
            AssetPointsCancellationRow(
                id: "ord-cancel-102",
                orderNumber: "CY202610200102",
                deductedPoints: 150,
                refundedPointsFromAuthority: nil,
                state: .awaitingServerReadback,
                note: "取消请求已受理，积分余额与退回明细等待服务端权威回读 (I04)"
            )
        ]
    )

    public var conservedCount: Int {
        rows.filter { $0.state == .conservedByAuthority }.count
    }

    public var pendingReadbackCount: Int {
        rows.filter { $0.state == .awaitingServerReadback }.count
    }

    public var discrepancyCount: Int {
        rows.filter { $0.state == .discrepancyDetected }.count
    }

    public var isConservationCompliant: Bool {
        discrepancyCount == 0
    }

    public var balanceDisplayText: String {
        if let balance = authoritativeBalancePoints {
            return "\(balance) 积分（服务端权威回读）"
        }
        return "—（待服务端权威回读）"
    }

    public var summaryText: String {
        "守恒确认 \(conservedCount) · 待回读 \(pendingReadbackCount) · 异常 \(discrepancyCount)"
    }
}

/// Renders `I04` points ledger readback and order cancellation points conservation using `Text(verbatim:)` throughout.
@MainActor
public struct AssetPointsAndOrderCancellationSectionView: View {
    public let snapshot: AssetPointsAndOrderCancellationSnapshot

    public init(snapshot: AssetPointsAndOrderCancellationSnapshot = .defaultConservationSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "积分流水与退单守恒 (I04)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isConservationCompliant ? "守恒合规 (I04_OK)" : "存在账目偏差")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isConservationCompliant ? Color.green : Color.red).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isConservationCompliant ? Color.green : Color.red)
                    .accessibilityIdentifier("assetPointsCancellation.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.balanceDisplayText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "当前权威积分余额")
            }
            .accessibilityIdentifier("assetPointsCancellation.balance")

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "退单守恒统计")
            }
            .accessibilityIdentifier("assetPointsCancellation.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.orderNumber)
                            .font(.subheadline.monospaced().weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.state).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.state))
                    }
                    Text(verbatim: row.deltaSummaryText)
                        .font(.caption.monospacedDigit())
                    Text(verbatim: row.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("assetPointsCancellation.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "资产积分与订单取消守恒核查 (I04)")
        }
        .accessibilityIdentifier("assetPointsCancellation.section")
    }

    private func badgeColor(for state: AssetPointsCancellationRow.ConservationState) -> Color {
        switch state {
        case .conservedByAuthority:
            return .green
        case .awaitingServerReadback:
            return .orange
        case .discrepancyDetected:
            return .red
        }
    }
}
