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
    init(controller: ProjectEndingConditionController, original: ProjectEndingConditionController.Presentation) {
        self.controller = controller; self.original = original; model = controller.context.model
    }
    var body: some View {
        ProjectConditionChoiceSheet(choices: original.choices, oldValue: original.oldValue,
            isCurrent: controller.isCurrent(original), titleKey: "projectEndingChoice.title",
            scopeKey: "projectEndingChoice.scope", emptyKey: "projectEndingChoice.empty",
            apply: { controller.apply(id: $0, original: original) }, close: { controller.close(original) })
    }
}
/// Shared source-only UI. Ending and voice controllers keep separate typed targets and semantics.
@MainActor private struct ProjectConditionChoiceSheet: View {
    let choices: [ProjectEndingConditionChoices.Choice]
    let oldValue: ProjectEditJSON?
    let isCurrent: Bool
    let titleKey: String, scopeKey: String, emptyKey: String
    let apply: (String) -> Void, close: () -> Void
    @State private var selectedID: String?
    init(choices: [ProjectEndingConditionChoices.Choice], oldValue: ProjectEditJSON?, isCurrent: Bool,
         titleKey: String, scopeKey: String, emptyKey: String, apply: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.choices = choices; self.oldValue = oldValue; self.isCurrent = isCurrent
        self.titleKey = titleKey; self.scopeKey = scopeKey; self.emptyKey = emptyKey; self.apply = apply; self.close = close
        _selectedID = State(initialValue: choices.first(where: {
            ProjectEditPendingMaterials.exactData($0.value) == oldValue.flatMap { ProjectEditPendingMaterials.exactData($0) }
        })?.id)
    }
    private var originalText: String {
        guard let raw = oldValue, let bytes = ProjectEditPendingMaterials.exactData(raw) else { return "—" }
        return raw.text ?? String(decoding: bytes, as: UTF8.self)
    }
    var body: some View {
        NavigationStack {
            Form {
                if isCurrent {
                    LabeledContent(content: { Text(verbatim: originalText).textSelection(.enabled) },
                        label: { Text("projectEndingChoice.current", tableName: "ProjectEndingConditionPicker") })
                    Text(LocalizedStringKey(scopeKey), tableName: "ProjectEndingConditionPicker").font(.caption)
                    if choices.isEmpty { Text(LocalizedStringKey(emptyKey), tableName: "ProjectEndingConditionPicker") }
                    ForEach(choices) { choice in
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
                    Button(action: { if let selectedID { apply(selectedID) } },
                        label: { Text("projectEndingChoice.confirm", tableName: "ProjectEndingConditionPicker") })
                        .disabled(selectedID == nil).accessibilityIdentifier("projectEndingChoice.confirm")
                } else { Text("projectStarter.stale") }
            }
            .navigationTitle(Text(LocalizedStringKey(titleKey), tableName: "ProjectEndingConditionPicker"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel", action: close) } }
        }
    }
}
@MainActor final class ProjectStoryConditionController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID(), incarnation: UUID, session: ProjectEditSession?, identity: ProjectEditDraftIdentity?
        let revision: Int, bytes: Data
        let lease: ProjectEditStarterController.Lease
        let target: ProjectStoryConditionChoice.Target
        let choices: [ProjectEndingConditionChoices.Choice]
        let oldValue: ProjectEditJSON?
    }
    let model: ProjectEditModel
    let chapterID: String
    let block: Binding<ProjectEditBlock>
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel, chapterID: String, block: Binding<ProjectEditBlock>) {
        self.model = model; self.chapterID = chapterID; self.block = block
    }
    private var target: ProjectStoryConditionChoice.Target? {
        guard model.captureStarterLease() != nil, let target = try? ProjectStoryConditionChoice.Target(draft: model.draft, chapterID: chapterID, blockID: block.wrappedValue.id),
              ProjectEditPendingMaterials.exactData(block.wrappedValue) == target.blockBytes else { return nil }
        return target
    }
    var available: Bool { target != nil }
    func open() {
        guard presentation == nil, let target, let lease = model.captureStarterLease(), let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        presentation = .init(incarnation: model.editorIncarnation, session: model.coordinator.session, identity: model.coordinator.identity,
            revision: model.draftMutationRevision, bytes: bytes, lease: lease, target: target,
            choices: ProjectEndingConditionChoices.choices(in: model.draft, operation: "HAS_TAG"), oldValue: ProjectStoryConditionChoice.currentValue(target, in: model.draft))
    }
    func isCurrent(_ original: Presentation) -> Bool {
        presentation?.id == original.id && model.isCurrentStarterLease(original.lease) && available && original.incarnation == model.editorIncarnation &&
        original.session == model.coordinator.session && original.identity == model.coordinator.identity &&
        original.revision == model.draftMutationRevision && ProjectEditPendingMaterials.exactData(model.draft) == original.bytes &&
        block.wrappedValue.id.utf8.elementsEqual(original.target.blockID.utf8) && ProjectEditPendingMaterials.exactData(block.wrappedValue) == original.target.blockBytes
    }
    func apply(id: String, original: Presentation) {
        guard isCurrent(original), let choice = original.choices.first(where: { $0.id == id }),
              let next = try? ProjectStoryConditionChoice.applying(choice, to: model.draft, target: original.target) else { return }
        if ProjectEditPendingMaterials.exactData(next) != original.bytes { model.draft = next }
        close(original)
    }
    func close(_ original: Presentation) { if presentation?.id == original.id { presentation = nil } }
    func retire() { presentation = nil }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}
@MainActor struct ProjectStoryConditionEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectStoryConditionController
    init(model: ProjectEditModel, chapterID: String, block: Binding<ProjectEditBlock>) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, block: block))
    }
    var body: some View {
        let original = controller.presentation
        Button(action: { controller.open() }, label: { Text("projectEndingChoice.choose", tableName: "ProjectEndingConditionPicker") })
            .disabled(!controller.available).accessibilityIdentifier("projectStoryCondition.open")
            .sheet(item: controller.binding(original)) { original in ProjectStoryConditionSheet(controller: controller, original: original) }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
            .onDisappear { controller.retire() }
    }
}
@MainActor private struct ProjectStoryConditionSheet: View {
    @ObservedObject var controller: ProjectStoryConditionController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectStoryConditionController.Presentation
    init(controller: ProjectStoryConditionController, original: ProjectStoryConditionController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
    }
    var body: some View {
        ProjectConditionChoiceSheet(choices: original.choices, oldValue: original.oldValue,
            isCurrent: controller.isCurrent(original), titleKey: "projectStoryCondition.title",
            scopeKey: "projectStoryCondition.scope", emptyKey: "projectStoryCondition.empty",
            apply: { controller.apply(id: $0, original: original) }, close: { controller.close(original) })
    }
}
