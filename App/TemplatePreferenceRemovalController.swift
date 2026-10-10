import SwiftUI

/// One local review lifetime. No server calls, persistence or implicit source repair.
@MainActor final class TemplatePreferenceRemovalController: ObservableObject {
    struct Capture {
        let controller: UUID
        let generation: UUID
        let editorGeneration: UUID
        let session: TemplateAuthoringSession
        let identity: TemplateAuthoringIdentity
        let source: String
    }
    struct Presentation: Identifiable {
        let id = UUID()
        let capture: Capture
        let document: TemplatePreferenceRemoval?
    }
    struct Review: Identifiable {
        let id = UUID()
        let presentationID: UUID
        let target: TemplatePreferenceRemoval.Target
        let label: String
    }
    private let model: TemplateAuthoringModel
    private let identity = UUID()
    private var generation = UUID()
    @Published private(set) var presentation: Presentation?
    @Published private(set) var review: Review?
    init(model: TemplateAuthoringModel) { self.model = model }
    private var editable: Bool {
        model.canEdit && model.draft.id == nil && model.draft.finishEnabled && model.draft.validationMethod == .preference
    }
    func capture() -> Capture? {
        guard editable, let session = model.coordinator.session, let source = model.draft.preferenceJson else { return nil }
        return .init(controller: identity, generation: generation, editorGeneration: model.metadataGeneration,
                     session: session, identity: model.coordinator.identity, source: source)
    }
    private func isCurrent(_ capture: Capture) -> Bool {
        editable && capture.controller == identity && capture.generation == generation &&
        capture.editorGeneration == model.metadataGeneration && capture.session == model.coordinator.session &&
        capture.identity == model.coordinator.identity &&
        model.draft.preferenceJson.map({ $0.utf8.elementsEqual(capture.source.utf8) }) == true
    }
    func isCurrent(_ original: Presentation) -> Bool {
        presentation?.id == original.id && isCurrent(original.capture)
    }
    var currentPresentation: Presentation? {
        guard let presentation, isCurrent(presentation) else { return nil }; return presentation
    }
    func open(_ capture: Capture) {
        guard presentation == nil, isCurrent(capture) else { return }
        presentation = .init(capture: capture, document: try? .init(source: capture.source)); review = nil
    }
    func request(_ target: TemplatePreferenceRemoval.Target, in original: Presentation) {
        guard isCurrent(original), review == nil, let document = original.document else { return }
        let label: String
        switch target {
        case .question(let index):
            guard document.canRemoveQuestion, document.questions.indices.contains(index) else { return }
            label = document.questions[index].title
        case .option(let question, let index):
            guard document.questions.indices.contains(question) else { return }
            let row = document.questions[question]
            guard row.canRemoveOption, row.options.indices.contains(index) else { return }
            label = row.options[index].text
        }
        review = .init(presentationID: original.id, target: target, label: label)
    }
    func cancel(_ intent: Review, in original: Presentation) {
        guard isCurrent(original), review?.id == intent.id, intent.presentationID == original.id else { return }; review = nil
    }
    @discardableResult func confirm(_ intent: Review, in original: Presentation) -> Bool {
        guard isCurrent(original), review?.id == intent.id, intent.presentationID == original.id,
              let document = original.document, let source = model.draft.preferenceJson,
              let next = try? document.removing(intent.target, from: source) else { return false }
        // Retire before committing, so duplicate taps and old dismissal callbacks cannot
        // affect a later review even when its source happens to have the same bytes.
        retire(); model.draft.preferenceJson = next; model.changed(); return true
    }
    func close(_ original: Presentation) {
        guard presentation?.id == original.id else { return }; retire()
    }
    func retire() { generation = UUID(); review = nil; presentation = nil }
}
