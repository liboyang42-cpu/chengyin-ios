import SwiftUI

/// SwiftUI section rendering `CommerceOrderHostSnapshot` per-line fulfilment vs entitlement
/// separation, `UNKNOWN` refund retry lock warning, quote-change confirmation banner,
/// `StaffRedemptionHostEvaluation` preview vs final redemption status, and
/// `SponsoredRewardHostProjection` limited-quantity disclosure & frozen voucher terms.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor public struct CommerceOrderLifecycleSectionView: View {
    public let orderSnapshot: CommerceOrderHostSnapshot
    public let requiresQuoteConfirmation: Bool
    public let redemptionEvaluation: StaffRedemptionHostEvaluation?
    public let rewardProjection: SponsoredRewardHostProjection?

    public init(
        orderSnapshot: CommerceOrderHostSnapshot,
        requiresQuoteConfirmation: Bool = false,
        redemptionEvaluation: StaffRedemptionHostEvaluation? = nil,
        rewardProjection: SponsoredRewardHostProjection? = nil
    ) {
        self.orderSnapshot = orderSnapshot
        self.requiresQuoteConfirmation = requiresQuoteConfirmation
        self.redemptionEvaluation = redemptionEvaluation
        self.rewardProjection = rewardProjection
    }

    public var body: some View {
        Section {
            if requiresQuoteConfirmation {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .foregroundStyle(.orange)
                    Text(verbatim: "报价版本或总价已变更，需消费者显式确认后方可继续")
                        .font(.footnote.weight(.semibold))
                }
                .accessibilityIdentifier("commerceOrderLifecycle.quoteConfirmationBanner")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "订单 \(orderSnapshot.orderID) · 整体投影 \(orderSnapshot.projection.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("commerceOrderLifecycle.orderHeader")
                Text(verbatim: "实物/服务履约与主题权益严格分离统计，互不替代")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if orderSnapshot.requiresServerRefundQuery {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .foregroundStyle(.red)
                    Text(verbatim: "存在 UNKNOWN 状态退款单：已锁定客户端重试，仅允许服务端回查")
                        .font(.footnote)
                }
                .accessibilityIdentifier("commerceOrderLifecycle.unknownRefundLockWarning")
            }

            ForEach(orderSnapshot.lineSummaries, id: \.lineID) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "行 \(line.lineID) (\(line.skuID) · \(line.kind.rawValue))")
                            .font(.footnote.weight(.medium))
                        Spacer()
                        Text(verbatim: line.isLineFulfilled ? "已履约" : "履约 \(line.fulfilledQuantity)/\(line.orderedQuantity)")
                            .font(.caption)
                            .foregroundStyle(line.isLineFulfilled ? .green : .secondary)
                    }
                    Text(verbatim: "主题权益：生效 \(line.activeEntitlementCount) · 已核销 \(line.consumedEntitlementCount)（不计入实物履约）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if line.hasUnknownRefund {
                        Text(verbatim: "该行退款状态 UNKNOWN，禁止客户端重复发起退款")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityIdentifier("commerceOrderLifecycle.line." + line.lineID)
            }

            if let redemption = redemptionEvaluation {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "店员核销校验 · \(Self.scopeDecisionLabel(redemption.scopeDecision))")
                        .font(.footnote.weight(.semibold))
                    Text(verbatim: "预览可确认：\(redemption.previewConfirmable ? "是" : "否") · 凭证格式合规：\(redemption.credentialLooksOpaque ? "是" : "否") · 允许终态确认：\(redemption.canProceedToFinalConfirm ? "是" : "否")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: Self.finalOutcomeLabel(redemption))
                        .font(.caption)
                        .foregroundStyle(redemption.isDuplicateRedemption ? .orange : .primary)
                }
                .accessibilityIdentifier("commerceOrderLifecycle.redemption")
            }

            if let reward = rewardProjection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "赞助奖池项 \(reward.itemID) · \(Self.disclosureLabel(reward.disclosure))")
                        .font(.footnote.weight(.semibold))
                    Text(verbatim: "展示门控：\(reward.isPresentable ? "已开启" : "默认关闭") · 冻结券条款校验：\(reward.voucherReadbackAccepted ? "通过（不可缩期或改版）" : "拒绝回退")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let refusal = reward.bindingRefusal {
                        Text(verbatim: "绑定拒绝原因：\(refusal.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityIdentifier("commerceOrderLifecycle.reward")
            }
        } header: {
            Text(verbatim: "订单行履约、店员核销与赞助奖池状态")
        }
    }

    private static func scopeDecisionLabel(_ decision: MerchantStaffScopeDecision) -> String {
        switch decision {
        case .allowed:
            return "门店与权限域通过"
        case .denied(let reason):
            return "拒绝 (\(reason.rawValue))"
        }
    }

    private static func finalOutcomeLabel(_ evaluation: StaffRedemptionHostEvaluation) -> String {
        switch evaluation.finalOutcome {
        case .redeemed(let receiptID)?:
            return "终态核销完成 · 凭据 \(receiptID)"
        case .alreadyRedeemed(let originalReceiptID)?:
            return "重复扫码幂等返回原凭据 · \(originalReceiptID)"
        case .rejected(let reasonCode)?:
            return "终态核销被拒 · \(reasonCode)"
        case nil:
            return "当前处于预览阶段，尚未提交终态核销"
        }
    }

    private static func disclosureLabel(_ disclosure: SponsoredPoolItem.Disclosure) -> String {
        switch disclosure {
        case .limitedWhileSuppliesLast:
            return "数量有限，发完即止"
        case .guaranteedReserved:
            return "已预留专属保底配额"
        }
    }
}
