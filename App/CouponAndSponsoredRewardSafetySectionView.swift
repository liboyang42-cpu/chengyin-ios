import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 4 coupon & sponsored reward safety pillars:
/// `w2-05` coupon runtime journey, `G-W07` pool disclosure, frozen voucher readback protection,
/// and fail-closed `SponsoredRewardCapabilities`.
public struct CouponSponsoredSafetyRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case w205CouponRuntimeJourney = "w2-05"
        case gW07PoolDisclosure = "G-W07-POOL"
        case frozenVoucherReadbackProtection = "FROZEN-VOUCHER"
        case sponsoredRewardCapabilitiesGate = "SPONSORED-CAPABILITIES"
    }

    public let id: String
    public let kind: PillarKind
    public let title: String
    public let summary: String
    public let evidenceText: String
    public let isCompliant: Bool

    public init(
        id: String? = nil,
        kind: PillarKind,
        title: String,
        summary: String,
        evidenceText: String,
        isCompliant: Bool
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.summary = summary
        self.evidenceText = evidenceText
        self.isCompliant = isCompliant
    }
}

/// Self-contained snapshot for `w2-05` coupon runtime journey, `G-W07` pool disclosure,
/// frozen voucher readback protection, and fail-closed `SponsoredRewardCapabilities`.
public struct CouponAndSponsoredRewardSafetySnapshot: Equatable, Sendable {
    public let couponRuntimeReadOnlyJourneyVerified: Bool
    public let sponsoredPoolDisclosureComplete: Bool
    public let frozenVoucherReadbackProtected: Bool
    public let sponsoredRewardCapabilitiesFailClosed: Bool
    public let rows: [CouponSponsoredSafetyRow]

    public init(
        couponRuntimeReadOnlyJourneyVerified: Bool,
        sponsoredPoolDisclosureComplete: Bool,
        frozenVoucherReadbackProtected: Bool,
        sponsoredRewardCapabilitiesFailClosed: Bool,
        rows: [CouponSponsoredSafetyRow]
    ) {
        self.couponRuntimeReadOnlyJourneyVerified = couponRuntimeReadOnlyJourneyVerified
        self.sponsoredPoolDisclosureComplete = sponsoredPoolDisclosureComplete
        self.frozenVoucherReadbackProtected = frozenVoucherReadbackProtected
        self.sponsoredRewardCapabilitiesFailClosed = sponsoredRewardCapabilitiesFailClosed
        self.rows = rows
    }

    public var compliantRowCount: Int {
        rows.filter(\.isCompliant).count
    }

    public var isAllCompliant: Bool {
        couponRuntimeReadOnlyJourneyVerified &&
            sponsoredPoolDisclosureComplete &&
            frozenVoucherReadbackProtected &&
            sponsoredRewardCapabilitiesFailClosed &&
            Set(rows.map(\.kind)) == Set(CouponSponsoredSafetyRow.PillarKind.allCases) &&
            rows.allSatisfy(\.isCompliant)
    }

    public static let compliantSample = CouponAndSponsoredRewardSafetySnapshot(
        couponRuntimeReadOnlyJourneyVerified: true,
        sponsoredPoolDisclosureComplete: true,
        frozenVoucherReadbackProtected: true,
        sponsoredRewardCapabilitiesFailClosed: true,
        rows: [
            CouponSponsoredSafetyRow(
                kind: .w205CouponRuntimeJourney,
                title: "w2-05 卡券运行态只读核验链路",
                summary: "卡券列表、详情、核销码展示与状态回读严格遵循服务端事实，不伪造本地核销成功",
                evidenceText: "couponRuntime.readOnlyConfirm 已挂载 · 禁止本地自造核销回执",
                isCompliant: true
            ),
            CouponSponsoredSafetyRow(
                kind: .gW07PoolDisclosure,
                title: "G-W07 赞助奖池透明披露",
                summary: "完整展示赞助商主体、奖池余量、使用门槛、有效期与非现金兑换声明",
                evidenceText: "赞助方与有效期齐备 · 非现金声明已固定展示",
                isCompliant: true
            ),
            CouponSponsoredSafetyRow(
                kind: .frozenVoucherReadbackProtection,
                title: "冻结券与未知结果回读保护",
                summary: "处于 FROZEN 或网络结果未知的券码立即锁定操作按钮，仅允许服务端只读刷新核对",
                evidenceText: "FROZEN 状态禁止重复提交 · 仅提供重新回读",
                isCompliant: true
            ),
            CouponSponsoredSafetyRow(
                kind: .sponsoredRewardCapabilitiesGate,
                title: "SponsoredRewardCapabilities 默认关闭围栏",
                summary: "未审阅的赞助奖池申领与核销写接口默认全部关闭，不触发任何网络写请求",
                evidenceText: "SponsoredRewardCapabilities.disabled = true",
                isCompliant: true
            )
        ]
    )
}

@MainActor
public struct CouponAndSponsoredRewardSafetySectionView: View {
    public let snapshot: CouponAndSponsoredRewardSafetySnapshot

    public init(snapshot: CouponAndSponsoredRewardSafetySnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "卡券运行态与赞助奖池安全审计")
                    .font(.headline)
                    .accessibilityIdentifier("couponSponsoredSafety.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("couponSponsoredSafety.overallStatus")

                Text(verbatim: Self.couponJourneyStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("couponSponsoredSafety.couponJourneyStatus")

                Text(verbatim: Self.poolDisclosureStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("couponSponsoredSafety.poolDisclosureStatus")

                Text(verbatim: Self.frozenVoucherStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("couponSponsoredSafety.frozenVoucherStatus")

                Text(verbatim: Self.capabilitiesGateStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("couponSponsoredSafety.capabilitiesGateStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无卡券与赞助奖池安全检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("couponSponsoredSafety.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    CouponSponsoredSafetyRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("couponSponsoredSafety.section")
    }

    public static func overallStatusText(for snapshot: CouponAndSponsoredRewardSafetySnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：卡券与赞助奖池四大安全围栏全部生效（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未生效的卡券或赞助奖池安全围栏（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
    }

    public static func couponJourneyStatusText(for snapshot: CouponAndSponsoredRewardSafetySnapshot) -> String {
        snapshot.couponRuntimeReadOnlyJourneyVerified
            ? "w2-05 卡券运行态：只读回读与核销状态核验已就绪"
            : "w2-05 卡券运行态：只读回读或核销状态核验未就绪"
    }

    public static func poolDisclosureStatusText(for snapshot: CouponAndSponsoredRewardSafetySnapshot) -> String {
        snapshot.sponsoredPoolDisclosureComplete
            ? "G-W07 奖池披露：赞助主体、有效期与非现金声明已齐备"
            : "G-W07 奖池披露：赞助主体或非现金声明缺失"
    }

    public static func frozenVoucherStatusText(for snapshot: CouponAndSponsoredRewardSafetySnapshot) -> String {
        snapshot.frozenVoucherReadbackProtected
            ? "冻结券回读保护：FROZEN 锁定与防重放回读已启用"
            : "冻结券回读保护：FROZEN 锁定或防重放回读未启用"
    }

    public static func capabilitiesGateStatusText(for snapshot: CouponAndSponsoredRewardSafetySnapshot) -> String {
        snapshot.sponsoredRewardCapabilitiesFailClosed
            ? "SponsoredRewardCapabilities：默认关闭（Fail-Closed）已核验"
            : "SponsoredRewardCapabilities：存在未授权开启项"
    }
}

@MainActor
private struct CouponSponsoredSafetyRowView: View {
    let row: CouponSponsoredSafetyRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isCompliant ? "已生效" : "待修复")
                    .font(.caption)
                    .foregroundStyle(row.isCompliant ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "核验凭据：\(row.evidenceText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("couponSponsoredSafety.row")
    }
}
