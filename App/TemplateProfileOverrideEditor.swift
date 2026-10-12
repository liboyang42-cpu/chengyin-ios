import SwiftUI
import Combine

@MainActor final class TemplateProfileOverrideController: ObservableObject {
    enum Field { case variable, threshold, option, voice }
    private let model: TemplateAuthoringModel
    private let questionKey: String
    private var owner: TemplateAuthoringSession?
    private var identity: TemplateAuthoringIdentity?
    private var metadata = UUID(), media = UUID(), generation = UUID()
    private var active = false, writing = false
    private var observation: AnyCancellable?
    @Published private var configuration: TemplateProfileOverrideConfiguration?
    @Published private(set) var form: TemplateProfileOverrideConfiguration.Form?
    @Published private(set) var messageKey: String?
    init(model: TemplateAuthoringModel, questionKey: String) {
        self.model = model; self.questionKey = questionKey
        observation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.generation = UUID()
            if !self.writing { self.retire() }
        }
    }
    var canReload: Bool { model.canReadStoryDraft && model.canEdit && !model.busy && model.review == nil }
    private var sameOwner: Bool { owner != nil && owner == model.coordinator.session && identity == model.coordinator.identity }
    private var hasLease: Bool { active && canReload && sameOwner && metadata == model.metadataGeneration && media == model.mediaReviewGeneration && configuration?.isCurrent(model.draft) == true }
    var visibleConfiguration: TemplateProfileOverrideConfiguration? { hasLease ? configuration : nil }
    var canEditForm: Bool { hasLease && configuration?.canEdit == true }
    var issues: [String] { guard hasLease, let configuration, let form else { return [] }; return configuration.issueKeys(form) }
    var canApply: Bool { guard hasLease, let configuration, let form else { return false }; return configuration.applying(form, to: model.draft) != nil }
    var canSave: Bool { guard hasLease, model.draft.canSave, let configuration, let form else { return false }; return configuration.prepared(form, to: model.draft) != nil }
    func reload() {
        retire(); guard canReload else { return }
        owner = model.coordinator.session; identity = model.coordinator.identity
        metadata = model.metadataGeneration; media = model.mediaReviewGeneration
        let value = TemplateProfileOverrideConfiguration(model.draft, questionKey: questionKey)
        configuration = value; form = value.initialForm; active = true
    }
    func retire() { generation = UUID(); active = false; configuration = nil; form = nil; messageKey = nil }
    func enabledBinding() -> Binding<Bool> {
        let stamp = generation
        return .init(get: { [weak self] in guard let self, self.generation == stamp, self.hasLease else { return false }; return self.form?.enabled ?? false }, set: { [weak self] value in
            guard let self, self.generation == stamp, self.canEditForm, let form = self.form, let config = self.configuration else { return }
            self.update(config.toggling(form, enabled: value))
        })
    }
    func textBinding(_ field: Field) -> Binding<String> {
        let stamp = generation
        return .init(get: { [weak self] in
            guard let self, self.generation == stamp, self.hasLease, let form = self.form else { return "" }
            switch field { case .variable: return form.variable; case .threshold: return form.threshold; case .option: return form.option; case .voice: return form.voice }
        }, set: { [weak self] value in
            guard let self, self.generation == stamp, self.canEditForm, var form = self.form, form.enabled else { return }
            switch field { case .variable: form.variable = value; case .threshold: form.threshold = value; case .option: form.option = value; case .voice: form.voice = value }
            self.update(form)
        })
    }
    private func update(_ next: TemplateProfileOverrideConfiguration.Form) {
        guard next != form else { return }; generation = UUID(); form = next; messageKey = "templateProfileOverride.staged"
    }
    func applyAction() -> () -> Void { action(save: false) }
    func saveAction() -> () -> Void { action(save: true) }
    private func action(save: Bool) -> () -> Void {
        let stamp = generation
        return { [weak self] in
            guard let self, self.generation == stamp, save ? self.canSave : self.canApply,
                  let staged = self.form, let next = self.configuration?.prepared(staged, to: self.model.draft) else { return }
            self.generation = UUID(); self.messageKey = nil; self.writing = true
            if TemplateProfileOverrideConfiguration.snapshot(next) != TemplateProfileOverrideConfiguration.snapshot(self.model.draft) { self.model.draft = next; self.model.changed() }
            if save { self.model.save() }
            self.writing = false
            guard self.canReload, self.sameOwner, self.media == self.model.mediaReviewGeneration,
                  TemplateProfileOverrideConfiguration.snapshot(next) == TemplateProfileOverrideConfiguration.snapshot(self.model.draft) else { self.retire(); return }
            self.metadata = self.model.metadataGeneration
            self.configuration = .init(self.model.draft, questionKey: self.questionKey)
            // Disabled source form values survive within this editor, but are never persisted as kaccha.
            self.form = staged.enabled ? self.configuration?.initialForm : staged
            self.messageKey = save ? self.model.coordinator.messageKey : "templateProfileOverride.applied"
        }
    }
    func closeAction(_ dismiss: @escaping () -> Void) -> () -> Void {
        let stamp = generation
        return { [weak self] in guard let self, self.generation == stamp else { return }; self.retire(); dismiss() }
    }
}

@MainActor struct TemplateProfileOverrideEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var controller: TemplateProfileOverrideController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel, questionKey: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, questionKey: questionKey))
    }
    var body: some View {
        Form {
            Section {
                Text("templateProfileOverride.scope").font(.callout)
                Text("templateProfileOverride.stageScope").font(.footnote)
                Text("templateProfileOverride.saveScope").font(.footnote).foregroundStyle(.secondary)
            }
            if let config = controller.visibleConfiguration {
                Section("templateProfileOverride.question") {
                    Text(verbatim: config.questionLabel); Text(verbatim: config.questionKey).font(.caption)
                    if !config.isSupported { Text("templateProfileOverride.readOnly") }
                    else if !config.canEdit { Text("templateProfileOverride.disabled") }
                }
                Section {
                    Toggle("templateProfileOverride.enabled", isOn: controller.enabledBinding()).disabled(!controller.canEditForm)
                        .accessibilityIdentifier("templateProfileOverride.enabled")
                    if controller.form?.enabled == true {
                        TextField("templateProfileOverride.variable", text: controller.textBinding(.variable)).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("templateProfileOverride.variable")
                        TextField("templateProfileOverride.threshold", text: controller.textBinding(.threshold)).keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("templateProfileOverride.threshold")
                        Text("templateProfileOverride.bounds").font(.footnote)
                        Picker("templateProfileOverride.option", selection: controller.textBinding(.option)) {
                            if let current = controller.form?.option, !config.options.contains(where: { $0.key == current }) { Text(verbatim: current).tag(current) }
                            ForEach(config.options) { option in Text(verbatim: option.label.isEmpty ? option.key : option.label).tag(option.key) }
                        }.accessibilityIdentifier("templateProfileOverride.option")
                        TextField("templateProfileOverride.voice", text: controller.textBinding(.voice), axis: .vertical)
                            .accessibilityIdentifier("templateProfileOverride.voice")
                        Text("templateProfileOverride.voiceHint").font(.footnote)
                    }
                }.disabled(!controller.canEditForm)
                if !controller.issues.isEmpty { Section("templateProfileOverride.validation") { ForEach(controller.issues, id: \.self) { Text(LocalizedStringKey($0)) } } }
                Section {
                    Button("templateProfileOverride.apply", action: controller.applyAction()).disabled(!controller.canApply).accessibilityIdentifier("templateProfileOverride.apply")
                    Button("templateProfileOverride.save", action: controller.saveAction()).disabled(!controller.canSave).accessibilityIdentifier("templateProfileOverride.save")
                    Button("templateProfileOverride.reload") { controller.reload() }.disabled(!controller.canReload)
                    if let key = controller.messageKey { Text(LocalizedStringKey(key)).accessibilityIdentifier("templateProfileOverride.message") }
                }
            } else {
                Section { Text("templateProfileOverride.unavailable"); Button("templateProfileOverride.reload") { controller.reload() }.disabled(!controller.canReload) }
            }
        }.navigationTitle("templateProfileOverride.title").privacySensitive()
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("templateAuthor.close", action: controller.closeAction { dismiss() }).accessibilityIdentifier("templateProfileOverride.close")
            } }
            .onAppear { controller.reload() }.onDisappear { controller.retire() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { controller.reload() } else { controller.retire() } }
    }
}
