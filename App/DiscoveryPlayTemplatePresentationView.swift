import SwiftUI

/// Public-library prose and two-image preview only; the owner namespace has its
/// own view. The injected reader remains disabled by default in normal composition.
@MainActor struct DiscoveryPlayTemplatePresentationView: View {
    let presentation: DiscoveryPlayTemplatePresentation
    let scope: UUID
    let imageReader: any RetainedPublicImageReading

    var body: some View {
        if let publisher = presentation.publisher {
            Section("discovery.template.publisher") {
                Text(verbatim: publisher).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("discovery.template.publisherValue")
            }
        }
        if let count = presentation.useCount {
            Section {
                LabeledContent("discovery.template.useCount", value: String(count))
                    .accessibilityIdentifier("discovery.template.useCount")
            }
        }
        if !presentation.gallerySources.isEmpty {
            Section("discovery.template.images") {
                NativeMediaGalleryEntry(sources: presentation.gallerySources, scope: scope,
                                        titleKey: "discovery.template.images", reader: imageReader)
            }
        }
        if presentation.hasStory {
            Section("discovery.template.story") {
                if let text = presentation.storyText {
                    Text(verbatim: text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("discovery.template.storyText")
                }
                if presentation.storyImage != nil {
                    Text("discovery.template.storyImageInGallery").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("discovery.template.storyImage")
                }
            }
        }
    }
}
