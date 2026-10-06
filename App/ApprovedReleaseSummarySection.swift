import SwiftUI

/// Reused by current preparation and publication confirmation; both render the captured value passed in.
@MainActor struct ApprovedReleaseSummarySection: View {
    @Environment(\.locale) private var locale
    var coverSource: (any OwnedTopicCoverServing)? = nil
    var coverSession: ProjectEditSession? = nil
    var coverContextCurrent: () -> Bool = { false }
    let prepared: ApprovedTopicReleasePreparation
    var identifierPrefix = "approvedRelease"
    var body: some View { summary(prepared) }
    private func identifier(_ suffix: String) -> String { identifierPrefix + "." + suffix }
    @ViewBuilder private func summary(_ prepared: ApprovedTopicReleasePreparation) -> some View {
        Section {
            field(String(localized: LocalizedStringResource("approvedRelease.name", defaultValue: "Approved title", locale: locale)), prepared.name, identifier("name"))
            field(String(localized: LocalizedStringResource("approvedRelease.description", defaultValue: "Description", locale: locale)), prepared.description, identifier("description"))
            field(String(localized: LocalizedStringResource("approvedRelease.topic", defaultValue: "Topic ID", locale: locale)), String(prepared.topicID), identifier("topic"))
            field(String(localized: LocalizedStringResource("approvedRelease.auditTask", defaultValue: "Review task ID", locale: locale)), String(prepared.auditTaskID), identifier("auditTask"))
            field(String(localized: LocalizedStringResource("approvedRelease.auditVersion", defaultValue: "Review task version", locale: locale)), String(prepared.auditTaskVersion), identifier("auditVersion"))
            field(String(localized: LocalizedStringResource("approvedRelease.sourceVersion", defaultValue: "Source content version", locale: locale)), String(prepared.sourceConfigVersion), identifier("sourceVersion"))
            field(String(localized: LocalizedStringResource("approvedRelease.headRevision", defaultValue: "Captured release-head revision", locale: locale)), String(prepared.headRevision), identifier("headRevision"))
            field(String(localized: LocalizedStringResource("approvedRelease.categories", defaultValue: "Captured category IDs", locale: locale)), prepared.categoryIDs, identifier("categories"))
            field(String(localized: LocalizedStringResource("approvedRelease.manifestHash", defaultValue: "Full manifest SHA-256", locale: locale)), prepared.manifestHash, identifier("manifestHash"))
            field(String(localized: LocalizedStringResource("approvedRelease.auditHash", defaultValue: "Audit snapshot SHA-256", locale: locale)), prepared.auditSnapshotHash, identifier("auditHash"))
            Text(String(localized: LocalizedStringResource("approvedRelease.serverOnly", defaultValue: "Answer values and private guide text remain server-side. The hashes bind the full captured content, including fields omitted from this readable summary.", locale: locale)))
                .font(.footnote)
        }
        if let cover = prepared.selectedCover {
            ApprovedTopicSelectedCoverSection(cover: cover, prefix: identifierPrefix, approved: true, source: coverSource, session: coverSession, parentCurrent: coverContextCurrent)
        }
        ForEach(Array(prepared.chapters.enumerated()), id: \.element.id) { ci, chapter in
            Section {
                field(String(localized: LocalizedStringResource("approvedRelease.chapter", defaultValue: "Chapter", locale: locale)), chapter.name, identifier("chapter.\(ci).name"))
                field(String(localized: LocalizedStringResource("approvedRelease.description", defaultValue: "Description", locale: locale)), chapter.description, identifier("chapter.\(ci).description"))
                ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { bi, block in
                    if let node = block.node {
                        Group {
                            field(String(localized: LocalizedStringResource("approvedRelease.node", defaultValue: "Node", locale: locale)), node.name, identifier("chapter.\(ci).block.\(bi).name"))
                            field(String(localized: LocalizedStringResource("approvedRelease.description", defaultValue: "Description", locale: locale)), node.description, identifier("chapter.\(ci).block.\(bi).description"))
                            field(String(localized: LocalizedStringResource("approvedRelease.address", defaultValue: "Address", locale: locale)), node.address, identifier("chapter.\(ci).block.\(bi).address"))
                            field(String(localized: LocalizedStringResource("approvedRelease.imageReference", defaultValue: "Image reference (not fetched)", locale: locale)), node.imageReference, identifier("chapter.\(ci).block.\(bi).image"))
                            field(String(localized: LocalizedStringResource("approvedRelease.nodeTime", defaultValue: "Node time", locale: locale)), String(node.nodeTime), identifier("chapter.\(ci).block.\(bi).time"))
                            field(String(localized: LocalizedStringResource("approvedRelease.templateID", defaultValue: "Member play template ID", locale: locale)), String(node.templateID), identifier("chapter.\(ci).block.\(bi).template"))
                            field(String(localized: LocalizedStringResource("approvedRelease.templateTitle", defaultValue: "Captured template title", locale: locale)), node.templateTitle, identifier("chapter.\(ci).block.\(bi).templateTitle"))
                            field(String(localized: LocalizedStringResource("approvedRelease.templateCategoryID", defaultValue: "Captured template category ID", locale: locale)), node.templateCategoryID.map { String($0) }, identifier("chapter.\(ci).block.\(bi).templateCategory"))
                            field(String(localized: LocalizedStringResource("approvedRelease.templateActivityCategories", defaultValue: "Captured template activity category IDs", locale: locale)), node.templateCategoryIDs, identifier("chapter.\(ci).block.\(bi).templateCategories"))
                            field(String(localized: LocalizedStringResource("approvedRelease.templateHash", defaultValue: "Template snapshot SHA-256", locale: locale)), node.templateContentHash, identifier("chapter.\(ci).block.\(bi).templateHash"))
                            field(String(localized: LocalizedStringResource("approvedRelease.question", defaultValue: "Question", locale: locale)), node.questionText, identifier("chapter.\(ci).block.\(bi).question"))
                            field(String(localized: LocalizedStringResource("approvedRelease.rules", defaultValue: "Rule instructions", locale: locale)), node.ruleInstructions, identifier("chapter.\(ci).block.\(bi).rules"))
                        }
                    } else {
                        Text(verbatim: block.content ?? "").accessibilityIdentifier(identifier("chapter.\(ci).block.\(bi).text"))
                    }
                }
            }
        }
    }
    private func field(_ title: String, _ value: String?, _ identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value ?? String(localized: LocalizedStringResource("approvedRelease.missing", defaultValue: "Not supplied", locale: locale)))
                .textSelection(.enabled).accessibilityIdentifier(identifier)
        }
    }
}
