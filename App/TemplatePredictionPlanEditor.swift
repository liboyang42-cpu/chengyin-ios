import SwiftUI
import Combine

@MainActor final class TemplatePredictionPlanController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), actionGeneration = UUID(), inputGeneration = UUID()
    private var writing = false
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?, lockObservation: AnyCancellable?
    @Published private var active = false
    @Published private var plan: TemplatePredictionPlan
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity; plan = .init(model.draft.advanced); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.actionGeneration = UUID()
            if !self.writing && (!self.canReload || !self.model.canEdit || self.mediaGeneration != self.model.mediaReviewGeneration) { self.suspend() }
        }
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in guard let self, !self.writing else { return }; self.suspend() }
        lockObservation = Publishers.CombineLatest(model.$busy, model.$review).dropFirst().sink { [weak self] value in if value.0 || value.1 != nil { self?.suspend() } }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && session == model.coordinator.session && identity == model.coordinator.identity }
    private var hasLease: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && plan.isCurrent(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && !model.busy && model.review == nil && plan.canEdit }
    var isSupported: Bool { hasLease && plan.isSupported }
    var canAdd: Bool { canEdit && plan.canAdd }
    var rows: [TemplatePredictionPlan.Row] { hasLease ? plan.rows : [] }
    var sameDayConflict: Bool { hasLease && plan.sameDayConflict }
    var issues: [TemplateCreatorIssue] { hasLease ? model.draft.advanced.creatorIssues(.predict) : [] }
    func timing(_ field: TemplatePredictionPlan.TimingField) -> Int { hasLease ? plan.timing(field) : (field == .revealDays ? 1 : 20) }
    func reload() {
        actionGeneration = UUID(); inputGeneration = UUID(); plan = .init(model.draft.advanced); mediaGeneration = model.mediaReviewGeneration; active = canReload; needsReload = !active
    }
    func retire() { active = false; actionGeneration = UUID(); inputGeneration = UUID() }
    func suspend() { retire(); needsReload = true }
    func textInput(_ field: TemplatePredictionPlan.TextField) -> Binding<String> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in guard let self, self.hasLease, self.inputGeneration == stamp else { return "" }; return field == .question ? self.plan.question : self.plan.hint }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp else { return }; self.apply(.text(field, value))
        })
    }
    func labelInput(_ index: Int) -> Binding<String> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in guard let self, self.hasLease, self.inputGeneration == stamp else { return "" }; return self.plan.rows.first(where: { $0.id == index })?.label ?? "" }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp else { return }; self.apply(.label(index, value))
        })
    }
    func timingInput(_ field: TemplatePredictionPlan.TimingField) -> Binding<Int> {
        let stamp = inputGeneration
        return .init(get: { [weak self] in self?.timing(field) ?? (field == .revealDays ? 1 : 20) }, set: { [weak self] value in
            guard let self, self.canEdit, self.inputGeneration == stamp else { return }; self.apply(.timing(field, value))
        })
    }
    func addAction() -> () -> Void { structuralAction(.add) }
    func removeAction(_ index: Int) -> () -> Void { structuralAction(.remove(index)) }
    private func structuralAction(_ edit: TemplatePredictionPlan.Edit) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, snapshot = plan
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata, snapshot.isCurrent(self.model.draft.advanced) else { return }
            self.apply(edit, structural: true)
        }
    }
    func saveAction() -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration
        return { [weak self] in guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata else { return }; self.model.save() }
    }
    private func apply(_ edit: TemplatePredictionPlan.Edit, structural: Bool = false) {
        guard canEdit, let next = plan.applying(edit, to: model.draft.advanced) else { return }
        let updated = TemplatePredictionPlan(next)
        actionGeneration = UUID(); if structural { inputGeneration = UUID() }
        writing = true; defer { writing = false }; plan = updated
        if !updated.isCurrent(model.draft.advanced) { model.draft.advanced = next; model.changed() }
    }
}

@MainActor struct TemplatePredictionPlanEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplatePredictionPlanController
    @Environment(\.scenePhase) private var scenePhase
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templatePrediction.scope").font(.callout)
                if editor.needsReload {
                    Text("templatePrediction.changed").font(.caption)
                    Button("templatePrediction.reload") { editor.reload() }.disabled(!editor.canReload)
                } else if !editor.isSupported { Text("templatePrediction.unsupported") }
            }
            Section("templatePrediction.question") {
                TextField("creator.field.question", text: editor.textInput(.question), axis: .vertical).accessibilityIdentifier("templatePrediction.question")
                TextField("creator.field.hint", text: editor.textInput(.hint), axis: .vertical).accessibilityIdentifier("templatePrediction.hint")
            }.disabled(!editor.canEdit)
            Section("templatePrediction.options") {
                Text("templatePrediction.keysNotice").font(.caption)
                ForEach(editor.rows) { row in
                    VStack(alignment: .leading) {
                        TextField("creator.field.label", text: editor.labelInput(row.id), axis: .vertical).accessibilityIdentifier("templatePrediction.option.\(row.id).label")
                        HStack {
                            Text(verbatim: row.key).font(.caption).lineLimit(1).textSelection(.enabled)
                            Spacer(); Button("creator.remove", role: .destructive, action: editor.removeAction(row.id)).buttonStyle(.borderless)
                                .accessibilityIdentifier("templatePrediction.option.\(row.id).remove")
                        }
                    }
                }
                Text("templatePrediction.count \(editor.rows.count)").font(.caption)
                Button("creator.add", systemImage: "plus", action: editor.addAction()).disabled(!editor.canAdd).accessibilityIdentifier("templatePrediction.add")
            }.disabled(!editor.canEdit)
            Section("templatePrediction.schedule") {
                hourPicker(.closeAtHour)
                Picker("creator.field.revealDays", selection: editor.timingInput(.revealDays)) {
                    ForEach(TemplatePredictionPlan.days, id: \.self) { day in dayLabel(day).tag(day) }
                }.accessibilityIdentifier("templatePrediction.revealDays")
                hourPicker(.revealHour)
                if editor.sameDayConflict { Text("templatePrediction.conflict").foregroundStyle(.red) }
            }.disabled(!editor.canEdit)
            if editor.isSupported {
                Section("templatePrediction.summary") {
                    LabeledContent("creator.field.closeAtHour", value: hour(editor.timing(.closeAtHour)))
                    LabeledContent("creator.field.revealDays") { dayLabel(editor.timing(.revealDays)) }
                    LabeledContent("creator.field.revealHour", value: hour(editor.timing(.revealHour)))
                    Text("templatePrediction.relative").font(.caption)
                }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") { ForEach(editor.issues) { issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } } }
            }
            Section { Button("templateAuthor.saveLocal", action: editor.saveAction()).disabled(!editor.canEdit || !model.draft.canSave).accessibilityIdentifier("templatePrediction.saveLocal") }
        }.navigationTitle("templatePrediction.title")
            .onDisappear { editor.retire() }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { editor.suspend() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { editor.suspend() } }
    }
    private func hour(_ value: Int) -> String { String(format: "%02d:00", value) }
    private func hourPicker(_ field: TemplatePredictionPlan.TimingField) -> some View {
        Picker(LocalizedStringKey("creator.field." + field.rawValue), selection: editor.timingInput(field)) {
            ForEach(TemplatePredictionPlan.hours, id: \.self) { Text(verbatim: hour($0)).tag($0) }
        }.accessibilityIdentifier("templatePrediction." + field.rawValue)
    }
    @ViewBuilder private func dayLabel(_ day: Int) -> some View {
        switch day { case 0: Text("templatePrediction.sameDay"); case 1: Text("templatePrediction.nextDay"); case 2: Text("templatePrediction.secondDay"); default: Text("templatePrediction.day \(day)") }
    }
}
