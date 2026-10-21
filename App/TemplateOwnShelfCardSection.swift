import SwiftUI

/// Card facts and the marketplace plan, mounted on the own shelf.
/// The plan is review copy only: `isDispatchable` stays false, so this view
/// has no button and builds no market request. A preview is not a publish.
struct TemplateOwnShelfCardSection: View {
    let facts: TemplateOwnShelfCardFacts?
    let state: TemplateOwnShelfStateProjection
    let rowID: Int
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private var plan: TemplateOwnShelfMarketPlan { TemplateOwnShelfMarketPlan(state) }
    var body: some View {
        if let facts {
            TemplateOwnShelfCardFactLines(facts: facts, zh: zh, rowID: rowID)
        }
        if let action = plan.action, plan.isDispatchable == false {
            Text(LocalizedStringKey(action.labelKey))
                .accessibilityIdentifier("templateOwnShelf.market.plan.\(rowID)")
            Text(verbatim: zh ? "广场操作仅预览，未发送，不是发布" : "Marketplace action is a preview. Nothing is sent. This is not a publish.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("templateOwnShelf.market.held.\(rowID)")
        }
    }
}

private struct TemplateOwnShelfCardFactLines: View {
    let facts: TemplateOwnShelfCardFacts
    let zh: Bool
    let rowID: Int
    var body: some View {
        if let rating = facts.rating {
            LabeledContent("discovery.templateDetail.stat.rating", value: NSDecimalNumber(decimal: rating).stringValue)
                .accessibilityIdentifier("templateOwnShelf.card.rating.\(rowID)")
        }
        if let count = facts.useCount {
            Text(verbatim: zh ? "\(count) 次引用" : "\(count) references")
                .accessibilityIdentifier("templateOwnShelf.card.uses.\(rowID)")
        }
        Text(verbatim: zh ? "\(facts.durationMinutes)分钟" : "\(facts.durationMinutes) min")
            .accessibilityIdentifier("templateOwnShelf.card.duration.\(rowID)")
        if let created = facts.createTime {
            Text(verbatim: created)
                .accessibilityIdentifier("templateOwnShelf.card.created.\(rowID)")
        }
        if let feedback = facts.reviewFeedback {
            Text("discovery.templateDetail.reviewFeedback \(feedback)")
                .accessibilityIdentifier("templateOwnShelf.card.feedback.\(rowID)")
        }
    }
}

/// Source danger copy inside the existing delete review. The confirm control stays the shelf confirm button.
struct TemplateOwnShelfDeleteReviewCopy: View {
    let title: String
    var body: some View {
        Text("templateOwnShelf.delete.title \(title)")
            .accessibilityIdentifier("templateOwnShelf.delete.title")
        Text("templateOwnShelf.delete.body")
            .accessibilityIdentifier("templateOwnShelf.delete.body")
        ForEach(TemplateOwnShelfDeleteCopy.consequenceKeys, id: \.self) { key in
            Text(LocalizedStringKey(key))
        }
        Text("templateOwnShelf.delete.confirm")
            .accessibilityIdentifier("templateOwnShelf.delete.confirm")
    }
}
