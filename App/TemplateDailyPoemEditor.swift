import SwiftUI
import Combine

@MainActor final class TemplateDailyPoemController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID()
    private var actionGeneration = UUID()
    private var textGeneration = UUID()
    private var writing = false
    private var publicationObservation: AnyCancellable?
    private var draftObservation: AnyCancellable?
    @Published private var active = false
    @Published private var pool: TemplateDailyPoemPool
    @Published private(set) var needsReload = false

    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        pool = .init(model.draft.advanced); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.actionGeneration = UUID()
            if !self.writing && (!self.canReload || self.mediaGeneration != self.model.mediaReviewGeneration) { self.invalidate() }
        }
        // Parent Form calls changed() again from onChange(draft). Those review/revision
        // publications must not discard raw textarea state. Actual external draft emissions
        // (including an equal-value assignment) still retire text and require reload.
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in
            guard let self, !self.writing else { return }; self.invalidate()
        }
    }
    var canReload: Bool {
        model.canReadStoryDraft && session != nil && model.coordinator.session == session && model.coordinator.identity == identity
    }
    private var hasLease: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && pool.isCurrent(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && pool.canEdit }
    var isSupported: Bool { hasLease && pool.isSupported }
    var canAdd: Bool { canEdit && pool.canAdd }
    var rows: [TemplateDailyPoemPool.Row] { hasLease ? pool.rows : [] }
    var issues: [TemplateCreatorIssue] {
        hasLease ? model.draft.advanced.creatorIssues(.dailySign).filter { $0.path == "poems" || $0.path.hasPrefix("poems[") } : []
    }
    func reload() {
        actionGeneration = UUID(); textGeneration = UUID()
        guard canReload else { active = false; needsReload = true; return }
        pool = .init(model.draft.advanced); mediaGeneration = model.mediaReviewGeneration; active = true; needsReload = false
    }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID() }
    private func invalidate() { retire(); needsReload = true }
    func addAction() -> () -> Void { action(.add) }
    func removeAction(_ id: UUID) -> () -> Void { action(.remove(id)) }
    private func action(_ edit: TemplateDailyPoemPool.Edit) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, captured = pool
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let update = captured.applying(edit, to: self.model.draft.advanced) else { return }
            self.textGeneration = UUID(); self.apply(update)
        }
    }
    func text(_ id: UUID) -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp else { return "" }
            return self.pool.rows.first(where: { $0.id == id })?.text ?? ""
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp,
                  let update = self.pool.applying(.text(id, text), to: self.model.draft.advanced) else { return }
            self.apply(update)
        })
    }
    private func apply(_ update: TemplateDailyPoemPool.Update) {
        // A raw-only newline edit must also retire old buttons, even when wire bytes are unchanged.
        actionGeneration = UUID(); writing = true; defer { writing = false }
        pool = update.pool
        if !update.pool.isCurrent(model.draft.advanced) { model.draft.advanced = update.draft; model.changed() }
    }
}

@MainActor struct TemplateDailyPoemEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateDailyPoemController
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templatePoems.instructions").font(.callout)
                if editor.needsReload {
                    Text("templatePoems.changed").font(.caption)
                    Button("templatePoems.reload") { editor.reload() }.disabled(!editor.canReload)
                        .accessibilityIdentifier("creator.poems.reload")
                } else if !editor.isSupported { Text("templatePoems.unsupported").font(.caption) }
            }
            ForEach(Array(editor.rows.enumerated()), id: \.element.id) { index, row in
                Section {
                    HStack {
                        Text("templatePoems.number \(index + 1)").font(.headline)
                        Spacer()
                        Button("creator.remove", role: .destructive, action: editor.removeAction(row.id))
                            .accessibilityIdentifier("creator.poems.remove.\(index)")
                    }
                    TextEditor(text: editor.text(row.id)).frame(minHeight: 132)
                        .accessibilityLabel("templatePoems.input").accessibilityIdentifier("creator.poems.input.\(index)")
                    let lines = TemplateDailyPoemPool.lines(row.text)
                    Text("templatePoems.lineCount \(lines.count)").font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("templatePoems.preview") {
                        if lines.isEmpty { Text("templatePoems.empty").font(.caption) }
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line) }
                    }
                }.disabled(!editor.canEdit)
            }
            Section {
                Button("templatePoems.add", systemImage: "plus", action: editor.addAction())
                    .disabled(!editor.canAdd).accessibilityIdentifier("creator.poems.add")
                if editor.rows.isEmpty && !editor.needsReload { Text("templatePoems.empty").font(.caption) }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } }
                }
            }
        }.navigationTitle("templatePoems.title")
            .onAppear { editor.reload() }.onDisappear { editor.retire() }
    }
}
