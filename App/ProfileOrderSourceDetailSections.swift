import SwiftUI

/// Source scene-member-order-detail sections after 支付明细: 订单进度 timeline, 支付信息
/// (报名信息 when free, paid orders only), 报名人信息 and 凭证与有效期. Presentation only:
/// the enclosing ProfileReadScreen owns the read; nothing here sends a request.
struct ProfileOrderSourceDetailSections: View {
    let order: ProfileOrder
    var body: some View {
        Section("orderLifecycle.timeline.title") {
            ForEach(order.sourceTimeline()) { step in
                ProfileOrderTimelineStepRow(step: step)
            }
            Text("orderLifecycle.timeline.zone").font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("profile.order.detail.timeline")
        if order.showsSourcePaymentInfo {
            Section(LocalizedStringKey(order.isSourceFreeOrder ? "profile.orderParity.section.registrationInfo" : "profile.orderParity.section.paymentInfo")) {
                if let time = order.sourcePaymentTimeText {
                    LabeledContent(LocalizedStringKey(order.isSourceFreeOrder ? "profile.orderParity.registrationTime" : "profile.orders.paymentTime")) {
                        Text(verbatim: time).monospacedDigit()
                    }
                }
                if let key = order.sourcePaymentTypeLabelKey {
                    LabeledContent("profile.orders.paymentType") { Text(LocalizedStringKey(key)) }
                } else {
                    ProfileOptionalRow(key: "profile.orders.paymentType", value: order.paymentTypeLabel)
                }
                if order.showsSourceWechatPay, let amount = order.wechatPaymentAmount {
                    LabeledContent("profile.orderParity.wechatPaid") { Text(verbatim: OwnedOrderMoneyText.string(amount)).monospacedDigit() }
                }
                if order.showsSourcePointPay, let amount = order.pointPaymentAmount {
                    LabeledContent("profile.orderParity.pointsPaid") { Text(verbatim: OwnedOrderMoneyText.string(amount)).monospacedDigit() }
                }
                ProfileOptionalRow(key: "profile.orderParity.transactionID", value: order.detailFacts.transactionID)
            }.accessibilityIdentifier("profile.order.detail.paymentInfo")
        }
        if order.realName?.isEmpty == false || order.phone?.isEmpty == false || order.sourceParticipateDateText != nil {
            Section("profile.orderParity.section.registrant") {
                ProfileOptionalRow(key: "profile.participants.name", value: order.realName)
                ProfileOptionalRow(key: "profile.orderParity.mobile", value: order.phone)
                ProfileOptionalRow(key: "profile.orderParity.registrationDate", value: order.sourceParticipateDateText)
            }
        }
        if order.sourceVerificationTimeText != nil || order.sourceExpiresAtText != nil {
            Section("profile.orderParity.section.voucher") {
                ProfileOptionalRow(key: "profile.orderParity.verifiedAt", value: order.sourceVerificationTimeText)
                ProfileOptionalRow(key: "profile.orderParity.entitlementExpires", value: order.sourceExpiresAtText)
            }
        }
    }
}

private struct ProfileOrderTimelineStepRow: View {
    let step: ProfileOrderTimelineStep
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: step.state == .done ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(step.state == .done ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let label = step.label { Text(verbatim: label) }
                else if let key = step.labelKey { Text(LocalizedStringKey(key)) }
                if let time = step.time { Text(verbatim: time).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                else if let key = step.timeKey { Text(LocalizedStringKey(key)).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.order.timeline.\(step.id)")
    }
}
