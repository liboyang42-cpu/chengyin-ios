import SwiftUI

/// Actions retain the displayed review ID, rather than looking up a later result by field name.
@MainActor struct MerchantTemplateSuggestionReviewPanel: View {
    let review: MerchantTemplateSuggestionReview
    let canChange: (MerchantTemplateSuggestionReview.Action, MerchantTemplateSuggestionReview.Change) -> Bool
    let canReject: (MerchantTemplateSuggestionReview.Action) -> Bool
    let change: (MerchantTemplateSuggestionReview.Action, MerchantTemplateSuggestionReview.Change) -> Void
    let reject: (MerchantTemplateSuggestionReview.Action) -> Void
    var body: some View {
        Section("merchant.assist.diff.title") {
            Text("merchant.assist.diff.boundary").font(.footnote)
            ForEach(review.suggestions) { suggestion in
                let action = review.action(for: suggestion)
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(suggestion.field.titleKey)).font(.headline)
                    Text("merchant.assist.diff.original").font(.caption)
                    if suggestion.original.isEmpty { Text("merchant.assist.diff.empty").foregroundStyle(.secondary) }
                    else { Text(verbatim: suggestion.original).textSelection(.enabled) }
                    Text("merchant.assist.diff.proposed").font(.caption)
                    Text(verbatim: suggestion.proposed).textSelection(.enabled)
                    Text(LocalizedStringKey("merchant.assist.diff.state." + suggestion.state.rawValue))
                        .accessibilityIdentifier("merchant.assist.diff.state." + suggestion.field.rawValue)
                    HStack {
                        if suggestion.state == .applied {
                            Button("merchant.assist.diff.undo") { change(action, .undo) }
                                .buttonStyle(.borderless).disabled(!canChange(action, .undo))
                                .accessibilityIdentifier("merchant.assist.diff.undo." + suggestion.field.rawValue)
                        } else {
                            Button("merchant.assist.diff.accept") { change(action, .accept) }
                                .buttonStyle(.borderless).disabled(!canChange(action, .accept))
                                .accessibilityIdentifier("merchant.assist.diff.accept." + suggestion.field.rawValue)
                        }
                        Button("merchant.assist.diff.reject") { reject(action) }
                            .buttonStyle(.borderless).disabled(!canReject(action))
                            .accessibilityIdentifier("merchant.assist.diff.reject." + suggestion.field.rawValue)
                    }
                    if suggestion.state != .rejected && !canChange(action, suggestion.state == .applied ? .undo : .accept) {
                        Text("merchant.assist.diff.blocked").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
