import SwiftUI
import Combine

@MainActor final class TemplateLegacyQuestionRehearsalController: ObservableObject {
    private enum Action { case select(TemplateLegacyQuestionRehearsal.Letter), hint, submit, restart }
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), actionGeneration = UUID(), inputGeneration = UUID()
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?, lockObservation: AnyCancellable?
    @Published private var active = false
    @Published private var rehearsal: TemplateLegacyQuestionRehearsal
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        rehearsal = .init(model.draft); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.actionGeneration = UUID()
            if !self.canReload || !self.model.canEdit || self.mediaGeneration != self.model.mediaReviewGeneration { self.suspend() }
        }
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in self?.suspend() }
        lockObservation = Publishers.CombineLatest(model.$busy, model.$review).dropFirst().sink { [weak self] value in
            if value.0 || value.1 != nil { self?.suspend() }
        }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && session == model.coordinator.session && identity == model.coordinator.identity }
    var canRead: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && rehearsal.isCurrent(model.draft) }
    var canInteract: Bool { canRead && model.canEdit && !model.busy && model.review == nil && rehearsal.isAvailable }
    var isConfigured: Bool { canRead && rehearsal.isConfigured }
    var canAttempt: Bool { canInteract && rehearsal.canAttempt }
    var canRevealHint: Bool { canInteract && rehearsal.canRevealHint }
    var method: TemplateAuthoringMethod { canRead ? rehearsal.method : .manual }
    var question: String { canRead ? rehearsal.question : "" }
    var options: [TemplateLegacyQuestionRehearsal.Option] { canRead ? rehearsal.options : [] }
    var selected: TemplateLegacyQuestionRehearsal.Letter? { canRead ? rehearsal.selected : nil }
    var state: TemplateLegacyQuestionRehearsal.State { canRead ? rehearsal.state : .ready }
    var visibleHint: String? { canRead && rehearsal.hintRevealed ? rehearsal.hint : nil }
    var acceptsAnyNonemptyAnswer: Bool { canRead && rehearsal.acceptsAnyNonemptyAnswer }
    func reload() {
        actionGeneration = UUID(); inputGeneration = UUID(); rehearsal = .init(model.draft)
        mediaGeneration = model.mediaReviewGeneration; active = canReload; needsReload = !active
    }
    func retire() { active = false; actionGeneration = UUID(); inputGeneration = UUID(); rehearsal.restart() }
    func suspend() { retire(); needsReload = true }
    func answerInput() -> Binding<String> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in guard let self, self.canRead, self.inputGeneration == stamp else { return "" }; return self.rehearsal.answer }, set: { [weak self] value in
            guard let self, self.canAttempt, self.inputGeneration == stamp else { return }
            self.actionGeneration = UUID(); self.rehearsal.setAnswer(value)
        })
    }
    func selectAction(_ letter: TemplateLegacyQuestionRehearsal.Letter) -> () -> Void { action(.select(letter)) }
    func hintAction() -> () -> Void { action(.hint) }
    func submitAction() -> () -> Void { action(.submit) }
    func restartAction() -> () -> Void { action(.restart) }
    private func action(_ value: Action) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.canInteract, self.actionGeneration == stamp, self.model.metadataGeneration == metadata else { return }
            self.actionGeneration = UUID()
            switch value {
            case .select(let letter): self.rehearsal.select(letter)
            case .hint: self.rehearsal.revealHint()
            case .submit: self.rehearsal.submit()
            case .restart: self.inputGeneration = UUID(); self.rehearsal.restart()
            }
        }
    }
}

@MainActor struct TemplateLegacyQuestionRehearsalView: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateLegacyQuestionRehearsalController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templateLegacyQuiz.scope").font(.callout)
                if editor.needsReload {
                    Text("templateLegacyQuiz.changed").font(.caption)
                    Button("templateLegacyQuiz.reload") { editor.reload() }.disabled(!editor.canReload)
                } else if !editor.isConfigured { Text("templateLegacyQuiz.incomplete").font(.caption) }
            }
            if editor.canRead {
                Section("templateLegacyQuiz.question") {
                    Text(verbatim: editor.question).font(.headline)
                    if editor.state == .completed {
                        Label("templateLegacyQuiz.completed", systemImage: "checkmark.circle").accessibilityIdentifier("templateLegacyQuiz.completed")
                        Text("templateLegacyQuiz.noAward").font(.caption)
                    } else {
                        if editor.method == .text {
                            TextField("templateLegacyQuiz.answer", text: editor.answerInput(), axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .disabled(!editor.canAttempt).accessibilityIdentifier("templateLegacyQuiz.answer")
                            if editor.acceptsAnyNonemptyAnswer { Text("templateLegacyQuiz.emptyAliases").font(.caption) }
                        } else if editor.method == .choice {
                            ForEach(editor.options) { option in
                                Button(action: editor.selectAction(option.letter)) {
                                    HStack {
                                        Text(verbatim: option.letter.rawValue)
                                        if option.text.isEmpty { Text("templateLegacyQuiz.blankOption") } else { Text(verbatim: option.text) }
                                        Spacer(); if editor.selected == option.letter { Image(systemName: "checkmark.circle.fill") }
                                    }
                                }.buttonStyle(.borderless).disabled(!editor.canAttempt)
                                    .accessibilityIdentifier("templateLegacyQuiz.option." + option.letter.rawValue)
                                    .accessibilityValue(editor.selected == option.letter ? Text("templateLegacyQuiz.selected") : Text("templateLegacyQuiz.unselected"))
                            }
                        }
                        if editor.state == .wrong { Text("templateLegacyQuiz.wrong").foregroundStyle(.red).accessibilityIdentifier("templateLegacyQuiz.wrong") }
                        if let hint = editor.visibleHint { Text(verbatim: hint).accessibilityIdentifier("templateLegacyQuiz.hintText") }
                        else if editor.canRevealHint { Button("templateLegacyQuiz.hint", action: editor.hintAction()).accessibilityIdentifier("templateLegacyQuiz.hint") }
                        Button("templateLegacyQuiz.submit", action: editor.submitAction()).disabled(!editor.canAttempt).accessibilityIdentifier("templateLegacyQuiz.submit")
                    }
                }
                Section { Button("templateLegacyQuiz.restart", action: editor.restartAction()).disabled(!editor.canInteract).accessibilityIdentifier("templateLegacyQuiz.restart") }
            }
        }.navigationTitle("templateLegacyQuiz.title")
            .onDisappear { editor.retire() }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { editor.suspend() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.suspend() } }
    }
}
