import SwiftUI

/// This view never reads the current /prepare response or initiates a publish/retry.
/// A saved intent remains unknown until its matching authoritative receipt is present.
@MainActor struct ApprovedReleaseSummaryResultView: View {
    @Environment(\.locale) private var locale
    let original: ApprovedTopicReleasePublishFlow.ResultInspection
    let close: (ApprovedTopicReleasePublishFlow.ResultInspection) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(String(localized: LocalizedStringResource("approvedRelease.history.scope", defaultValue: "This is the exact version saved with this request, not the latest draft or preparation. A saved request alone is not proof of publication or player access.", table: "ApprovedReleaseHistory", locale: locale)))
                        .accessibilityIdentifier("approvedRelease.history.scope")
                    Text(verbatim: original.record.command.requestID).textSelection(.enabled)
                        .accessibilityIdentifier("approvedRelease.history.requestID")
                    if let receipt = original.record.receipt {
                        Text(String(receipt.releaseID)).accessibilityIdentifier("approvedRelease.history.releaseID")
                        Text(verbatim: receipt.manifestHash).textSelection(.enabled).accessibilityIdentifier("approvedRelease.history.receiptHash")
                        Text(receipt.currentlyApproved
                            ? String(localized: LocalizedStringResource("approvedRelease.receiptApproved", defaultValue: "Approved at the last server check", locale: locale))
                            : String(localized: LocalizedStringResource("approvedRelease.receiptChanged", defaultValue: "The last server check did not confirm current approval", locale: locale)))
                    } else {
                        Text(String(localized: LocalizedStringResource("approvedRelease.unconfirmed", defaultValue: "The publication result is unconfirmed. The exact request is retained; check its result before creating another request.", locale: locale)))
                            .accessibilityIdentifier("approvedRelease.history.unconfirmed")
                    }
                }
                // Historical media is metadata-only: no new media-read authority is inferred.
                ApprovedReleaseSummarySection(prepared: original.record.prepared, identifierPrefix: "approvedRelease.history")
            }
            .navigationTitle(String(localized: LocalizedStringResource("approvedRelease.history.title", defaultValue: "Saved publication requests", table: "ApprovedReleaseHistory", locale: locale)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: LocalizedStringResource("approvedRelease.close", defaultValue: "Close", locale: locale))) { close(original) }
                        .accessibilityIdentifier("approvedRelease.history.close")
                }
            }
        }
        .onDisappear { close(original) }
    }
}
