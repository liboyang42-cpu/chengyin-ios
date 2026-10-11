import SwiftUI
import Combine

@MainActor final class TemplateBranchCompositionController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let stepIndex: Int?
    private let stepID: String?
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID()
    private var generation = UUID()
    private var observation: AnyCancellable?
    @Published private var active = false

    init(model: TemplateAuthoringModel, stepIndex: Int? = nil) {
        self.model = model; self.stepIndex = stepIndex
        let steps = TemplateBranchComposition(model.draft.advanced).steps
        stepID = stepIndex.flatMap { steps.indices.contains($0) ? steps[$0].id : nil }
        session = model.coordinator.session; identity = model.coordinator.identity
        reload()
        observation = model.objectWillChange.sink { [weak self] _ in self?.generation = UUID() }
    }
    private var projection: TemplateBranchComposition { .init(model.draft.advanced) }
    private var hasLease: Bool {
        guard active, model.canReadStoryDraft, session != nil, model.coordinator.session == session,
              model.coordinator.identity == identity, mediaGeneration == model.mediaReviewGeneration else { return false }
        guard let stepIndex else { return true }
        return projection.steps.indices.contains(stepIndex) && projection.steps[stepIndex].id == stepID
    }
    var canEdit: Bool { hasLease && model.canEdit && projection.canEdit }
    var terminal: Bool { hasLease && projection.steps.first(where: { $0.id == stepID })?.terminal == true }
    var canAdd: Bool { canEdit && (stepID.map { projection.canAddOption($0) } ?? projection.canAddStep) }
    func reload() { generation = UUID(); mediaGeneration = model.mediaReviewGeneration; active = true }
    func retire() { active = false; generation = UUID() }
    func terminalBinding() -> Binding<Bool> {
        let stamp = generation, enable = terminalAction(true), disable = terminalAction(false)
        return .init(get: { [weak self] in guard let self, self.generation == stamp else { return false }; return self.terminal },
                     set: { $0 ? enable() : disable() })
    }
    func terminalAction(_ value: Bool) -> () -> Void {
        guard let stepID else { return {} }; return action(.terminal(stepID, value))
    }
    func addAction() -> () -> Void {
        if let stepID { return action(.addOption(stepID: stepID, optionID: "option_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))) }
        return action(.addStep("step_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")))
    }
    private func action(_ edit: TemplateBranchComposition.Edit) -> () -> Void {
        let stamp = generation, snapshot = projection, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.canEdit, self.generation == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced), next != self.model.draft.advanced else { return }
            self.model.draft.advanced = next; self.model.changed()
        }
    }
}

@MainActor struct TemplateBranchTerminalFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateBranchCompositionController
    init(model: TemplateAuthoringModel, stepIndex: Int) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model, stepIndex: stepIndex))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("creator.field.terminal", isOn: editor.terminalBinding()).accessibilityIdentifier("creator.branch.terminal")
            Text("templateBranch.terminalHint").font(.caption).foregroundStyle(.secondary)
            if editor.terminal {
                Button("templateBranch.continueWithChoice", systemImage: "arrow.triangle.branch", action: editor.addAction())
                    .disabled(!editor.canAdd).accessibilityIdentifier("creator.branch.continue")
            } else { Text("templateBranch.choiceHint").font(.caption).foregroundStyle(.secondary) }
        }.disabled(!editor.canEdit)
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}

@MainActor struct TemplateBranchAddRowButton: View {
    @ObservedObject var model: TemplateAuthoringModel
    let stepIndex: Int?
    @StateObject private var editor: TemplateBranchCompositionController
    init(model: TemplateAuthoringModel, stepIndex: Int? = nil) {
        self.model = model; self.stepIndex = stepIndex
        _editor = StateObject(wrappedValue: .init(model: model, stepIndex: stepIndex))
    }
    var body: some View {
        Button(LocalizedStringKey(stepIndex == nil ? "templateBranch.addStep" : "templateBranch.addChoice"), systemImage: "plus", action: editor.addAction())
            .disabled(!editor.canAdd).accessibilityIdentifier(stepIndex == nil ? "creator.branch.addStep" : "creator.branch.addChoice")
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}
