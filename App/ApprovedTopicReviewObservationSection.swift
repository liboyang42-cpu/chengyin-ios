import SwiftUI

@MainActor struct ApprovedTopicReviewObservationSection: View {
    @ObservedObject var model: ApprovedTopicReviewReadModel
    let original: ApprovedTopicReviewJournal.Snapshot
    @Environment(\.locale) private var locale
    var body: some View {
        Section {
            Text(String(localized: LocalizedStringResource("topicReview.currentTitle", defaultValue: "Current review task", locale: locale))).font(.headline)
            Text(String(localized: LocalizedStringResource("topicReview.currentNotice", defaultValue: "This is the task state read from the server, separate from the status saved when you submitted. Even an approved task still needs independent release preparation and permission checks.", locale: locale))).font(.footnote)
                .accessibilityIdentifier("topicReview.current.notice")
            switch model.flow.observation {
            case .notRequested: EmptyView()
            case .loading: ProgressView()
            case .unauthorized:
                Text(String(localized: LocalizedStringResource("topicReview.unauthorized", defaultValue: "Sign in again before reading this review request.", locale: locale))).accessibilityIdentifier("topicReview.current.unauthorized")
            case .failed:
                Text(String(localized: LocalizedStringResource("topicReview.currentFailed", defaultValue: "The current task could not be verified. Your saved request is unchanged. Close and reopen if its context has changed.", locale: locale)))
                    .accessibilityIdentifier("topicReview.current.failed")
            case .ready(let value):
                field(String(localized: LocalizedStringResource("topicReview.currentTask", defaultValue: "Observed task ID", locale: locale)), String(value.auditTaskID), "task")
                field(String(localized: LocalizedStringResource("topicReview.currentVersion", defaultValue: "Task version when checked", locale: locale)), String(value.observedTaskVersion), "version")
                field(String(localized: LocalizedStringResource("topicReview.currentState", defaultValue: "Task state when checked", locale: locale)), status(value.status), "state")
                field(String(localized: LocalizedStringResource("topicReview.currentHash", defaultValue: "Observed snapshot hash", locale: locale)), value.observedSnapshotHash, "hash")
                Text(value.matchesSubmittedCapture
                    ? String(localized: LocalizedStringResource("topicReview.currentMatches", defaultValue: "This task still references your submitted capture.", locale: locale))
                    : String(localized: LocalizedStringResource("topicReview.currentDifferent", defaultValue: "This task now references a different capture. The original submitted request has not been changed.", locale: locale)))
                    .accessibilityIdentifier("topicReview.current.captureMatch")
            }
            Button(String(localized: LocalizedStringResource("topicReview.currentRead", defaultValue: "Check current review task", locale: locale))) { model.observe(original) }
                .buttonStyle(.borderless).disabled(!model.flow.canObserve).accessibilityIdentifier("topicReview.current.read")
            if !model.flow.canObserve {
                Text(String(localized: LocalizedStringResource("topicReview.currentUnavailable", defaultValue: "Current-task checking is not configured or this saved request is not available for checking.", locale: locale))).font(.footnote)
                    .accessibilityIdentifier("topicReview.current.unavailable")
            }
        }
    }
    private func field(_ label: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled).accessibilityIdentifier("topicReview.current." + suffix)
        }
    }
    private func status(_ value: ApprovedTopicReviewObservation.Status) -> String {
        switch value {
        case .pending: return String(localized: LocalizedStringResource("topicReview.pending", defaultValue: "Pending review", locale: locale))
        case .approved: return String(localized: LocalizedStringResource("topicReview.currentApproved", defaultValue: "Review task approved", locale: locale))
        case .rejected: return String(localized: LocalizedStringResource("topicReview.currentRejected", defaultValue: "Review task rejected", locale: locale))
        case .escalated: return String(localized: LocalizedStringResource("topicReview.escalated", defaultValue: "Escalated review", locale: locale))
        case .cancelled: return String(localized: LocalizedStringResource("topicReview.currentCancelled", defaultValue: "Review task cancelled", locale: locale))
        }
    }
}
