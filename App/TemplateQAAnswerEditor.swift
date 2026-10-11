import SwiftUI
import Combine

/// Retires captured controls synchronously on every model publication, including mode/list ABA edits.
@MainActor final class TemplateQAAnswerEditor: ObservableObject {
    private let model: TemplateAuthoringModel
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var mediaGeneration = UUID()
    private var generation = UUID()
    @Published private var active = false
    private var observation: AnyCancellable?

    init(model: TemplateAuthoringModel) {
        self.model = model
        reload()
        observation = model.objectWillChange.sink { [weak self] _ in self?.generation = UUID() }
    }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && model.coordinator.session == session &&
            model.coordinator.identity == identity && model.mediaReviewGeneration == mediaGeneration
    }
    private var selection: TemplateQAAnswerSelection { .init(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && selection.canEdit }
    var isSupported: Bool { hasLease && selection.isSupported }
    var isMultiple: Bool { hasLease && selection.isMultiple }
    var options: [TemplateQAAnswerSelection.Option] { hasLease ? selection.options : [] }

    func reload() {
        generation = UUID()
        session = model.coordinator.session; identity = model.coordinator.identity
        mediaGeneration = model.mediaReviewGeneration
        active = true
    }
    func retire() { active = false; generation = UUID() }

    func chooseAction(_ index: Int) -> () -> Void { action(.choose(index)) }
    func multiple() -> Binding<Bool> {
        let stamp = generation, snapshot = selection
        let changeOn = action(.setMultiple(true)), changeOff = action(.setMultiple(false))
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.generation == stamp else { return false }
            return self.isMultiple
        }, set: { enabled in
            guard enabled != snapshot.isMultiple else { return }
            if enabled { changeOn() } else { changeOff() }
        })
    }
    private func action(_ edit: TemplateQAAnswerSelection.Edit) -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration, snapshot = selection
        return { [weak self] in
            guard let self, self.canEdit, self.generation == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced), next != self.model.draft.advanced else { return }
            self.model.draft.advanced = next
            self.model.changed()
        }
    }
}

@MainActor struct TemplateQAAnswerFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateQAAnswerEditor
    init(model: TemplateAuthoringModel) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("templateQAAnswers.title").font(.headline)
            if editor.isSupported {
                Toggle("creator.field.multi", isOn: editor.multiple())
                    .accessibilityIdentifier("creator.qa.answers.multiple")
                Text(LocalizedStringKey(editor.isMultiple ? "templateQAAnswers.multipleHint" : "templateQAAnswers.singleHint"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(editor.options) { option in
                    Button(action: editor.chooseAction(option.id)) {
                        HStack(alignment: .top) {
                            Image(systemName: editor.isMultiple ? (option.correct ? "checkmark.square.fill" : "square") :
                                (option.correct ? "largecircle.fill.circle" : "circle"))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text("templateQAAnswers.optionNumber \(option.id + 1)").font(.caption)
                                if option.label.isEmpty { Text("templateQAAnswers.emptyLabel") }
                                else { Text(verbatim: option.label) }
                            }
                            Spacer()
                        }.contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("creator.qa.answers.option.\(option.id)")
                        .accessibilityValue(Text(LocalizedStringKey(option.correct ? "templateQAAnswers.selected" : "templateQAAnswers.notSelected")))
                        .accessibilityAddTraits(option.correct ? [.isSelected] : [])
                }
                if !editor.options.contains(where: \.correct) {
                    Text("templateQAAnswers.noAnswer").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("creator.qa.answers.noAnswer")
                }
            } else { Text("templateQAAnswers.unsupported").font(.caption).accessibilityIdentifier("creator.qa.answers.unsupported") }
        }.disabled(!editor.canEdit)
            .onAppear { editor.reload() }
            .onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}
