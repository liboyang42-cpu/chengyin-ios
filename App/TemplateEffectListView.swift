import SwiftUI
import Combine

@MainActor final class TemplateEffectListController: ObservableObject {
    private let model: TemplateAuthoringModel
    let family: TemplateCreatorFamily
    let path: [TemplateCreatorPath]
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private let scopeFingerprint: Data?
    private var mediaGeneration = UUID()
    private var actionGeneration = UUID()
    private var textGeneration = UUID()
    private var writingText = false
    private var observation: AnyCancellable?
    @Published private var active = false

    init(model: TemplateAuthoringModel, family: TemplateCreatorFamily, path: [TemplateCreatorPath]) {
        self.model = model; self.family = family; self.path = path
        session = model.coordinator.session; identity = model.coordinator.identity
        scopeFingerprint = TemplateEffectList(model.draft.advanced, family: family, path: path).scopeFingerprint
        reload()
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.actionGeneration = UUID()
            if !self.writingText { self.textGeneration = UUID() }
        }
    }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && model.coordinator.session == session &&
            model.coordinator.identity == identity && model.mediaReviewGeneration == mediaGeneration &&
            scopeFingerprint != nil && projection.scopeFingerprint == scopeFingerprint
    }
    private var projection: TemplateEffectList { .init(model.draft.advanced, family: family, path: path) }
    var canEdit: Bool { hasLease && model.canEdit && projection.canEdit }
    var canAdd: Bool { canEdit && projection.canAdd }
    var needsReopen: Bool { !hasLease }
    var rows: [TemplateEffectList.Row] { hasLease ? projection.rows : [] }
    var issues: [TemplateCreatorIssue] {
        guard hasLease else { return [] }
        let prefix = projection.validationPrefix
        return model.draft.advanced.creatorIssues(family).filter { $0.path == prefix || $0.path.hasPrefix(prefix + "[") }
    }
    func reload() {
        actionGeneration = UUID(); textGeneration = UUID()
        mediaGeneration = model.mediaReviewGeneration; active = true
    }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID() }
    func addAction() -> () -> Void { action(.add) }
    func removeAction(_ index: Int) -> () -> Void { action(.remove(index)) }
    func moveAction(_ from: Int, _ to: Int) -> () -> Void { action(.move(from, to)) }
    private func action(_ edit: TemplateEffectList.Edit) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = projection
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(edit, to: self.model.draft.advanced) else { return }
            self.apply(next)
        }
    }
    func operation(_ index: Int) -> Binding<String> {
        let stamp = actionGeneration, choices = Dictionary(uniqueKeysWithValues: TemplateEffectList.operations.map { ($0, action(.operation(index, $0))) })
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.actionGeneration == stamp, self.rows.indices.contains(index) else { return "" }
            return self.rows[index].operation
        }, set: { value in choices[value]?() })
    }
    func input(_ index: Int, _ field: TemplateEffectList.Input) -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp, self.rows.indices.contains(index) else { return "" }
            switch field { case .variable: return self.rows[index].variable; case .value: return self.rows[index].input }
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp,
                  let next = self.projection.applying(.input(index, field, text), to: self.model.draft.advanced) else { return }
            self.writingText = true; defer { self.writingText = false }
            self.apply(next)
        })
    }
    private func apply(_ next: TemplateAdvancedDraft) {
        guard next != model.draft.advanced else { return }
        model.draft.advanced = next; model.changed()
    }
}

@MainActor struct TemplateEffectListView: View {
    @ObservedObject var model: TemplateAuthoringModel
    let titleKey: String
    @StateObject private var editor: TemplateEffectListController
    init(model: TemplateAuthoringModel, family: TemplateCreatorFamily, path: [TemplateCreatorPath], titleKey: String) {
        self.model = model; self.titleKey = titleKey
        _editor = StateObject(wrappedValue: .init(model: model, family: family, path: path))
    }
    var body: some View {
        Form {
            Section {
                Text("templateEffects.scope").font(.caption)
                if editor.needsReopen { Text("templateEffects.reopen").accessibilityIdentifier("creator.effects.reopen") }
            }
            ForEach(editor.rows) { row in
                Section {
                    Text("templateEffects.rowNumber \(row.id + 1)").font(.headline)
                    Picker("creator.field.op", selection: editor.operation(row.id)) {
                        if !TemplateEffectList.operations.contains(row.operation) {
                            if row.operation.isEmpty { Text("creator.choose").tag("") }
                            else { Text(verbatim: row.operation).tag(row.operation) }
                        }
                        ForEach(TemplateEffectList.operations, id: \.self) { operation in
                            Text(LocalizedStringKey("creator.choice." + operation)).tag(operation)
                        }
                    }.accessibilityIdentifier("creator.effects.operation.\(row.id)")
                    if TemplateEffectList.operations.contains(row.operation) {
                        if row.operation != "ADD_TAG" {
                            TextField("creator.field.var", text: editor.input(row.id, .variable))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("creator.effects.variable.\(row.id)")
                            Text("templateEffects.variableHint").font(.caption).foregroundStyle(.secondary)
                        }
                        TextField(LocalizedStringKey(row.operation == "ADD_TAG" ? "creator.field.tagValue" : "creator.field.value"), text: editor.input(row.id, .value))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(row.operation == "ADD_TAG" ? .default : .numbersAndPunctuation)
                            .accessibilityIdentifier("creator.effects.value.\(row.id)")
                        Text(LocalizedStringKey(row.operation == "ADD_TAG" ? "templateEffects.tagHint" : "templateEffects.numberHint"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(action: editor.moveAction(row.id, row.id - 1)) { Label("playkit.sort.up", systemImage: "arrow.up") }.disabled(row.id == 0)
                        Button(action: editor.moveAction(row.id, row.id + 1)) { Label("playkit.sort.down", systemImage: "arrow.down") }.disabled(row.id == editor.rows.count - 1)
                        Spacer()
                        Button("creator.remove", role: .destructive, action: editor.removeAction(row.id))
                            .accessibilityIdentifier("creator.effects.remove.\(row.id)")
                    }.buttonStyle(.borderless)
                }
            }
            Section {
                Button("templateEffects.add", systemImage: "plus", action: editor.addAction())
                    .disabled(!editor.canAdd).accessibilityIdentifier("creator.effects.add")
                if editor.rows.isEmpty { Text("templateEffects.empty").font(.caption) }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(editor.issues) { issue in
                        VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) }
                    }
                }
            }
        }.navigationTitle(LocalizedStringKey(titleKey)).disabled(!editor.canEdit)
            .onAppear { editor.reload() }
            .onDisappear { editor.retire() }
            .onChange(of: model.mediaReviewGeneration) { _, _ in editor.reload() }
    }
}
