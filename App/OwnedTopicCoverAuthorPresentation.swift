import SwiftUI

@MainActor final class OwnedTopicCoverAuthorPresentation: ObservableObject {
    struct Opening {
        let pending: ProjectEditPending
        let session: ProjectEditSession
        let incarnation: UUID
        let target: ApprovedTopicReleaseReadTarget
        let source: any OwnedTopicCoverServing
        let journal: OwnedTopicCoverJournal
    }
    struct Presentation: Identifiable {
        let opening: Opening
        let flow: OwnedTopicCoverAuthorFlow
        var id: UUID { flow.id }
    }
    @Published private(set) var presentation: Presentation?
    private let model: ProjectEditModel
    init(model: ProjectEditModel) { self.model = model }
    func capture() -> Opening? {
        guard presentation == nil, model.submissionEvidence?.bundleAcknowledgment != nil,
              let pending = model.coordinator.pending, let session = model.coordinator.session,
              let target = ApprovedTopicReleaseReadTarget(pending: pending,session: session),
              let source = model.coordinator.ownedCoverSource, source.permits(.readCurrent,session: session),
              let journal = model.coordinator.ownedCoverJournal else { return nil }
        return .init(pending:pending,session:session,incarnation:model.editorIncarnation,target:target,source:source,journal:journal)
    }
    func isCurrent(_ opening: Opening) -> Bool {
        guard model.ownsVisit, model.editorIncarnation == opening.incarnation, model.coordinator.session == opening.session,
              model.submissionEvidence?.operationID == opening.pending.operationID, let pending = model.coordinator.pending,
              let source = model.coordinator.ownedCoverSource, ObjectIdentifier(source) == ObjectIdentifier(opening.source),
              model.coordinator.ownedCoverJournal === opening.journal, source.isCurrent(session:opening.session) else { return false }
        return ProjectEditLocalStore.exactPending(pending,opening.pending)
    }
    func mayChange(_ opening: Opening) -> Bool {
        guard isCurrent(opening) else { return false }
        do {
            if let journal = model.coordinator.releaseReviewJournal {
                let snapshot = try journal.read(session:opening.session,topicID:opening.target.topicID)
                // A selection receipt is not a new V2 editing receipt. A reviewed edit uses the
                // ordinary explicit continue-edit/save path before choosing another cover.
                guard !snapshot.records.contains(where: { $0.originOperationID == opening.pending.operationID }),
                      snapshot.current == nil || snapshot.current?.receipt != nil else { return false }
            }
            if let journal = model.coordinator.releasePublicationJournal {
                let snapshot = try journal.read(session:opening.session,topicID:opening.target.topicID)
                guard snapshot.current == nil || snapshot.current?.receipt != nil else { return false }
            }
            return true
        } catch { return false }
    }
    func open(_ opening: Opening) {
        guard presentation == nil, isCurrent(opening) else { return }
        let flow = OwnedTopicCoverAuthorFlow(session:opening.session,topicID:opening.target.topicID,source:opening.source,journal:opening.journal,
            parentCurrent:{ [weak self] in self?.isCurrent(opening) == true },mayChangeSelection:{ [weak self] in self?.mayChange(opening) == true })
        presentation = .init(opening:opening,flow:flow)
    }
    func acceptedSelection(_ original: Presentation) {
        guard presentation?.id == original.id, isCurrent(original.opening), case .selected(let receipt) = original.flow.state else { return }
        model.recordCoverSelection(receipt, operationID: original.opening.pending.operationID)
        model.invalidateStarterLease(); close(original)
    }
    func close(_ original: Presentation) {
        original.flow.close(); guard presentation?.id == original.id else { return }; presentation = nil
    }
    func retire() { if let presentation { close(presentation) } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get:{ guard let original,self.presentation?.id == original.id,self.isCurrent(original.opening) else { return nil };return original },set:{ next in
            guard next == nil,let original else { return };self.close(original)
        })
    }
}

@MainActor struct OwnedTopicCoverEntrySection: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: OwnedTopicCoverAuthorPresentation
    @Environment(\.locale) private var locale
    var body: some View {
        let opening = controller.capture()
        if model.submissionEvidence?.bundleAcknowledgment != nil {
            Section {
                if let receipt = model.coverSelectionNotice {
                    Text(String(localized:LocalizedStringResource("ownedCover.selectedNotice",defaultValue:"The server selected this cover for the next review. Existing release images remain unchanged.",locale:locale)))
                        .accessibilityIdentifier("ownedCover.selectedNotice")
                    Text(verbatim:receipt.asset.assetID).textSelection(.enabled).accessibilityIdentifier("ownedCover.selectedNotice.asset")
                    Text(String(receipt.configVersion)).accessibilityIdentifier("ownedCover.selectedNotice.config")
                }
                Button(String(localized:LocalizedStringResource("ownedCover.open",defaultValue:"Choose a cover for review",locale:locale))) {
                    guard let opening else { return };controller.open(opening)
                }.buttonStyle(.borderless).disabled(opening == nil).accessibilityIdentifier("ownedCover.open")
                if opening == nil {
                    Text(String(localized:LocalizedStringResource("ownedCover.unconfigured",defaultValue:"Author cover selection is not configured for this account or saved submission.",locale:locale)))
                        .font(.footnote).accessibilityIdentifier("ownedCover.unconfigured")
                }
            }
        }
    }
}
