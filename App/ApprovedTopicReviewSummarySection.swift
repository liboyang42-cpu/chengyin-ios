import SwiftUI

@MainActor struct ApprovedTopicReviewSummarySection: View {
    @Environment(\.locale) private var locale
    var coverSource: (any OwnedTopicCoverServing)? = nil
    var coverSession: ProjectEditSession? = nil
    var coverContextCurrent: () -> Bool = { false }
    let capture: ApprovedTopicReviewCapture
    var prefix = "topicReview"
    private func id(_ key: String) -> String { prefix + "." + key }
    var body: some View {
        Section {
            field(String(localized: LocalizedStringResource("topicReview.name", defaultValue: "Captured current title", locale: locale)), capture.name, "name")
            field(String(localized: LocalizedStringResource("topicReview.description", defaultValue: "Description", locale: locale)), capture.description, "description")
            field(String(localized: LocalizedStringResource("topicReview.topic", defaultValue: "Topic ID", locale: locale)), String(capture.topicID), "topic")
            field(String(localized: LocalizedStringResource("topicReview.observedTask", defaultValue: "Previously submitted review task", locale: locale)), String(capture.observedAuditTaskID), "observedTask")
            field(String(localized: LocalizedStringResource("topicReview.observedVersion", defaultValue: "Observed review task version", locale: locale)), String(capture.observedAuditTaskVersion), "observedVersion")
            field(String(localized: LocalizedStringResource("topicReview.sourceVersion", defaultValue: "Captured source version", locale: locale)), String(capture.sourceConfigVersion), "sourceVersion")
            field(String(localized: LocalizedStringResource("topicReview.snapshotHash", defaultValue: "Captured snapshot SHA-256", locale: locale)), capture.snapshotHash, "snapshotHash")
            field(String(localized: LocalizedStringResource("topicReview.categories", defaultValue: "Captured category IDs", locale: locale)), capture.categoryIDs, "categories")
            field(String(localized: LocalizedStringResource("topicReview.cover", defaultValue: "Cover reference (not fetched)", locale: locale)), capture.coverReference, "cover")
            Text(String(localized: LocalizedStringResource("topicReview.summaryLimits", defaultValue: "This is the captured server content for a review request. It is not approved or released. Answers and private guide text remain server-side; media proof and publication eligibility are not established by this summary.", locale: locale)))
                .font(.footnote).accessibilityIdentifier(id("limits"))
        }
        if let cover = capture.selectedCover {
            ApprovedTopicSelectedCoverSection(cover: cover, prefix: prefix, approved: false, source: coverSource, session: coverSession, parentCurrent: coverContextCurrent)
        }
        if !capture.selectedMerchantSources.isEmpty {
            Section {
                Text(String(localized: LocalizedStringResource("topicReview.sources.captured", defaultValue: "These exact merchant confirmations are included in this review request. Approval is checked separately.", table: "ApprovedMerchantReviewSources", locale: locale)))
                ForEach(capture.selectedMerchantSources) { source in
                    field(String(localized: LocalizedStringResource("topicReview.sources.template", defaultValue: "Merchant draft", table: "ApprovedMerchantReviewSources", locale: locale)), "#\(source.memberTemplateID)", "source.template.\(source.memberTemplateID)")
                    field(String(localized: LocalizedStringResource("topicReview.sources.confirmation", defaultValue: "Saved confirmation", table: "ApprovedMerchantReviewSources", locale: locale)), "#\(source.merchantConfirmation.sourceID)", "source.confirmation.\(source.memberTemplateID)")
                }
            }
        }
        ForEach(Array(capture.chapters.enumerated()), id: \.element.id) { ci, chapter in
            Section {
                field(String(localized: LocalizedStringResource("topicReview.chapter", defaultValue: "Chapter", locale: locale)), chapter.name, "chapter.\(ci).name")
                field(String(localized: LocalizedStringResource("topicReview.description", defaultValue: "Description", locale: locale)), chapter.description, "chapter.\(ci).description")
                ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { bi, block in
                    if let node = block.node {
                        Group {
                            field(String(localized: LocalizedStringResource("topicReview.node", defaultValue: "Node", locale: locale)), node.name, "chapter.\(ci).block.\(bi).name")
                            field(String(localized: LocalizedStringResource("topicReview.description", defaultValue: "Description", locale: locale)), node.description, "chapter.\(ci).block.\(bi).description")
                            field(String(localized: LocalizedStringResource("topicReview.address", defaultValue: "Address", locale: locale)), node.address, "chapter.\(ci).block.\(bi).address")
                            field(String(localized: LocalizedStringResource("topicReview.image", defaultValue: "Image reference (not fetched)", locale: locale)), node.imageReference, "chapter.\(ci).block.\(bi).image")
                            field(String(localized: LocalizedStringResource("topicReview.nodeTime", defaultValue: "Node time", locale: locale)), String(node.nodeTime), "chapter.\(ci).block.\(bi).time")
                            field(String(localized: LocalizedStringResource("topicReview.template", defaultValue: "Member play template ID", locale: locale)), String(node.templateID), "chapter.\(ci).block.\(bi).template")
                            field(String(localized: LocalizedStringResource("topicReview.templateTitle", defaultValue: "Captured template title", locale: locale)), node.templateTitle, "chapter.\(ci).block.\(bi).templateTitle")
                            field(String(localized: LocalizedStringResource("topicReview.templateCategory", defaultValue: "Template category ID", locale: locale)), node.templateCategoryID.map { String($0) }, "chapter.\(ci).block.\(bi).templateCategory")
                            field(String(localized: LocalizedStringResource("topicReview.templateActivities", defaultValue: "Template activity category IDs", locale: locale)), node.templateCategoryIDs, "chapter.\(ci).block.\(bi).templateActivities")
                            field(String(localized: LocalizedStringResource("topicReview.templateHash", defaultValue: "Template snapshot SHA-256", locale: locale)), node.templateContentHash, "chapter.\(ci).block.\(bi).templateHash")
                            field(String(localized: LocalizedStringResource("topicReview.question", defaultValue: "Question", locale: locale)), node.questionText, "chapter.\(ci).block.\(bi).question")
                            field(String(localized: LocalizedStringResource("topicReview.rules", defaultValue: "Rule instructions", locale: locale)), node.ruleInstructions, "chapter.\(ci).block.\(bi).rules")
                        }
                    } else { Text(verbatim: block.content ?? "").accessibilityIdentifier(id("chapter.\(ci).block.\(bi).text")) }
                }
            }
        }
    }
    private func field(_ label: String, _ value: String?, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value ?? String(localized: LocalizedStringResource("topicReview.missing", defaultValue: "Not supplied", locale: locale)))
                .textSelection(.enabled).accessibilityIdentifier(id(key))
        }
    }
}
