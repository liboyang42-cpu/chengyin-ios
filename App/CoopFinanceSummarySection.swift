import SwiftUI

/// 主办分润 header: 已入账分润, 调整待处理, 已执行调整 and the settled-vs-credited
/// explainer (mini-program scene-merchant-profit). Unknown amounts show "—".
struct CoopFinanceSummarySection: View {
    let summary: CoopFinanceSummary
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.s2) {
                Text("member.finance.credited", tableName: "MemberProfile")
                    .font(.subheadline).foregroundStyle(.secondary)
                amount(summary.creditedIncome).font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, Theme.Space.s2)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coopflow.summary.credited")
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
        .labeledContentStyle(CoopFinancialRowStyle())
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

/// Layout only. The existing finance reader, amounts and permissions stay unchanged.
struct CoopOperationListPresentation: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.insetGrouped)
            .listSectionSpacing(Theme.Space.s4)
            .environment(\.defaultMinListRowHeight, 52)
            .font(.body)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Layout only: the original amount, currency, precision and unknown marker are supplied unchanged.
struct CoopFinancialRowStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                vertical(configuration)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s3) {
                        configuration.label
                        Spacer(minLength: Theme.Space.s2)
                        configuration.content.fixedSize(horizontal: true, vertical: false)
                    }
                    vertical(configuration)
                }
            }
        }.accessibilityElement(children: .combine)
    }
    private func vertical(_ configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s2) {
            configuration.label
            configuration.content.multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.s1)
    }
}
