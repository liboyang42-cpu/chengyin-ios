import SwiftUI

@MainActor final class ApprovedReleaseReadModel: ObservableObject {
    let flow: ApprovedTopicReleaseReadFlow
    let publisher: ApprovedTopicReleasePublishFlow?
    @Published private(set) var confirmation: ApprovedTopicReleasePublishFlow.Confirmation?
    @Published private(set) var revision = 0
    init(original: ApprovedReleaseAuthorPresentation.Presentation) { flow = original.flow; publisher = original.publisher }
    func load() async { publisher?.reload(); revision += 1; await flow.load(); revision += 1 }
    func review(_ prepared: ApprovedTopicReleasePreparation) {
        guard flow.isCurrent, flow.state == .ready(prepared), confirmation == nil else { return }
        confirmation = publisher?.review(prepared); revision += 1
    }
    func cancel(_ original: ApprovedTopicReleasePublishFlow.Confirmation) {
        publisher?.cancel(original)
        if confirmation?.id == original.id { confirmation = nil }
        revision += 1
    }
    func confirm(_ original: ApprovedTopicReleasePublishFlow.Confirmation) {
        guard confirmation?.id == original.id, flow.isCurrent, flow.state == .ready(original.prepared),
              let publisher, let claim = publisher.claim(original) else { cancel(original); return }
        confirmation = nil; revision += 1
        Task { [weak self] in await publisher.submit(claim); self?.revision += 1 }
    }
    func confirmationBinding(_ original: ApprovedTopicReleasePublishFlow.Confirmation?) -> Binding<ApprovedTopicReleasePublishFlow.Confirmation?> {
        Binding(get: { guard let original, self.confirmation?.id == original.id, self.publisher?.isCurrent == true,
            self.flow.isCurrent, self.flow.state == .ready(original.prepared) else { return nil }; return original },
            set: { value in guard value == nil, let original else { return }; self.cancel(original) })
    }
    func check(_ original: ApprovedTopicReleasePublicationJournal.Snapshot) async { revision += 1; await publisher?.checkStatus(original); revision += 1 }
    func retry(_ original: ApprovedTopicReleasePublicationJournal.Snapshot) async { revision += 1; await publisher?.retryExact(original); revision += 1 }
    func close() { publisher?.close(); flow.close(); revision += 1 }
}

@MainActor struct ApprovedReleasePreparationView: View {
    @Environment(\.locale) private var locale
    @StateObject private var model: ApprovedReleaseReadModel
    let original: ApprovedReleaseAuthorPresentation.Presentation
    let close: () -> Void
    init(original: ApprovedReleaseAuthorPresentation.Presentation, close: @escaping () -> Void) {
        self.original = original; self.close = close; _model = StateObject(wrappedValue: .init(original: original))
    }
    var body: some View {
        let confirmation = model.confirmation
        NavigationStack {
            Form {
                Text(String(localized: LocalizedStringResource("approvedRelease.readOnly", defaultValue: "This is a captured server-approved summary, not your editable draft. Reading it creates no release.", locale: locale)))
                    .font(.footnote).accessibilityIdentifier("approvedRelease.readOnly")
                if !model.flow.isCurrent {
                    Text(String(localized: LocalizedStringResource("approvedRelease.changedContext", defaultValue: "This review is no longer current. Close it and return to the current submission.", locale: locale)))
                } else {
                    switch model.flow.state {
                    case .idle, .loading: ProgressView().accessibilityIdentifier("approvedRelease.loading")
                    case .ready(let prepared): ApprovedReleaseSummarySection(coverSource: original.coverSource, coverSession: original.flow.session, coverContextCurrent: { original.flow.isCurrent && original.flow.state == .ready(prepared) }, prepared: prepared)
                    case .unauthorized:
                        Text(String(localized: LocalizedStringResource("approvedRelease.unauthorized", defaultValue: "Sign in again before checking the current approved snapshot.", locale: locale)))
                    case .failed:
                        Text(String(localized: LocalizedStringResource("approvedRelease.checkFailed", defaultValue: "No current approved snapshot could be verified. Review may be pending, changed, unsupported or unavailable. This check did not create or retry a release; any saved request is retained.", locale: locale)))
                            .accessibilityIdentifier("approvedRelease.failed")
                        Button(String(localized: LocalizedStringResource("approvedRelease.retry", defaultValue: "Check again", locale: locale))) { Task { await model.load() } }
                            .buttonStyle(.borderless).accessibilityIdentifier("approvedRelease.retry")
                    case .closed: EmptyView()
                    }
                    if let publisher = model.publisher { publication(publisher) }
                }
            }
            .navigationTitle(String(localized: LocalizedStringResource("approvedRelease.title", defaultValue: "Approved snapshot", locale: locale)))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: LocalizedStringResource("approvedRelease.close", defaultValue: "Close", locale: locale))) { model.close(); close() }
                        .accessibilityIdentifier("approvedRelease.close")
                }
            }
        }
        .task(id: original.id) { await model.load() }
        .sheet(item: model.confirmationBinding(confirmation)) { captured in
            ApprovedReleasePublicationConfirmationView(original: captured, cancel: model.cancel, confirm: model.confirm)
        }
        .onDisappear { original.publisher?.close(); original.flow.close() }
    }
    @ViewBuilder private func publication(_ publisher: ApprovedTopicReleasePublishFlow) -> some View {
        let captured = publisher.snapshot
        Section {
            Text(String(localized: LocalizedStringResource("approvedRelease.publishScope", defaultValue: "Creating an immutable release records this exact approved version. It does not by itself prove public listing, player eligibility or successful play.", locale: locale)))
                .font(.footnote)
            switch publisher.state {
            case .sending: ProgressView().accessibilityIdentifier("approvedRelease.publication.sending")
            case .known(let receipt):
                Text(String(receipt.releaseID)).accessibilityIdentifier("approvedRelease.publication.releaseID")
                Text(verbatim: receipt.manifestHash).textSelection(.enabled).accessibilityIdentifier("approvedRelease.publication.manifestHash")
                Text(String(localized: LocalizedStringResource("approvedRelease.allocated", defaultValue: "The server returned an immutable release ID for this captured manifest.", locale: locale)))
                Text(receipt.currentlyApproved
                    ? String(localized: LocalizedStringResource("approvedRelease.receiptApproved", defaultValue: "Approved at the last server check", locale: locale))
                    : String(localized: LocalizedStringResource("approvedRelease.receiptChanged", defaultValue: "The last server check did not confirm current approval", locale: locale)))
                    .accessibilityIdentifier("approvedRelease.publication.approval")
            case .unconfirmed:
                Text(String(localized: LocalizedStringResource("approvedRelease.unconfirmed", defaultValue: "The publication result is unconfirmed. The exact request is retained; check its result before creating another request.", locale: locale)))
                    .accessibilityIdentifier("approvedRelease.publication.unconfirmed")
            case .unavailable:
                Text(String(localized: LocalizedStringResource("approvedRelease.journalUnavailable", defaultValue: "The local publication record could not be safely read or saved. Existing bytes were not cleared. No new request is authorized by this error.", locale: locale)))
                    .accessibilityIdentifier("approvedRelease.publication.unavailable")
            case .idle, .reviewing, .closed: EmptyView()
            }
            if let captured, let record = captured.current {
                Text(verbatim: record.command.requestID).textSelection(.enabled).accessibilityIdentifier("approvedRelease.publication.requestID")
                Button(String(localized: LocalizedStringResource("approvedRelease.checkResult", defaultValue: "Check this request", locale: locale))) { Task { await model.check(captured) } }
                    .buttonStyle(.borderless).disabled(!publisher.canCheckStatus).accessibilityIdentifier("approvedRelease.publication.check")
                if record.receipt == nil {
                    Button(String(localized: LocalizedStringResource("approvedRelease.retryExact", defaultValue: "Retry the exact saved request", locale: locale))) { Task { await model.retry(captured) } }
                        .buttonStyle(.borderless).disabled(!publisher.canRetryExact).accessibilityIdentifier("approvedRelease.publication.retry")
                }
            }
            if case .ready(let prepared) = model.flow.state, publisher.canReview(prepared) {
                Button(String(localized: LocalizedStringResource("approvedRelease.reviewPublication", defaultValue: "Review immutable release", locale: locale))) { model.review(prepared) }
                    .buttonStyle(.borderless).accessibilityIdentifier("approvedRelease.publish")
            }
        }
    }

}
