import SwiftUI

/// Presentation only. Existing intent, receipt validation, current-owner checks and
/// action eligibility remain with the original editor/coordinator. No writer lives here.
enum ProjectCloudDraftReceiptPresentation {
    enum ProcessingContent: Equatable {
        case unavailable
        case recorded(ProjectEditPostProcessingReceipt)
    }

    static func intentKey(_ intent: ProjectEditSubmissionIntent) -> String {
        switch intent {
        case .ordinary: return "intent.ordinary"
        case .saveCloudDraft: return "intent.save"
        case .submitServerDraft: return "intent.submit"
        }
    }

    static func explanationKey(_ intent: ProjectEditSubmissionIntent) -> String? {
        switch intent {
        case .ordinary: return nil
        case .saveCloudDraft: return "intent.saveExplanation"
        case .submitServerDraft: return "intent.submitExplanation"
        }
    }

    // Exact original codes only: case folding or an unknown code cannot imply success.
    static let statusKeys: [String: String] = [
        "PENDING": "status.pending",
        "FAILED": "status.failed",
        "NOT_REQUIRED": "status.notRequired",
        "DEFERRED_DRAFT": "status.deferredDraft",
        "RECORDED": "status.recorded",
        "STALE_SOURCE": "status.staleSource",
        "SUPERSEDED": "status.superseded",
        "AWAITING_NEW_RECORD": "status.awaitingNewRecord",
        "RECORDED_DECISION": "status.recordedDecision",
        "WAITING": "status.waitingMedia",
        "PROCESSING": "status.waitingMedia",
        "DONE": "status.mediaDone",
        "RETRYABLE_CALLBACK": "status.retryableCallback",
        "IGNORED_STALE": "status.ignoredStale",
        "MANUAL_REVIEW": "status.manualReview",
        "NOT_CONFIGURED": "status.notConfigured",
        "REGISTERED": "status.registered",
        "WRITER_BUNDLE_SUBMISSION": "status.bundleSubmission",
        "SPOT_CHECK_REUSED": "status.spotCheckReused",
        "SPOT_CHECK_CREATED": "status.spotCheckCreated",
        "APPROVE": "status.approve",
        "REJECT": "status.reject",
        "REVERT": "status.revert",
        "CANCEL": "status.cancel",
        "ESCALATE": "status.escalate"
    ]

    static func statusKey(_ code: String) -> String { statusKeys[code] ?? "status.unknown" }

    static func riskKey(_ risky: Bool?) -> String {
        switch risky {
        case true?: return "risk.matched"
        case false?: return "risk.notMatched"
        case nil: return "risk.unknown"
        }
    }

    static func processing(_ receipt: ProjectEditPostProcessingReceipt?) -> ProcessingContent {
        receipt.map(ProcessingContent.recorded) ?? .unavailable
    }
}

struct ProjectCloudDraftIntentSummary: View {
    let intent: ProjectEditSubmissionIntent
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(ProjectCloudDraftReceiptPresentation.intentKey(intent)), tableName: "ProjectCloudDraftReceipt")
                .font(.headline)
            if let key = ProjectCloudDraftReceiptPresentation.explanationKey(intent) {
                Text(LocalizedStringKey(key), tableName: "ProjectCloudDraftReceipt")
                    .font(.body).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("projectCloudDraft.intentSummary")
    }
}

/// Mounted only inside the original committed-request section. An unavailable
/// processing read does not erase the separate, confirmed project-save fact.
struct ProjectCloudDraftProcessingFacts: View {
    let receipt: ProjectEditPostProcessingReceipt?
    var body: some View {
        switch ProjectCloudDraftReceiptPresentation.processing(receipt) {
        case .unavailable:
            Label {
                Text("processing.unavailable", tableName: "ProjectCloudDraftReceipt")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: { Image(systemName: "info.circle") }
            .accessibilityIdentifier("projectCloudDraft.processingUnavailable")
        case .recorded(let value):
            ProjectCloudDraftStatusLine(titleKey: "processing.spotCheck", code: value.spotCheckState)
            if value.audits.isEmpty {
                Text("processing.noAudits", tableName: "ProjectCloudDraftReceipt")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectCloudDraft.noAudits")
            }
            ForEach(value.audits, id: \.taskID) { audit in
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent {
                        Text(verbatim: String(audit.taskID)).monospacedDigit().textSelection(.enabled)
                    } label: { Text("processing.auditID", tableName: "ProjectCloudDraftReceipt") }
                    ProjectCloudDraftStatusLine(titleKey: "processing.association", code: audit.association)
                    ProjectCloudDraftStatusLine(titleKey: "processing.auditState", code: audit.state)
                    if audit.actions.isEmpty {
                        Text("processing.noActions", tableName: "ProjectCloudDraftReceipt")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("processing.actions", tableName: "ProjectCloudDraftReceipt")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(audit.actions.enumerated()), id: \.offset) { _, code in
                                Text(LocalizedStringKey(ProjectCloudDraftReceiptPresentation.statusKey(code)), tableName: "ProjectCloudDraftReceipt")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }.padding(.vertical, 4)
            }
            if value.media.isEmpty {
                Text("processing.noMedia", tableName: "ProjectCloudDraftReceipt")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("projectCloudDraft.noMedia")
            }
            ForEach(value.media, id: \.mediaSHA256) { media in
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent {
                        Text(verbatim: String(media.mediaSHA256.prefix(8))).monospaced().textSelection(.enabled)
                    } label: { Text("processing.mediaID", tableName: "ProjectCloudDraftReceipt") }
                    ProjectCloudDraftStatusLine(titleKey: "processing.mediaState", code: media.state)
                    Text(LocalizedStringKey(ProjectCloudDraftReceiptPresentation.riskKey(media.risky)), tableName: "ProjectCloudDraftReceipt")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            }
            ProjectCloudDraftStatusLine(titleKey: "processing.creative", code: value.creativeState)
        }
    }
}

private struct ProjectCloudDraftStatusLine: View {
    let titleKey: String
    let code: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(titleKey), tableName: "ProjectCloudDraftReceipt")
                .font(.caption).foregroundStyle(.secondary)
            Text(LocalizedStringKey(ProjectCloudDraftReceiptPresentation.statusKey(code)), tableName: "ProjectCloudDraftReceipt")
                .font(.body).fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
