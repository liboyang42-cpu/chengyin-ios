import SwiftUI

@MainActor final class ApprovedTopicReviewPresentation: ObservableObject {
    struct Opening {
        let pending: ProjectEditPending
        let session: ProjectEditSession
        let incarnation: UUID
        let origin: ApprovedTopicReleaseReadTarget
        let source: any ApprovedTopicReviewServing
        let journal: ApprovedTopicReviewJournal
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let coverSource: (any OwnedTopicCoverServing)?
        let flow: ApprovedTopicReviewFlow
        var id: UUID { flow.id }
    }
    private let model: ProjectEditModel
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel) { self.model = model }
    func capture() -> Opening? {
        guard presentation == nil, model.coverSelectionIsResolved, model.submissionEvidence?.bundleAcknowledgment != nil,
              let pending = model.coordinator.pending, let session = model.coordinator.session,
              let origin = ApprovedTopicReleaseReadTarget(pending: pending, session: session),
              let source = model.coordinator.releaseReviewSource, source.isCurrent(session: session),
              let journal = model.coordinator.releaseReviewJournal else { return nil }
        return .init(pending: pending, session: session, incarnation: model.editorIncarnation, origin: origin, source: source, journal: journal)
    }
    func isCurrent(_ original: Opening) -> Bool {
        guard model.ownsVisit, model.coverSelectionIsResolved, model.editorIncarnation == original.incarnation, model.coordinator.session == original.session,
              model.submissionEvidence?.operationID == original.pending.operationID,
              let pending = model.coordinator.pending, let source = model.coordinator.releaseReviewSource,
              let journal = model.coordinator.releaseReviewJournal, ObjectIdentifier(source) == ObjectIdentifier(original.source),
              journal === original.journal, source.isCurrent(session: original.session) else { return false }
        return ProjectEditLocalStore.exactPending(pending, original.pending)
    }
    func open(_ original: Opening) {
        guard presentation == nil, isCurrent(original) else { return }
        let flow = ApprovedTopicReviewFlow(origin: original.origin, session: original.session, source: original.source, journal: original.journal,
            stillCurrent: { [weak self] in self?.isCurrent(original) == true })
        presentation = .init(opening: original, coverSource: model.coordinator.ownedCoverSource, flow: flow)
    }
    func isPresented(_ original: Presentation) -> Bool { presentation?.id == original.id && isCurrent(original.opening) && original.flow.state != .closed }
    func close(_ original: Presentation) {
        original.flow.close(); guard presentation?.id == original.id else { return }; presentation = nil
    }
    func retire() { if let presentation { close(presentation) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isPresented(original) else { return nil }; return original }, set: { value in
            guard value == nil, let original else { return }; self.close(original)
        })
    }
}

@MainActor struct ApprovedTopicReviewEntrySection: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ApprovedTopicReviewPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        let opening = controller.capture()
        if model.submissionEvidence?.bundleAcknowledgment != nil {
            Section {
                Button(String(localized: LocalizedStringResource("topicReview.open", defaultValue: "Prepare a new review request", locale: locale))) {
                    guard let opening else { return }; controller.open(opening)
                }.buttonStyle(.borderless).disabled(opening == nil).accessibilityIdentifier("topicReview.open")
                if opening == nil {
                    Text(String(localized: LocalizedStringResource("topicReview.unconfigured", defaultValue: "New review requests are not configured for this account, mode or submission. The original submission receipt is retained.", locale: locale)))
                        .font(.footnote).accessibilityIdentifier("topicReview.unconfigured")
                }
            }
        }
    }
}
