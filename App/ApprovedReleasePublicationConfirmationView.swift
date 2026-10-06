import SwiftUI

@MainActor struct ApprovedReleasePublicationConfirmationView: View {
    @Environment(\.locale) private var locale
    let original: ApprovedTopicReleasePublishFlow.Confirmation
    let cancel: (ApprovedTopicReleasePublishFlow.Confirmation) -> Void
    let confirm: (ApprovedTopicReleasePublishFlow.Confirmation) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Text(String(localized: LocalizedStringResource("approvedRelease.confirmScope", defaultValue: "Confirm the exact server-approved snapshot below. The server will check this audit version, manifest hash and release-head revision again before allocating an immutable release.", locale: locale)))
                    .accessibilityIdentifier("approvedRelease.confirm.scope")
                ApprovedReleaseSummarySection(prepared: original.prepared, identifierPrefix: "approvedRelease.confirm")
                Section {
                    Button(String(localized: LocalizedStringResource("approvedRelease.confirmCreate", defaultValue: "Create this immutable release", locale: locale))) { confirm(original) }
                        .buttonStyle(.borderless).accessibilityIdentifier("approvedRelease.confirm.create")
                }
            }
            .navigationTitle(String(localized: LocalizedStringResource("approvedRelease.confirmTitle", defaultValue: "Confirm release version", locale: locale)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: LocalizedStringResource("approvedRelease.confirmCancel", defaultValue: "Cancel", locale: locale))) { cancel(original) }
                        .accessibilityIdentifier("approvedRelease.confirm.cancel")
                }
            }
        }
        .onDisappear { cancel(original) }
    }
}
