import SwiftUI

/// Immediate submission facts are kept separate from any future authoritative release read.
@MainActor struct ProjectSubmissionEvidenceView: View {
    @Environment(\.locale) private var locale
    let acknowledgment: ProjectEditBundleAcknowledgment
    var currentVerificationConfigured = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: LocalizedStringResource("projectSubmission.historyNotice", defaultValue: "These facts were returned when you submitted. They are not a current approval or immutable release.", locale: locale)))
                .font(.footnote).accessibilityIdentifier("projectSubmission.historyNotice")
            field(String(localized: LocalizedStringResource("projectSubmission.topicID", defaultValue: "Topic ID", locale: locale)), value: String(acknowledgment.topicID), id: "projectSubmission.topicID")
            if let task = acknowledgment.auditTaskID {
                field(String(localized: LocalizedStringResource("projectSubmission.auditTaskID", defaultValue: "Review task ID", locale: locale)), value: String(task), id: "projectSubmission.auditTaskID")
            }
            field(String(localized: LocalizedStringResource("projectSubmission.submittedState", defaultValue: "Review state at submission", locale: locale)), value: stateText, id: "projectSubmission.submittedState")
            field(String(localized: LocalizedStringResource("projectSubmission.legacyVisibility", defaultValue: "Legacy service reported published", locale: locale)),
                  value: acknowledgment.published ? String(localized: LocalizedStringResource("projectSubmission.yes", defaultValue: "Yes", locale: locale)) : String(localized: LocalizedStringResource("projectSubmission.no", defaultValue: "No", locale: locale)),
                  id: "projectSubmission.legacyVisibility")
            Text(String(localized: LocalizedStringResource("projectSubmission.legacyNotice", defaultValue: "The older service can make content visible while review is pending. This flag does not approve a release.", locale: locale)))
                .font(.footnote).foregroundStyle(.secondary)
            field(String(localized: LocalizedStringResource("projectSubmission.templateIDs", defaultValue: "Bundled play template IDs", locale: locale)), value: acknowledgment.bundledTemplateIDs.map(String.init).joined(separator: ", "), id: "projectSubmission.templateIDs")
            if currentVerificationConfigured {
                Text(String(localized: LocalizedStringResource("approvedRelease.separateCheck", defaultValue: "Use the editor's approved-snapshot check for the current server decision. These submission-time facts remain unchanged.", locale: locale)))
                    .font(.footnote)
            } else {
            Text(String(localized: LocalizedStringResource("projectSubmission.releaseUnavailable", defaultValue: "Current approved-release verification is not configured here. Your original submission record is retained.", locale: locale)))
                .font(.footnote).accessibilityIdentifier("projectSubmission.releaseUnavailable")
            }
        }
    }
    private func field(_ label: String, value: String, id: String) -> some View {
        LabeledContent(label) { Text(verbatim: value) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityIdentifier(id)
    }
    private var stateText: String {
        switch acknowledgment.reviewState {
        case "PENDING": return String(localized: LocalizedStringResource("projectSubmission.pending", defaultValue: "Pending", locale: locale))
        case "ESCALATED": return String(localized: LocalizedStringResource("projectSubmission.escalated", defaultValue: "Escalated review", locale: locale))
        case "DRAFT": return String(localized: LocalizedStringResource("projectSubmission.draft", defaultValue: "Draft", locale: locale))
        default: return String(localized: LocalizedStringResource("projectSubmission.notRequired", defaultValue: "Not required by the legacy service", locale: locale))
        }
    }
}

@MainActor struct ProjectSubmissionEvidenceSection: View {
    @ObservedObject var model: ProjectEditModel
    @Environment(\.locale) private var locale
    var body: some View {
        if let acknowledgment = model.submissionEvidence?.bundleAcknowledgment {
            Section(String(localized: LocalizedStringResource("projectSubmission.title", defaultValue: "Submission acknowledgment", locale: locale))) {
                ProjectSubmissionEvidenceView(acknowledgment: acknowledgment, currentVerificationConfigured: model.approvedReleaseReadIsConfigured)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("projectSubmission.history")
            }
        }
    }
}
