import SwiftUI
import Combine

@MainActor final class TemplateOptionalModuleController: ObservableObject {
    struct Review: Identifiable {
        let id = UUID()
        let module: TemplateOptionalModules.Module
        let fields: [TemplateOptionalModules.Field]
        fileprivate let generation: UUID
    }
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), generation = UUID()
    private var active = false, writing = false
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?
    @Published private var scope: TemplateOptionalModules
    @Published private var review: Review?
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        scope = .init(model.draft); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] in
            guard let self, !self.writing else { return }
            self.generation = UUID(); self.review = nil
            if !self.canReload { self.suspend() }
        }
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in
            guard let self, !self.writing else { return }; self.suspend()
        }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && session == model.coordinator.session && identity == model.coordinator.identity && model.canEdit && !model.busy && model.review == nil }
    var canEdit: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && scope.isCurrent(model.draft) }
    var currentReview: Review? { guard let review, canEdit, review.generation == generation else { return nil }; return review }
    func enabled(_ module: TemplateOptionalModules.Module) -> Bool { canEdit && scope.enabled(module) }
    func canRemove(_ module: TemplateOptionalModules.Module) -> Bool { canEdit && scope.canRemove(module) }
    func reload() { generation = UUID(); review = nil; scope = .init(model.draft); mediaGeneration = model.mediaReviewGeneration; active = canReload; needsReload = !active }
    func retire() { generation = UUID(); review = nil; active = false }
    func suspend() { retire(); needsReload = true }
    func removalAction(_ module: TemplateOptionalModules.Module) -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.generation == stamp, self.model.metadataGeneration == metadata, self.canRemove(module), self.review == nil else { return }
            self.review = .init(module: module, fields: self.scope.fields(module), generation: self.generation)
        }
    }
    func addAction(_ module: TemplateOptionalModules.Module) -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.generation == stamp, self.model.metadataGeneration == metadata, self.canEdit, self.review == nil, !self.scope.enabled(module) else { return }
            self.apply(.add(module))
        }
    }
    func cancel(_ original: Review) { guard currentReview?.id == original.id else { return }; generation = UUID(); review = nil }
    func confirm(_ original: Review) {
        guard currentReview?.id == original.id, original.generation == generation else { return }
        apply(.remove(original.module))
    }
    func dismiss(_ original: Review?) { guard let original else { return }; cancel(original) }
    func saveAction() -> () -> Void {
        let stamp = generation, metadata = model.metadataGeneration
        return { [weak self] in
            guard let self, self.generation == stamp, self.model.metadataGeneration == metadata, self.canEdit, self.review == nil else { return }
            self.model.save()
        }
    }
    private func apply(_ change: TemplateOptionalModules.Change) {
        guard canEdit else { return }
        generation = UUID(); review = nil; writing = true; defer { writing = false }
        guard model.commitOptionalModuleChange(change, matching: scope) else { suspend(); return }
        scope = .init(model.draft); mediaGeneration = model.mediaReviewGeneration; active = canReload; needsReload = !active
    }
}

@MainActor struct TemplateOptionalModuleManager: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateOptionalModuleController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let presented = editor.currentReview
        Form {
            Section {
                Text("templateModules.instructions").font(.callout)
                if editor.needsReload {
                    Text("templateModules.changed").font(.caption)
                    Button("templateModules.reload") { editor.reload() }.disabled(!editor.canReload)
                }
            }
            ForEach(TemplateOptionalModules.Module.allCases) { module in
                Section(LocalizedStringKey(module.labelKey)) {
                    if editor.canEdit {
                        Text(LocalizedStringKey(editor.enabled(module) ? "templateModules.enabled" : "templateModules.available")).font(.caption)
                        if !editor.enabled(module) {
                            Button("templateModules.add", systemImage: "plus", action: editor.addAction(module)).accessibilityIdentifier("templateModules.add." + module.rawValue)
                        }
                    }
                    Button("templateModules.inspect", role: .destructive, action: editor.removalAction(module))
                        .disabled(!editor.canRemove(module)).accessibilityIdentifier("templateModules.inspect." + module.rawValue)
                }.disabled(!editor.canEdit)
            }
            Section {
                Button("templateAuthor.saveLocal", action: editor.saveAction()).disabled(!editor.canEdit || !model.draft.canSave)
                    .accessibilityIdentifier("templateModules.saveLocal")
                Text("templateModules.savedScope").font(.caption)
            }
        }.navigationTitle("templateModules.title")
            .sheet(item: Binding(get: { editor.currentReview }, set: { _ in editor.dismiss(presented) })) { original in
                NavigationStack {
                    Form {
                        if editor.currentReview?.id == original.id {
                            Section(LocalizedStringKey(original.module.labelKey)) {
                                Text("templateModules.removeNotice")
                                if original.module == .story { Text("templateModules.storyNotice").font(.caption) }
                                if original.module == .reward { Text("templateModules.rewardNotice").font(.caption) }
                                ForEach(original.fields) { field in
                                    VStack(alignment: .leading) {
                                        Text(LocalizedStringKey(field.labelKey)).font(.headline)
                                        if field.value.isEmpty { Text("templateModules.empty").foregroundStyle(.secondary) }
                                        else { Text(verbatim: field.value).textSelection(.enabled) }
                                    }
                                }
                            }
                            Button("templateModules.confirm", role: .destructive) { editor.confirm(original) }
                                .accessibilityIdentifier("templateModules.confirm")
                        } else { Text("templateModules.changed") }
                    }.navigationTitle("templateModules.review")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("templateAuthor.cancel") { editor.cancel(original) } } }
                }
            }
            .onDisappear { editor.retire() }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { editor.suspend() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.suspend() } }
    }
}
