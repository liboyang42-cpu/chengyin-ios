import SwiftUI

@MainActor struct ApprovedReleasePublicationConfirmationView: View {
    @Environment(\.locale) private var locale
    let original: ApprovedTopicReleasePublishFlow.Confirmation
    let cancel: (ApprovedTopicReleasePublishFlow.Confirmation) -> Void
    let confirm: (ApprovedTopicReleasePublishFlow.Confirmation) -> Void
    var body: some View {
        NavigationStack {
            Form {
                ApprovedReleaseSummarySection(prepared: original.prepared, identifierPrefix: "approvedRelease.confirm")
                Section {
                    Button(String(localized: LocalizedStringResource("approvedRelease.confirmCreate", defaultValue: "Publish", locale: locale))) { confirm(original) }
                        .buttonStyle(.questifyPrimary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("approvedRelease.confirm.create")
                }
            }
            .p04LifecycleSurface()
            .navigationTitle(String(localized: LocalizedStringResource("approvedRelease.confirmTitle", defaultValue: "Publish this version?", locale: locale)))
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
