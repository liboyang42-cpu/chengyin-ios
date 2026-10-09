import SwiftUI

@MainActor struct ProjectEndingConditionContext {
    let model: ProjectEditModel
    let chapterID: String
    let index: Int
    struct Identity: Hashable { let model: ObjectIdentifier; let chapter: Data; let index: Int }
    var id: Identity { .init(model: ObjectIdentifier(model), chapter: Data(chapterID.utf8), index: index) }
}
@MainActor final class ProjectEndingConditionController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID(), incarnation: UUID, session: ProjectEditSession?, identity: ProjectEditDraftIdentity?
        let revision: Int, bytes: Data
        let target: ProjectEndingConditionChoices.Target
        let choices: [ProjectEndingConditionChoices.Choice]
        let oldValue: ProjectEditJSON?
    }
    let context: ProjectEndingConditionContext
    @Published private(set) var presentation: Presentation?
    init(context: ProjectEndingConditionContext) { self.context = context }
    var available: Bool {
        context.model.fullEdit && (try? ProjectEndingConditionChoices.Target(draft: context.model.draft, chapterID: context.chapterID, index: context.index)) != nil
    }
    func open() {
        let model = context.model
        guard available, presentation == nil, let bytes = ProjectEditPendingMaterials.exactData(model.draft),
              let target = try? ProjectEndingConditionChoices.Target(draft: model.draft, chapterID: context.chapterID, index: context.index) else { return }
        presentation = .init(incarnation: model.editorIncarnation, session: model.coordinator.session, identity: model.coordinator.identity,
            revision: model.draftMutationRevision, bytes: bytes, target: target,
            choices: ProjectEndingConditionChoices.choices(in: model.draft, operation: target.operation), oldValue: ProjectEndingConditionChoices.currentValue(target, in: model.draft))
    }
    func isCurrent(_ original: Presentation) -> Bool {
        let model = context.model
        return presentation?.id == original.id && available && original.incarnation == model.editorIncarnation &&
            original.session == model.coordinator.session && original.identity == model.coordinator.identity &&
            original.revision == model.draftMutationRevision && ProjectEditPendingMaterials.exactData(model.draft) == original.bytes
    }
    func apply(id: String, original: Presentation) {
        guard isCurrent(original), let choice = original.choices.first(where: { $0.id == id }),
              let next = try? ProjectEndingConditionChoices.applying(choice, to: context.model.draft, target: original.target) else { return }
        if ProjectEditPendingMaterials.exactData(next) != original.bytes { context.model.draft = next }
        close(original)
    }
    func close(_ original: Presentation) { if presentation?.id == original.id { presentation = nil } }
    func retire() { presentation = nil }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}
@MainActor struct ProjectEndingConditionEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectEndingConditionController
    init(context: ProjectEndingConditionContext) {
        model = context.model; _controller = StateObject(wrappedValue: .init(context: context))
    }
    var body: some View {
        let original = controller.presentation
        Button { controller.open() } label: { Text("projectEndingChoice.choose", tableName: "ProjectEndingConditionPicker") }
            .disabled(!controller.available).accessibilityIdentifier("projectEndingChoice.open." + String(controller.context.index))
            .sheet(item: controller.binding(original)) { original in ProjectEndingConditionSheet(controller: controller, original: original) }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}
@MainActor private struct ProjectEndingConditionSheet: View {
    @ObservedObject var controller: ProjectEndingConditionController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectEndingConditionController.Presentation
    @State private var selectedID: String?
    init(controller: ProjectEndingConditionController, original: ProjectEndingConditionController.Presentation) {
        self.controller = controller; self.original = original; model = controller.context.model
        _selectedID = State(initialValue: original.choices.first(where: {
            ProjectEditPendingMaterials.exactData($0.value) == original.oldValue.flatMap { ProjectEditPendingMaterials.exactData($0) }
        })?.id)
    }
    private var originalText: String {
        guard let raw = original.oldValue, let bytes = ProjectEditPendingMaterials.exactData(raw) else { return "—" }
        return raw.text ?? String(decoding: bytes, as: UTF8.self)
    }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    LabeledContent(content: { Text(verbatim: originalText).textSelection(.enabled) },
                        label: { Text("projectEndingChoice.current", tableName: "ProjectEndingConditionPicker") })
                    Text("projectEndingChoice.scope", tableName: "ProjectEndingConditionPicker").font(.caption)
                    if original.choices.isEmpty { Text("projectEndingChoice.empty", tableName: "ProjectEndingConditionPicker") }
                    ForEach(original.choices) { choice in
                        Button { selectedID = choice.id } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(verbatim: choice.label)
                                    Text(LocalizedStringKey("projectEndingChoice.kind." + choice.kind.rawValue), tableName: "ProjectEndingConditionPicker").font(.caption)
                                }
                                if selectedID == choice.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    Button(action: { if let selectedID { controller.apply(id: selectedID, original: original) } },
                        label: { Text("projectEndingChoice.confirm", tableName: "ProjectEndingConditionPicker") })
                        .disabled(selectedID == nil).accessibilityIdentifier("projectEndingChoice.confirm")
                } else { Text("projectStarter.stale") }
            }
            .navigationTitle(Text("projectEndingChoice.title", tableName: "ProjectEndingConditionPicker"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
    }
}
