import SwiftUI

/// 主办分润 header: 已入账分润, 调整待处理, 已执行调整 and the settled-vs-credited
/// explainer (mini-program scene-merchant-profit). Unknown amounts show "—".
struct CoopFinanceSummarySection: View {
    let summary: CoopFinanceSummary
    var body: some View {
        Section {
            LabeledContent { amount(summary.creditedIncome) } label: {
                Text("member.finance.credited", tableName: "MemberProfile")
            }.accessibilityIdentifier("coopflow.summary.credited")
            if summary.showsPendingAdjustment {
                LabeledContent { amount(summary.pendingAdjustment) } label: {
                    Text("member.finance.pendingAdjustment", tableName: "MemberProfile")
                }.accessibilityIdentifier("coopflow.summary.pending")
            }
            if summary.showsExecutedAdjustment {
                LabeledContent { amount(summary.executedAdjustment, negative: true) } label: {
                    Text("member.finance.executedAdjustment", tableName: "MemberProfile")
                }.accessibilityIdentifier("coopflow.summary.executed")
            }
            if let reason = summary.pendingReason {
                Text(verbatim: reason).font(.footnote).foregroundStyle(.secondary)
            }
        } footer: {
            Text("member.finance.explainer", tableName: "MemberProfile")
        }
    }
    private func amount(_ value: Decimal?, negative: Bool = false) -> Text {
        guard let value else { return Text(verbatim: "—") }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        let text = formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
        return Text(verbatim: (negative ? "−¥" : "¥") + text).monospacedDigit()
    }
}
