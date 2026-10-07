import SwiftUI

@MainActor final class ApprovedTopicReviewReadModel: ObservableObject {
    let flow: ApprovedTopicReviewFlow
    @Published private(set) var revision = 0
    @Published private(set) var isWorking = false
    @Published private(set) var confirmation: ApprovedTopicReviewFlow.Confirmation?
    init(flow: ApprovedTopicReviewFlow) { self.flow = flow }
    func load() async {
        guard !isWorking else { return }; isWorking = true
        await flow.load(); isWorking = false; revision += 1
    }
    func selectSource(_ choice: ApprovedMerchantReviewChoices.Choice, from original: ApprovedTopicReviewFlow.SourceSelectionPresentation) {
        guard !isWorking, flow.selectSource(choice, from: original) else { return }; revision += 1
    }
    func captureSources(_ original: ApprovedTopicReviewFlow.SourceSelectionPresentation) {
        guard !isWorking, let claim = flow.claimSourceCapture(original) else { return }
        isWorking = true; revision += 1
        Task { [weak self, flow] in await flow.captureSources(claim); self?.isWorking = false; self?.revision += 1 }
    }
    func review(_ capture: ApprovedTopicReviewCapture) {
        guard confirmation == nil, !isWorking, let original = flow.review(capture) else { return }
        confirmation = original; revision += 1
    }
    func owns(_ original: ApprovedTopicReviewFlow.Confirmation) -> Bool {
        confirmation?.id == original.id && flow.confirmation?.id == original.id && flow.isCurrent
    }
    func cancel(_ original: ApprovedTopicReviewFlow.Confirmation) {
        guard confirmation?.id == original.id else { return }; flow.cancel(original); confirmation = nil; revision += 1
    }
    func confirm(_ original: ApprovedTopicReviewFlow.Confirmation) {
        guard confirmation?.id == original.id else { return }
        guard owns(original), let claim = flow.claim(original) else { flow.cancel(original); confirmation = nil; revision += 1; return }
        confirmation = nil; isWorking = true; revision += 1
        Task { [weak self, flow] in await flow.submit(claim); self?.isWorking = false; self?.revision += 1 }
    }
    func check(_ original: ApprovedTopicReviewJournal.Snapshot) {
        guard !isWorking, flow.canReadStatus, flow.snapshot == original else { return }; isWorking = true
        Task { [weak self, flow] in await flow.check(original); self?.isWorking = false; self?.revision += 1 }
    }
    func retry(_ original: ApprovedTopicReviewJournal.Snapshot) {
        guard !isWorking, flow.canRetryExact, flow.snapshot == original else { return }; isWorking = true
        Task { [weak self, flow] in await flow.retryExact(original); self?.isWorking = false; self?.revision += 1 }
    }
    func observe(_ original: ApprovedTopicReviewJournal.Snapshot) {
        guard !isWorking, flow.canObserve, flow.snapshot == original else { return }; isWorking = true
        Task { [weak self, flow] in await flow.observeCurrent(original); self?.isWorking = false; self?.revision += 1 }
    }
    func binding(_ original: ApprovedTopicReviewFlow.Confirmation?) -> Binding<ApprovedTopicReviewFlow.Confirmation?> {
        .init(get: { guard let original, self.owns(original) else { return nil }; return original }, set: { value in
            guard value == nil, let original else { return }; self.cancel(original)
        })
    }
}

@MainActor struct ApprovedTopicReviewRequestView: View {
    let original: ApprovedTopicReviewPresentation.Presentation
    let close: () -> Void
    @StateObject private var model: ApprovedTopicReviewReadModel
    @Environment(\.locale) private var locale
    init(original: ApprovedTopicReviewPresentation.Presentation, close: @escaping () -> Void) {
        self.original = original; self.close = close; _model = StateObject(wrappedValue: .init(flow: original.flow))
    }
    var body: some View {
        let confirmation = model.confirmation
        NavigationStack {
            Form {
                if original.flow.isCurrent {
                    if model.isWorking {
                        ProgressView().accessibilityIdentifier("topicReview.loading")
                    } else { content }
                } else {
                    Text(String(localized: LocalizedStringResource("topicReview.changed", defaultValue: "This review context is no longer current. Any saved request is retained.", locale: locale)))
                        .accessibilityIdentifier("topicReview.changed")
                }
            }
            .navigationTitle(String(localized: LocalizedStringResource("topicReview.title", defaultValue: "Request a content review", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: LocalizedStringResource("topicReview.close", defaultValue: "Close", locale: locale)), action: close)
                    .buttonStyle(.borderless).accessibilityIdentifier("topicReview.close")
            } }
        }
        .task(id: original.id) { await model.load() }
        .sheet(item: model.binding(confirmation)) { captured in
            if model.owns(captured) {
                ApprovedTopicReviewConfirmationView(original: captured, confirm: { model.confirm(captured) }, cancel: { model.cancel(captured) })
            }
        }
        .onDisappear { original.flow.close() }
    }
    @ViewBuilder private var content: some View {
        let flow = original.flow
        switch flow.state {
        case .selectingSources(let presentation):
            ApprovedMerchantReviewSourceSection(model: model, presentation: presentation)
        case .ready(let capture):
            ApprovedTopicReviewSummarySection(coverSource: original.coverSource, coverSession: flow.session, coverContextCurrent: { flow.isCurrent && flow.state == .ready(capture) }, capture: capture)
            Section {
                Button(String(localized: LocalizedStringResource("topicReview.review", defaultValue: "Review this exact request", locale: locale))) { model.review(capture) }
                    .buttonStyle(.borderless).disabled(!flow.canConfirm(capture)).accessibilityIdentifier("topicReview.review")
            }
        case .known(let receipt):
            Section {
                Text(String(localized: LocalizedStringResource("topicReview.submitted", defaultValue: "The server recorded this review request. It is not an approval or a release receipt. The original V2 submission remains unchanged.", locale: locale)))
                    .accessibilityIdentifier("topicReview.submitted")
                receiptField(String(localized: LocalizedStringResource("topicReview.submittedTask", defaultValue: "Submitted review task ID", locale: locale)), String(receipt.auditTaskID), "submittedTask")
                receiptField(String(localized: LocalizedStringResource("topicReview.submittedVersion", defaultValue: "Task version when submitted", locale: locale)), String(receipt.submittedTaskVersion), "submittedVersion")
                receiptField(String(localized: LocalizedStringResource("topicReview.submittedState", defaultValue: "Status when submitted", locale: locale)), receipt.submittedTaskStatus == 0
                    ? String(localized: LocalizedStringResource("topicReview.pending", defaultValue: "Pending review", locale: locale))
                    : String(localized: LocalizedStringResource("topicReview.escalated", defaultValue: "Escalated review", locale: locale)), "submittedState")
                receiptField(String(localized: LocalizedStringResource("topicReview.requestID", defaultValue: "Saved request ID", locale: locale)), receipt.requestID, "requestID")
                Text(String(localized: LocalizedStringResource("topicReview.afterSubmission", defaultValue: "Close this sheet to check the approved snapshot separately. A saved submission status is historical and does not establish the current review outcome.", locale: locale))).font(.footnote)
            }
            if let captured = flow.snapshot { ApprovedTopicReviewObservationSection(model: model, original: captured) }
            recoveryControls
            if !flow.isReceiptForThisSubmission {
                Section {
                    Text(String(localized: LocalizedStringResource("topicReview.previousDraft", defaultValue: "This recovered receipt belongs to an earlier submitted draft. You can now capture the current acknowledged draft.", locale: locale)))
                    Button(String(localized: LocalizedStringResource("topicReview.captureCurrent", defaultValue: "Capture this draft", locale: locale))) { Task { await model.load() } }
                        .buttonStyle(.borderless).accessibilityIdentifier("topicReview.captureCurrent")
                }
            }
        case .unconfirmed:
            Section {
                Text(String(localized: LocalizedStringResource("topicReview.unconfirmed", defaultValue: "The outcome is unconfirmed. The original request is saved. Check its status or retry exactly that request; a new request will not be invented.", locale: locale)))
                    .accessibilityIdentifier("topicReview.unconfirmed")
                if let id = flow.snapshot?.current?.command.requestID { receiptField(String(localized: LocalizedStringResource("topicReview.requestID", defaultValue: "Saved request ID", locale: locale)), id, "requestID") }
            }
            recoveryControls
        case .failed:
            Section {
                Text(String(localized: LocalizedStringResource("topicReview.failed", defaultValue: "The current capture or saved local request could not be verified. Retrying reads saved state first and does not invent a replacement request.", locale: locale)))
                    .accessibilityIdentifier("topicReview.failed")
                Button(String(localized: LocalizedStringResource("topicReview.reload", defaultValue: "Read saved state and retry", locale: locale))) { Task { await model.load() } }
                    .buttonStyle(.borderless).accessibilityIdentifier("topicReview.reload")
            }
        case .unauthorized:
            Text(String(localized: LocalizedStringResource("topicReview.unauthorized", defaultValue: "Sign in again before reading this review request.", locale: locale))).accessibilityIdentifier("topicReview.unauthorized")
        case .idle, .loading, .sending: ProgressView().accessibilityIdentifier("topicReview.loading")
        case .closed: EmptyView()
        }
    }
    @ViewBuilder private var recoveryControls: some View {
        let flow = original.flow
        if let captured = flow.snapshot {
            Section {
                if !flow.canReadStatus && !flow.canRetryExact {
                    Text(String(localized: LocalizedStringResource("topicReview.recoveryUnavailable", defaultValue: "Recovery is not configured for this account or request. The saved request remains unchanged.", locale: locale)))
                        .font(.footnote).accessibilityIdentifier("topicReview.recoveryUnavailable")
                }
                Button(String(localized: LocalizedStringResource("topicReview.check", defaultValue: "Check saved request", locale: locale))) { model.check(captured) }
                    .buttonStyle(.borderless).disabled(!flow.canReadStatus).accessibilityIdentifier("topicReview.check")
                if captured.current?.receipt == nil {
                    Button(String(localized: LocalizedStringResource("topicReview.retryExact", defaultValue: "Retry the exact saved request", locale: locale))) { model.retry(captured) }
                        .buttonStyle(.borderless).disabled(!flow.canRetryExact).accessibilityIdentifier("topicReview.retryExact")
                }
            }
        }
    }
    private func receiptField(_ label: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).textSelection(.enabled).accessibilityIdentifier("topicReview." + suffix)
        }
    }
}

@MainActor private struct ApprovedTopicReviewConfirmationView: View {
    let original: ApprovedTopicReviewFlow.Confirmation
    let confirm: () -> Void
    let cancel: () -> Void
    @Environment(\.locale) private var locale
    var body: some View {
        NavigationStack {
            Form {
                ApprovedTopicReviewSummarySection(capture: original.capture, prefix: "topicReview.confirm")
                Section {
                    Text(String(localized: LocalizedStringResource("topicReview.confirmation", defaultValue: "Send exactly this captured version for review. This action does not approve the content or create an immutable release.", locale: locale)))
                    Button(String(localized: LocalizedStringResource("topicReview.submit", defaultValue: "Request review of this capture", locale: locale)), action: confirm)
                        .buttonStyle(.borderless).accessibilityIdentifier("topicReview.confirm.submit")
                }
            }
            .navigationTitle(String(localized: LocalizedStringResource("topicReview.confirmTitle", defaultValue: "Confirm review request", locale: locale)))
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: LocalizedStringResource("topicReview.cancel", defaultValue: "Cancel", locale: locale)), action: cancel)
                    .buttonStyle(.borderless).accessibilityIdentifier("topicReview.confirm.cancel")
            } }
        }.onDisappear(perform: cancel)
    }
}
