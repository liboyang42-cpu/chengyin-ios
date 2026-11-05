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
        // The marketplace plan is never dispatchable here, so it isn't shown: no dead action, no "preview only" caption.
    }
}

private struct TemplateOwnShelfCardFactLines: View {
    @Environment(\.locale) private var locale
    let facts: TemplateOwnShelfCardFacts
    let zh: Bool
    let rowID: Int
    var body: some View {
        if let rating = facts.rating {
            LabeledContent("discovery.templateDetail.stat.rating", value: NSDecimalNumber(decimal: rating).stringValue)
                .accessibilityIdentifier("templateOwnShelf.card.rating.\(rowID)")
        }
        if let count = facts.useCount {
            fact("templateOwnShelf.card.useCount", String(count), id: "templateOwnShelf.card.uses.\(rowID)")
        }
        if let duration = facts.durationMinutes {
            fact("templateOwnShelf.card.durationLabel", appLocalized("templateOwnShelf.card.minutes \(duration)", locale: locale), id: "templateOwnShelf.card.duration.\(rowID)")
        }
        if let created = facts.createTime {
            fact("templateOwnShelf.card.createdLabel", created, id: "templateOwnShelf.card.created.\(rowID)")
        }
        if let feedback = facts.reviewFeedback {
            Text("discovery.templateDetail.reviewFeedback \(feedback)")
                .accessibilityIdentifier("templateOwnShelf.card.feedback.\(rowID)")
        }
    }
    /// Label left, value right; the value keeps the row's identifier.
    private func fact(_ title: LocalizedStringKey, _ value: String, id: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).foregroundStyle(.secondary).accessibilityIdentifier(id)
        }
    }
}
