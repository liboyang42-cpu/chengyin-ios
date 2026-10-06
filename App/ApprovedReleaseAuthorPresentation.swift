import SwiftUI

@MainActor final class ApprovedReleaseAuthorPresentation: ObservableObject {
    struct Opening {
        let pending: ProjectEditPending
        let session: ProjectEditSession
        let incarnation: UUID
        let target: ApprovedTopicReleaseReadTarget
        let reviewSnapshot: ApprovedTopicReviewJournal.Snapshot?
        let source: any ApprovedTopicReleasePreparing
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let coverSource: (any OwnedTopicCoverServing)?
        let flow: ApprovedTopicReleaseReadFlow
        let publisher: ApprovedTopicReleasePublishFlow?
        var id: UUID { flow.id }
    }
    private let model: ProjectEditModel
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel) { self.model = model }
    func capture() -> Opening? {
        guard presentation == nil, model.submissionEvidence?.bundleAcknowledgment != nil,
              let pending = model.coordinator.pending, let session = model.coordinator.session,
              let readScope = model.approvedReleaseReadScope(),
              let source = model.coordinator.releasePreparationSource, source.isCurrent(session: session) else { return nil }
        return .init(pending: pending, session: session, incarnation: model.editorIncarnation, target: readScope.target, reviewSnapshot: readScope.reviewSnapshot, source: source)
    }
    func isCurrent(_ opening: Opening) -> Bool {
        guard model.ownsVisit, model.editorIncarnation == opening.incarnation,
              model.coordinator.session == opening.session,
              model.submissionEvidence?.operationID == opening.pending.operationID,
              let readScope = model.approvedReleaseReadScope(), readScope.target == opening.target, readScope.reviewSnapshot == opening.reviewSnapshot,
              let pending = model.coordinator.pending,
              let source = model.coordinator.releasePreparationSource,
              ObjectIdentifier(source) == ObjectIdentifier(opening.source), source.isCurrent(session: opening.session) else { return false }
        return ProjectEditLocalStore.exactPending(pending, opening.pending)
    }
    func open(_ opening: Opening) {
        guard presentation == nil, isCurrent(opening) else { return }
        let flow = ApprovedTopicReleaseReadFlow(target: opening.target, session: opening.session, source: opening.source,
            stillCurrent: { [weak self] in self?.isCurrent(opening) == true })
        let publisher: ApprovedTopicReleasePublishFlow?
        if let source = model.coordinator.releasePublicationSource, let journal = model.coordinator.releasePublicationJournal {
            publisher = .init(session: opening.session, topicID: opening.target.topicID, source: source, journal: journal,
                stillCurrent: { [weak self] in self?.isCurrent(opening) == true && self?.presentation?.id == flow.id })
        } else { publisher = nil }
        presentation = .init(opening: opening, coverSource: model.coordinator.ownedCoverSource, flow: flow, publisher: publisher)
    }
    func isPresented(_ original: Presentation) -> Bool {
        presentation?.id == original.id && isCurrent(original.opening) && original.flow.state != .closed
    }
    func close(_ original: Presentation) {
        original.publisher?.close(); original.flow.close()
        guard presentation?.id == original.id else { return }; presentation = nil
    }
    func retire() { if let presentation { close(presentation) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        Binding(get: { guard let original, self.isPresented(original) else { return nil }; return original }, set: { value in
            guard value == nil, let original else { return }; self.close(original)
        })
    }
}

@MainActor struct ApprovedReleaseAuthorReadSection: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ApprovedReleaseAuthorPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        let opening = controller.capture()
        if model.submissionEvidence?.bundleAcknowledgment != nil {
            Section {
                Button(String(localized: LocalizedStringResource("approvedRelease.read", defaultValue: "Check the approved snapshot", locale: locale))) {
                    guard let opening else { return }; controller.open(opening)
                }.buttonStyle(.borderless).disabled(opening == nil).accessibilityIdentifier("approvedRelease.read")
                if opening == nil {
                    Text(String(localized: LocalizedStringResource("approvedRelease.unconfigured", defaultValue: "Approved-snapshot reading is not configured for this account, mode or submission. The original submission lock is unchanged.", locale: locale)))
                        .font(.footnote).accessibilityIdentifier("approvedRelease.unconfigured")
                }
            }
        }
    }
}
