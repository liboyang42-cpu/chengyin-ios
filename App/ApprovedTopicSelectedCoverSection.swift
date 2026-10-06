import SwiftUI

/// Immutable captured metadata shared by the review request and exact approved preparation.
@MainActor struct ApprovedTopicSelectedCoverSection: View {
    @Environment(\.locale) private var locale
    let cover: ApprovedTopicSelectedCover
    let prefix: String
    let approved: Bool
    var source: (any OwnedTopicCoverServing)? = nil
    var session: ProjectEditSession? = nil
    var parentCurrent: () -> Bool = { false }
    @StateObject private var imageController = OwnedTopicCoverImagePresentation()
    private func id(_ key: String) -> String { prefix + "." + key }
    var body: some View {
        let originalImage = imageController.presentation
        Section {
                if !cover.permitsReviewRequest {
                    Text(String(localized: LocalizedStringResource("topicReview.coverSelection.blocked", defaultValue: "The selected cover is available only to its author. Its public-player binding is not configured, so this capture cannot be sent for review or published. The saved legacy cover reference remains unverified.", locale: locale)))
                        .accessibilityIdentifier(id("selectedCover.blocked"))
                } else if approved {
                    Text(String(localized: LocalizedStringResource("topicReview.coverSelection.approvedBinding", defaultValue: "This selected asset is frozen in the captured approved manifest. New players can read it only through their authorized, pinned run. The author-only locator is not a public image URL.", locale: locale)))
                        .accessibilityIdentifier(id("selectedCover.approvedBinding"))
                } else {
                    Text(String(localized: LocalizedStringResource("topicReview.coverSelection.reviewBinding", defaultValue: "This captured asset will replace the legacy cover only in a newly approved release. This request still needs review. Player access requires an authorized run pinned to that release.", locale: locale)))
                        .accessibilityIdentifier(id("selectedCover.reviewBinding"))
                }
                field(String(localized: LocalizedStringResource("topicReview.coverSelection.asset", defaultValue: "Selected asset ID", locale: locale)), cover.assetID, "selectedCover.asset")
                field(String(localized: LocalizedStringResource("topicReview.coverSelection.version", defaultValue: "Asset source version", locale: locale)), cover.sourceVersion, "selectedCover.version")
                field(String(localized: LocalizedStringResource("topicReview.coverSelection.hash", defaultValue: "Verified asset byte SHA-256", locale: locale)), cover.contentHash, "selectedCover.hash")
                field(String(localized: LocalizedStringResource("topicReview.coverSelection.selection", defaultValue: "Captured selection revision", locale: locale)), String(cover.selectionVersion), "selectedCover.selection")
                field(String(localized: LocalizedStringResource("topicReview.coverSelection.slot", defaultValue: "Captured CONTENT ownership record", locale: locale)), String(cover.contentSlotID), "selectedCover.slot")
                if let source, let session {
                    Button(String(localized: LocalizedStringResource("ownedCover.openImage", defaultValue: "Read this selected cover image", locale: locale))) {
                        imageController.open(asset: cover.ownedAsset, session: session, source: source, parentCurrent: parentCurrent)
                    }.buttonStyle(.borderless).disabled(!parentCurrent() || !source.permits(.readAsset, session: session))
                        .accessibilityIdentifier(id("selectedCover.openImage"))
                }
                Text(String(localized: LocalizedStringResource("topicReview.coverSelection.notLoaded", defaultValue: "Image bytes are not loaded by this record view. The author-only locator is not opened as an arbitrary URL.", locale: locale)))
                    .font(.footnote).accessibilityIdentifier(id("selectedCover.notLoaded"))
            } header: { Text(String(localized: LocalizedStringResource("topicReview.coverSelection.title", defaultValue: "Captured selected cover", locale: locale))) }
        .sheet(item: imageController.binding(originalImage)) { original in
            OwnedTopicCoverImageView(original: original) { imageController.close(original) }
        }
        .onDisappear { if let originalImage { imageController.close(originalImage) } }
    }
    private func field(_ label: String, _ value: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled).accessibilityIdentifier(id(key))
        }
    }
}
