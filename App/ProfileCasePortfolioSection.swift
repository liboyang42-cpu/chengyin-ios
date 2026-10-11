import SwiftUI

/// Reuses the existing origin-reviewed anonymous viewer. No upload or URL entry capability.
@MainActor struct ProfileCasePortfolioSection: View {
    let casePics: String
    let scope: UUID
    let reader: (any RetainedPublicImageReading)?
    private var portfolio: ProfileCasePortfolio { .init(casePics: casePics) }
    var body: some View {
        Section("profile.case.images") {
            if portfolio.images.isEmpty {
                ContentUnavailableView("profile.case.imagesEmpty", systemImage: "photo.on.rectangle")
                    .accessibilityIdentifier("profile.case.imagesEmpty")
            } else {
                NativeMediaGalleryEntry(sources: portfolio.images, scope: scope,
                    titleKey: "profile.case.images", reader: reader)
                if portfolio.omittedImageCount > 0 {
                    LabeledContent("profile.case.imagesOmitted", value: String(portfolio.omittedImageCount))
                }
            }
            Text("profile.case.imagesReadOnly").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
