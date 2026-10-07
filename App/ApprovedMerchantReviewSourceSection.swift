import SwiftUI

/// A choice of exact historical confirmations; the server captures current evidence next.
@MainActor struct ApprovedMerchantReviewSourceSection: View {
    @ObservedObject var model: ApprovedTopicReviewReadModel
    let presentation: ApprovedTopicReviewFlow.SourceSelectionPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            Text(String(localized: LocalizedStringResource("topicReview.sources.explanation", defaultValue: "Choose the saved shop confirmation for each merchant draft. The server will check the current content, shop facts and ownership before preparing your review request.", table: "ApprovedMerchantReviewSources", locale: locale)))
                .accessibilityIdentifier("topicReview.sources.explanation")
        }
        ForEach(presentation.choices.groups) { group in
            Section {
                Text(String(localized: LocalizedStringResource("topicReview.sources.template", defaultValue: "Merchant draft", table: "ApprovedMerchantReviewSources", locale: locale)) + " #\(group.memberTemplateID)")
                if group.confirmations.isEmpty {
                    Text(String(localized: LocalizedStringResource("topicReview.sources.missing", defaultValue: "This draft has no verified saved shop confirmation. Confirm its facts before requesting a review.", table: "ApprovedMerchantReviewSources", locale: locale)))
                        .accessibilityIdentifier("topicReview.sources.missing.\(group.memberTemplateID)")
                }
                ForEach(group.confirmations) { choice in
                    Button { model.selectSource(choice, from: presentation) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: choice.title ?? "#\(group.memberTemplateID)")
                            Text(String(localized: LocalizedStringResource("topicReview.sources.confirmation", defaultValue: "Saved confirmation", table: "ApprovedMerchantReviewSources", locale: locale)) + " #\(choice.selection.merchantConfirmation.sourceID)")
                            Text(Date(timeIntervalSince1970: Double(choice.confirmedAtEpochMillis) / 1000), style: .date).font(.caption)
                            if model.flow.selectedSources[group.memberTemplateID] == choice.selection {
                                Label(String(localized: LocalizedStringResource("topicReview.sources.selected", defaultValue: "Selected", table: "ApprovedMerchantReviewSources", locale: locale)), systemImage: "checkmark.circle.fill")
                            }
                        }
                    }.buttonStyle(.borderless).accessibilityIdentifier("topicReview.sources.choose.\(choice.selection.merchantConfirmation.sourceID)")
                }
                if group.hasOlderConfirmations {
                    Text(String(localized: LocalizedStringResource("topicReview.sources.older", defaultValue: "Showing the eight most recent saved confirmations for this draft. Older confirmations are not shown here.", table: "ApprovedMerchantReviewSources", locale: locale))).font(.footnote)
                }
            }
        }
        Section {
            Button(String(localized: LocalizedStringResource("topicReview.sources.capture", defaultValue: "Check selected sources and prepare review", table: "ApprovedMerchantReviewSources", locale: locale))) { model.captureSources(presentation) }
                .buttonStyle(.borderless).disabled(!model.flow.canCaptureSources(presentation)).accessibilityIdentifier("topicReview.sources.capture")
        }
    }
}
