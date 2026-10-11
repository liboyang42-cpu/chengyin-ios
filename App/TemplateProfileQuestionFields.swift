import SwiftUI
import Combine

@MainActor final class TemplateProfileQuestionController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let questionIndex: Int?
    private let questionKey: String?
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID()
    private var generation = UUID()
    private var observation: AnyCancellable?
    @Published private var active = false
    init(model: TemplateAuthoringModel, questionIndex: Int? = nil) {
        self.model = model; self.questionIndex = questionIndex
        let questions = TemplateProfileQuestionComposition(model.draft.advanced).questions
        questionKey = questionIndex.flatMap { questions.indices.contains($0) ? questions[$0].key : nil }
        session = model.coordinator.session; identity = model.coordinator.identity; reload()
        observation = model.objectWillChange.sink { [weak self] _ in self?.generation = UUID() }
    }
    private var projection: TemplateProfileQuestionComposition { .init(model.draft.advanced) }
    private var hasLease: Bool {
        guard active, model.canReadStoryDraft, session != nil, model.coordinator.session == session,
              model.coordinator.identity == identity, mediaGeneration == model.mediaReviewGeneration else { return false }
        guard let questionIndex else { return true }
        return projection.questions.indices.contains(questionIndex) && projection.questions[questionIndex].key == questionKey
    }
    var canEdit: Bool { hasLease && model.canEdit && projection.canEdit }
    var canEditList: Bool { canEdit && (questionIndex == nil || kind == "pick") }
    var kind: String { hasLease ? projection.questions.first(where: { $0.key == questionKey })?.kind ?? "" : "" }
    var entries: [TemplateProfileQuestionComposition.Entry] {
        guard hasLease else { return [] }
        if let questionKey { return projection.questions.first(where: { $0.key == questionKey })?.options ?? [] }
        return projection.questions.map { .init(key: $0.key, label: $0.label) }
    }
    var canAdd: Bool { canEditList && (questionKey.map { projection.canAddOption($0) } ?? projection.canAddQuestion) }
    var canRemove: Bool { canEditList && entries.count > (questionIndex == nil ? 1 : 2) }
    func reload() { generation = UUID(); mediaGeneration = model.mediaReviewGeneration; active = true }
    func retire() { active = false; generation = UUID() }
    func kindBinding() -> Binding<String> {
        let stamp = generation, text = kindAction("text"), pick = kindAction("pick")
        return .init(get: { [weak self] in guard let self, self.generation == stamp else { return "" }; return self.kind },
                     set: { if $0 == "text" { text() } else if $0 == "pick" { pick() } })
    }
    func kindAction(_ kind: String) -> () -> Void {
        guard let questionKey else { return {} }; return action(.kind(questionKey, kind))
    }
    func addAction() -> () -> Void {
        if let questionKey { return action(.addOption(questionKey)) }; return action(.addQuestion)
    }
    private func action(_ edit: TemplateProfileQuestionComposition.Edit) -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration, snapshot = projection
        return { [weak self] in
            guard let self, self.canEdit, self.generation == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }; self.apply(next)
        }
    }
    func removeAction() -> (IndexSet) -> Void {
        let stamp = generation, metadata = model.metadataGeneration, snapshot = projection, key = questionKey
        return { [weak self] offsets in
            guard let self, self.canEditList, self.generation == stamp, self.model.metadataGeneration == metadata else { return }
            let edit: TemplateProfileQuestionComposition.Edit = key.map { .removeOptions($0, Array(offsets)) } ?? .removeQuestions(Array(offsets))
            guard let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }; self.apply(next)
        }
    }
    func moveAction() -> (IndexSet, Int) -> Void {
        let stamp = generation, metadata = model.metadataGeneration, snapshot = projection, key = questionKey
        return { [weak self] offsets, destination in
            guard let self, self.canEditList, self.generation == stamp, self.model.metadataGeneration == metadata else { return }
            let edit: TemplateProfileQuestionComposition.Edit = key.map { .moveOptions($0, Array(offsets), destination) } ?? .moveQuestions(Array(offsets), destination)
            guard let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }; self.apply(next)
        }
    }
    private func apply(_ next: TemplateAdvancedDraft) {
        guard next != model.draft.advanced else { return }; model.draft.advanced = next; model.changed()
    }
}

@MainActor struct TemplateProfileKindFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateProfileQuestionController
    init(model: TemplateAuthoringModel, questionIndex: Int) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model, questionIndex: questionIndex)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("creator.field.kind", selection: editor.kindBinding()) {
                Text("creator.choice.text").tag("text"); Text("creator.choice.pick").tag("pick")
            }.accessibilityIdentifier("creator.profile.kind")
            Text("templateProfile.kindHint").font(.caption).foregroundStyle(.secondary)
        }.disabled(!editor.canEdit)
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}

/// Reuses the original field renderer as each row's destination; effects/override are not duplicated.
@MainActor struct TemplateProfileQuestionRowsEditor<RowContent: View>: View {
    @ObservedObject var model: TemplateAuthoringModel
    let questionIndex: Int?
    private let rowContent: (Int) -> RowContent
    @StateObject private var editor: TemplateProfileQuestionController
    init(model: TemplateAuthoringModel, questionIndex: Int?, @ViewBuilder rowContent: @escaping (Int) -> RowContent) {
        self.model = model; self.questionIndex = questionIndex; self.rowContent = rowContent
        _editor = StateObject(wrappedValue: .init(model: model, questionIndex: questionIndex))
    }
    var body: some View {
        List {
            Text(LocalizedStringKey(questionIndex == nil ? "templateProfile.questionsHint" : "templateProfile.optionsHint")).font(.caption)
            ForEach(Array(editor.entries.enumerated()), id: \.element.key) { index, entry in
                NavigationLink { rowContent(index) } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: entry.label.isEmpty ? entry.key : entry.label)
                        Text(verbatim: entry.key).font(.caption).foregroundStyle(.secondary)
                    }
                }.deleteDisabled(!editor.canRemove).moveDisabled(!editor.canEditList)
            }.onDelete(perform: editor.removeAction()).onMove(perform: editor.moveAction())
            Button(LocalizedStringKey(questionIndex == nil ? "templateProfile.addQuestion" : "templateProfile.addOption"), systemImage: "plus", action: editor.addAction())
                .disabled(!editor.canAdd).accessibilityIdentifier(questionIndex == nil ? "creator.profile.addQuestion" : "creator.profile.addOption")
            if !editor.canEditList { Text("templateProfile.reopen").font(.caption) }
        }.disabled(!editor.canEditList).toolbar { EditButton() }
            .navigationTitle(LocalizedStringKey(questionIndex == nil ? "creator.field.questions" : "creator.field.options"))
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}
