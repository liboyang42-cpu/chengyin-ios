import SwiftUI
import Combine

@MainActor final class TemplateBlindOptionEditor: ObservableObject {
    enum Field: Equatable { case key, label }
    private let model: TemplateAuthoringModel
    private var session: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var mediaGeneration = UUID()
    private var actionGeneration = UUID()
    private var textGeneration = UUID()
    private var writingText = false
    private var observation: AnyCancellable?
    @Published private var active = false

    init(model: TemplateAuthoringModel) {
        self.model = model; reload()
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.actionGeneration = UUID()
            // Own key/label typing keeps row positions stable. Every other publication retires fields.
            if !self.writingText { self.textGeneration = UUID() }
        }
    }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && model.coordinator.session == session &&
            model.coordinator.identity == identity && model.mediaReviewGeneration == mediaGeneration
    }
    private var selection: TemplateBlindOptions { .init(model.draft.advanced) }
    var isSupported: Bool { hasLease && selection.isSupported }
    var canEdit: Bool { hasLease && model.canEdit && selection.canEdit }
    var canAdd: Bool { canEdit && selection.canAdd }
    var rows: [TemplateBlindOptions.Row] { hasLease ? selection.rows : [] }
    func canChoose(_ index: Int) -> Bool { canEdit && selection.canChoose(index) }

    func reload() {
        actionGeneration = UUID(); textGeneration = UUID()
        session = model.coordinator.session; identity = model.coordinator.identity
        mediaGeneration = model.mediaReviewGeneration; active = true
    }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID() }
    func addAction() -> () -> Void { action(.add) }
    func removeAction(_ index: Int) -> () -> Void { action(.remove(index)) }
    func chooseAction(_ index: Int) -> () -> Void { action(.choose(index)) }
    func moveAction(_ from: Int, _ to: Int) -> () -> Void { action(.move(from, to)) }
    private func action(_ edit: TemplateBlindOptions.Edit) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = selection
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }
            self.apply(next)
        }
    }
    func text(_ index: Int, _ field: Field) -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp, self.rows.indices.contains(index) else { return "" }
            return field == .key ? self.rows[index].key : self.rows[index].label
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp else { return }
            let edit: TemplateBlindOptions.Edit = field == .key ? .updateKey(index, text) : .updateLabel(index, text)
            guard let next = self.selection.applying(edit, to: self.model.draft.advanced) else { return }
            self.writingText = true
            defer { self.writingText = false }
            self.apply(next)
        })
    }
    private func apply(_ next: TemplateAdvancedDraft) {
        guard next != model.draft.advanced else { return }
        model.draft.advanced = next; model.changed()
    }
}

@MainActor struct TemplateBlindOptionFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateBlindOptionEditor
    init(model: TemplateAuthoringModel) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("templateBlindOptions.title").font(.headline)
            if editor.isSupported {
                Text("templateBlindOptions.hint").font(.caption).foregroundStyle(.secondary)
                ForEach(editor.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("templateBlindOptions.optionNumber \(row.id + 1)").font(.subheadline)
                        TextField("creator.field.key", text: editor.text(row.id, .key))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("creator.blindOptions.key.\(row.id)")
                        TextField("creator.field.label", text: editor.text(row.id, .label), axis: .vertical)
                            .accessibilityIdentifier("creator.blindOptions.label.\(row.id)")
                        HStack {
                            Button(action: editor.moveAction(row.id, row.id - 1)) { Label("playkit.sort.up", systemImage: "arrow.up") }
                                .disabled(row.id == 0).accessibilityIdentifier("creator.blindOptions.up.\(row.id)")
                            Button(action: editor.moveAction(row.id, row.id + 1)) { Label("playkit.sort.down", systemImage: "arrow.down") }
                                .disabled(row.id == editor.rows.count - 1).accessibilityIdentifier("creator.blindOptions.down.\(row.id)")
                        }.buttonStyle(.borderless)
                        HStack {
                            Button(action: editor.chooseAction(row.id)) {
                                Label { Text(LocalizedStringKey(row.isAnswer ? "templateBlindOptions.selected" : "templateBlindOptions.choose")) }
                                    icon: { Image(systemName: row.isAnswer ? "largecircle.fill.circle" : "circle") }
                            }.disabled(!editor.canChoose(row.id))
                                .accessibilityIdentifier("creator.blindOptions.answer.\(row.id)")
                                .accessibilityAddTraits(row.isAnswer ? [.isSelected] : [])
                            Spacer()
                            Button("creator.remove", role: .destructive, action: editor.removeAction(row.id))
                                .accessibilityIdentifier("creator.blindOptions.remove.\(row.id)")
                                .accessibilityLabel(Text("templateBlindOptions.removeNumber \(row.id + 1)"))
                        }.buttonStyle(.borderless)
                    }
                }
                Button("templateBlindOptions.add", systemImage: "plus", action: editor.addAction())
                    .disabled(!editor.canAdd).accessibilityIdentifier("creator.blindOptions.add")
                if !editor.rows.contains(where: \.isAnswer) {
                    Text("templateBlindOptions.noAnswer").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("templateBlindOptions.unsupported").font(.caption).accessibilityIdentifier("creator.blindOptions.unsupported") }
        }.disabled(!editor.canEdit)
            .onAppear { editor.reload() }
            .onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}
