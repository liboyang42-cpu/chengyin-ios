import SwiftUI
import Combine

@MainActor final class TemplateMultiplayerPlanController: ObservableObject {
    private let model: TemplateAuthoringModel
    private let session: TemplateAuthoringSession?
    private let identity: TemplateAuthoringIdentity
    private var mediaGeneration = UUID(), actionGeneration = UUID(), textGeneration = UUID()
    private var writing = false
    private var publicationObservation: AnyCancellable?, draftObservation: AnyCancellable?
    @Published private var active = false
    @Published private var plan: TemplateMultiplayerPlan
    @Published private(set) var needsReload = false
    init(model: TemplateAuthoringModel) {
        self.model = model; session = model.coordinator.session; identity = model.coordinator.identity
        plan = .init(model.draft.advanced); reload()
        publicationObservation = model.objectWillChange.sink { [weak self] _ in
            guard let self else { return }; self.actionGeneration = UUID()
            if !self.writing && (!self.canReload || self.mediaGeneration != self.model.mediaReviewGeneration) { self.invalidate() }
        }
        // Parent onChange(draft) refreshes review metadata after our own write. Keep typing
        // through that refresh; only an actual external draft emission requires reload.
        draftObservation = model.$draft.dropFirst().sink { [weak self] _ in
            guard let self, !self.writing else { return }; self.invalidate()
        }
    }
    var canReload: Bool { model.canReadStoryDraft && session != nil && model.coordinator.session == session && model.coordinator.identity == identity }
    private var hasLease: Bool { active && canReload && mediaGeneration == model.mediaReviewGeneration && plan.isCurrent(model.draft.advanced) }
    var canEdit: Bool { hasLease && model.canEdit && plan.canEdit }
    var isSupported: Bool { hasLease && plan.isSupported }
    var canAdd: Bool { canEdit && plan.canAdd }
    var roles: [TemplateMultiplayerPlan.Role] { hasLease ? plan.roles : [] }
    var turns: [TemplateMultiplayerPlan.Turn] { hasLease ? plan.turns : [] }
    var issues: [TemplateCreatorIssue] { hasLease ? model.draft.advanced.creatorIssues(.multiplayer) : [] }
    func reload() {
        actionGeneration = UUID(); textGeneration = UUID()
        guard canReload else { active = false; needsReload = true; return }
        plan = .init(model.draft.advanced); mediaGeneration = model.mediaReviewGeneration; active = true; needsReload = false
    }
    func retire() { active = false; actionGeneration = UUID(); textGeneration = UUID() }
    private func invalidate() { retire(); needsReload = true }
    func addAction() -> () -> Void { action(.add) }
    func removeAction(_ id: UUID) -> () -> Void { action(.remove(id)) }
    func moveAction(_ id: UUID, by offset: Int) -> () -> Void { action(.move(id, offset)) }
    private func action(_ edit: TemplateMultiplayerPlan.Edit) -> () -> Void {
        let stamp = actionGeneration, metadata = model.metadataGeneration, captured = plan
        return { [weak self] in
            guard let self, self.canEdit, self.actionGeneration == stamp, self.model.metadataGeneration == metadata,
                  let update = captured.applying(edit, to: self.model.draft.advanced) else { return }
            self.textGeneration = UUID(); self.apply(update)
        }
    }
    func text(_ id: UUID, field: TemplateMultiplayerPlan.Field) -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp, let row = self.plan.roles.first(where: { $0.id == id }) else { return "" }
            switch field { case .identifier: return row.wireID; case .label: return row.label; case .minimum: return row.minimumText; case .maximum: return row.maximumText }
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp, let update = self.plan.applying(.text(id, field, text), to: self.model.draft.advanced) else { return }
            self.apply(update)
        })
    }
    func orderInput() -> Binding<String> {
        let stamp = textGeneration
        return .init(get: { [weak self] in
            guard let self, self.hasLease, self.textGeneration == stamp else { return "" }; return self.plan.orderText
        }, set: { [weak self] text in
            guard let self, self.canEdit, self.textGeneration == stamp, let update = self.plan.applying(.order(text), to: self.model.draft.advanced) else { return }
            self.apply(update)
        })
    }
    private func apply(_ update: TemplateMultiplayerPlan.Update) {
        actionGeneration = UUID(); writing = true; defer { writing = false }
        plan = update.plan
        if !update.plan.isCurrent(model.draft.advanced) { model.draft.advanced = update.draft; model.changed() }
    }
}

@MainActor struct TemplateMultiplayerPlanEditor: View {
    @ObservedObject var model: TemplateAuthoringModel
    @StateObject private var editor: TemplateMultiplayerPlanController
    init(model: TemplateAuthoringModel) { self.model = model; _editor = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        Form {
            Section {
                Text("templateTeam.instructions").font(.callout)
                if editor.needsReload {
                    Text("templateTeam.changed").font(.caption)
                    Button("templateTeam.reload") { editor.reload() }.disabled(!editor.canReload)
                } else if !editor.isSupported { Text("templateTeam.unsupported").font(.caption) }
            }
            ForEach(Array(editor.roles.enumerated()), id: \.element.id) { index, role in
                Section {
                    Text("templateTeam.roleNumber \(index + 1)").font(.headline)
                    TextField("creator.field.id", text: editor.text(role.id, field: .identifier)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("creator.field.label", text: editor.text(role.id, field: .label), axis: .vertical)
                    TextField("creator.field.min", text: editor.text(role.id, field: .minimum)).keyboardType(.numbersAndPunctuation)
                    TextField("creator.field.max", text: editor.text(role.id, field: .maximum)).keyboardType(.numbersAndPunctuation)
                    HStack {
                        Button("templateTeam.up", systemImage: "arrow.up", action: editor.moveAction(role.id, by: -1)).disabled(index == 0)
                        Button("templateTeam.down", systemImage: "arrow.down", action: editor.moveAction(role.id, by: 1)).disabled(index == editor.roles.count - 1)
                        Spacer(); Button("creator.remove", role: .destructive, action: editor.removeAction(role.id))
                    }
                }.disabled(!editor.canEdit).accessibilityIdentifier("creator.team.role.\(index)")
            }
            Section {
                Button("templateTeam.add", systemImage: "plus", action: editor.addAction()).disabled(!editor.canAdd)
                Text("templateTeam.roleCount \(editor.roles.count)").font(.caption)
            }
            Section("templateTeam.order") {
                TextEditor(text: editor.orderInput()).frame(minHeight: 92).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("templateTeam.order").accessibilityIdentifier("creator.team.order")
                Text("templateTeam.orderHint").font(.caption)
            }.disabled(!editor.canEdit)
            Section("templateTeam.preview") {
                if editor.turns.isEmpty { Text("templateTeam.emptyOrder").font(.caption) }
                ForEach(editor.turns) { turn in
                    HStack(alignment: .top) {
                        Text(verbatim: "\(turn.id + 1). \(turn.roleID)")
                        Spacer()
                        if turn.resolvesUniquely { Text(verbatim: turn.labels[0]) }
                        else { Label("templateTeam.unresolved", systemImage: "exclamationmark.triangle").font(.caption) }
                    }
                }
            }
            if !editor.issues.isEmpty {
                Section("templateAuthor.validationTitle") {
                    ForEach(Array(editor.issues.enumerated()), id: \.offset) { _, issue in VStack(alignment: .leading) { Text(LocalizedStringKey(issue.labelKey)); Text(verbatim: issue.path).font(.caption) } }
                }
            }
        }.navigationTitle("templateTeam.title").onAppear { editor.reload() }.onDisappear { editor.retire() }
    }
}
