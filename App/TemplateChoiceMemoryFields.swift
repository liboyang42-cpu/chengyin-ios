import SwiftUI
import Combine

@MainActor final class TemplateChoiceMemoryController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let family: TemplateCreatorFamily
    private let optionPath: [TemplateCreatorPath]
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private let scopeFingerprint: Data?
    private var mediaGeneration = UUID(), actionGeneration = UUID()
    private var observation: AnyCancellable?
    @Published private var active = false
    init(model: TemplateAuthoringModel, family: TemplateCreatorFamily, optionPath: [TemplateCreatorPath]) {
        self.model = model; self.family = family; self.optionPath = optionPath
        session = model.coordinator.session; identity = model.coordinator.identity
        scopeFingerprint = TemplateChoiceMemory(model.draft.advanced, family: family, optionPath: optionPath).scopeFingerprint
        activate()
        observation = model.objectWillChange.sink { [weak self] _ in self?.actionGeneration = UUID() }
    }
    private var projection: TemplateChoiceMemory { .init(model.draft.advanced, family: family, optionPath: optionPath) }
    private var hasLease: Bool {
        active && model.canReadStoryDraft && session != nil && model.coordinator.session == session && model.coordinator.identity == identity &&
            model.mediaReviewGeneration == mediaGeneration && scopeFingerprint != nil && projection.scopeFingerprint == scopeFingerprint
    }
    var needsReopen: Bool { !hasLease }
    var canEdit: Bool { hasLease && model.canEdit && projection.canEdit }
    var isEnabled: Bool { hasLease && projection.isEnabled }
    var canEnable: Bool { canEdit && projection.canEnable }
    var canChange: Bool { canEdit && (isEnabled || canEnable) }
    var tags: [String] { hasLease ? projection.tags : [] }
    var otherEffectCount: Int { hasLease ? projection.otherEffectCount : 0 }
    func activate() { mediaGeneration = model.mediaReviewGeneration; actionGeneration = UUID(); active = true }
    func retire() { active = false; actionGeneration = UUID() }
    func setAction(_ enabled: Bool) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = projection
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let next = snapshot.applying(enabled: enabled, to: self.model.draft.advanced) else { return }
            self.actionGeneration = UUID(); self.model.draft.advanced = next; self.model.changed()
        }
    }
    func enabledInput() -> Binding<Bool> {
        let stamp = actionGeneration, enable = setAction(true), disable = setAction(false)
        return .init(get: { [weak self] in guard let self, self.hasLease, self.actionGeneration == stamp else { return false }; return self.isEnabled }, set: { $0 ? enable() : disable() })
    }
}

@MainActor struct TemplateChoiceMemoryFields: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateChoiceMemoryController
    init(model: TemplateAuthoringModel, family: TemplateCreatorFamily, optionPath: [TemplateCreatorPath]) {
        self.model = model; _editor = StateObject(wrappedValue: .init(model: model, family: family, optionPath: optionPath))
    }
    var body: some View {
        Section("templateMemo.title") {
            Toggle("templateMemo.remember", isOn: editor.enabledInput()).disabled(!editor.canChange).accessibilityIdentifier("creator.memo.toggle")
            Text("templateMemo.scope").font(.caption).foregroundStyle(.secondary)
            if editor.needsReopen { Text("templateMemo.reopen").font(.caption) }
            else {
                if !editor.isEnabled && editor.otherEffectCount >= 16 { Text("templateMemo.capacity").font(.caption) }
                if editor.tags.isEmpty { Text("templateMemo.off").font(.caption) }
                else {
                    ForEach(Array(editor.tags.enumerated()), id: \.offset) { _, tag in Text(verbatim: tag).font(.caption.monospaced()).textSelection(.enabled) }
                    Text("templateMemo.removeScope").font(.caption)
                }
                Text("templateMemo.otherEffects \(editor.otherEffectCount)").font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { editor.activate() }.onDisappear { editor.retire() }
    }
}
