import SwiftUI

@MainActor final class TemplateChoiceOptionRowsEditor: ObservableObject {
    typealias Letter = TemplateChoiceOptionMedia.Letter
    let model: TemplateAuthoringModel
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var mediaGeneration: UUID?
    private var methodGeneration: UUID?
    private var generation = 0
    private var active = false
    @Published private(set) var revision = 0
    init(model: TemplateAuthoringModel) { self.model = model; reload() }
    var canRead: Bool {
        active && model.canReadStoryDraft && session == model.coordinator.session && identity == model.coordinator.identity &&
            mediaGeneration == model.mediaReviewGeneration && methodGeneration == model.legacyHintGeneration &&
            model.draft.finishEnabled && model.draft.validationMethod == .choice
    }
    var canEdit: Bool { canRead && model.canEdit }
    var rows: TemplateChoiceOptionRows { .init(draft: model.draft) }
    var letters: [Letter] { canRead ? rows.letters : [] }
    func reload() {
        generation += 1; active = true
        session = model.coordinator.session; identity = model.coordinator.identity
        mediaGeneration = model.mediaReviewGeneration; methodGeneration = model.legacyHintGeneration
        revision += 1
    }
    func retire() { generation += 1; active = false; revision += 1 }
    func text(_ letter: Letter) -> Binding<String> {
        let stamp = generation
        return .init(get: {
            guard self.generation == stamp, self.canRead, self.letters.contains(letter) else { return "" }
            return self.model.draft[keyPath: TemplateChoiceOptionRows.path(letter)] ?? ""
        }, set: { value in
            guard self.generation == stamp, self.canEdit, self.letters.contains(letter) else { return }
            self.model.draft[keyPath: TemplateChoiceOptionRows.path(letter)] = value
            self.model.changed()
        })
    }
    func attachment(_ letter: Letter, _ kind: TemplateChoiceOptionMedia.Kind) -> Binding<String> {
        let stamp = generation, original = model.optionMedia(letter, kind)
        return .init(get: {
            guard self.generation == stamp, self.canRead, self.letters.contains(letter) else { return "" }
            return original.wrappedValue
        }, set: { value in
            guard self.generation == stamp, self.canEdit, self.letters.contains(letter) else { return }
            original.wrappedValue = value
        })
    }
    func answer() -> Binding<String> {
        let stamp = generation
        return .init(get: { self.generation == stamp && self.canRead ? self.model.draft.correctAnswer ?? "" : "" }, set: { value in
            guard self.generation == stamp, self.canEdit,
                  value.isEmpty || self.letters.contains(where: { $0.rawValue == value }) else { return }
            self.model.draft.correctAnswer = value.isEmpty ? nil : value
            self.model.changed()
        })
    }
    func action(_ edit: TemplateChoiceOptionRows.Edit) -> () -> Void {
        let stamp = generation, mutation = model.metadataGeneration, original = rows
        return { [weak self] in
            guard let self, self.generation == stamp, self.canEdit, self.model.metadataGeneration == mutation,
                  let next = original.applying(edit, to: self.model.draft) else { return }
            // Retire old row callbacks and pending media review before letters can move.
            self.generation += 1
            self.model.mediaReferencesWillChange()
            self.model.draft = next
            self.model.changed(); self.revision += 1
        }
    }
}

@MainActor struct TemplateChoiceOptionRowsFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateChoiceOptionRowsEditor
    init(model: TemplateAuthoringModel) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("templateChoiceRows.count", value: "\(editor.letters.count) / 4")
            Text("templateAuthor.optionMedia.scope").font(.caption).foregroundStyle(.secondary)
            if !model.draft.choiceOptionMedia.isSupported {
                Text("templateAuthor.optionMedia.unsupported").accessibilityIdentifier("templateAuthor.optionMedia.unsupported")
            }
            if !editor.rows.supportsReordering {
                Text("templateChoiceRows.reorderUnavailable").font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("templateChoiceRows.reorderUnavailable")
            }
            if let issue = model.optionMediaIssue {
                Text(LocalizedStringKey(issue)).foregroundStyle(.red).accessibilityIdentifier("templateAuthor.optionMedia.limit")
            }
            ForEach(editor.letters) { letter in
                VStack(alignment: .leading, spacing: 6) {
                    TemplateAuthoringField("question" + letter.rawValue, text: editor.text(letter),
                        accessibilityID: "templateChoiceRows.text." + letter.rawValue)
                    ForEach(TemplateChoiceOptionMedia.Kind.allCases) { kind in
                        TextField(LocalizedStringKey(kind.labelKey), text: editor.attachment(letter, kind))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .disabled(!model.draft.choiceOptionMedia.isSupported)
                            .accessibilityIdentifier("templateAuthor.optionMedia." + letter.rawValue + "." + kind.rawValue)
                    }
                    Button("templateChoiceRows.remove", role: .destructive, action: editor.action(.remove(letter)))
                        .disabled(!editor.rows.canRemove)
                        .accessibilityLabel(Text("templateChoiceRows.removeLetter \(letter.rawValue)"))
                        .accessibilityIdentifier("templateChoiceRows.remove." + letter.rawValue)
                }
            }
            Button("templateChoiceRows.add", systemImage: "plus", action: editor.action(.add))
                .disabled(!editor.rows.canAdd).accessibilityIdentifier("templateChoiceRows.add")
            Picker("templateAuthor.field.correctAnswer", selection: editor.answer()) {
                Text("templateAuthor.choose").tag("")
                ForEach(editor.letters) { letter in Text(verbatim: letter.rawValue).tag(letter.rawValue) }
                if let raw = model.draft.correctAnswer, !raw.isEmpty, !editor.letters.contains(where: { $0.rawValue == raw }) {
                    Text(verbatim: raw).tag(raw)
                }
            }.accessibilityIdentifier("templateChoiceRows.correctAnswer")
        }.buttonStyle(.borderless).disabled(!editor.canEdit)
            .onAppear { editor.reload() }
            .onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
            .onChange(of: model.legacyHintGeneration) { _, _ in editor.reload() }
    }
}
