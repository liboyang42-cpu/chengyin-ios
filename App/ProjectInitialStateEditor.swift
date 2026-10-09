import SwiftUI

@MainActor final class ProjectInitialStateController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let generation: Int
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let bytes: Data
        let initial: ProjectInitialState
    }
    let model: ProjectEditModel
    let chapterID: String
    private var generation = 0
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel, chapterID: String) { self.model = model; self.chapterID = chapterID }
    var available: Bool {
        model.fullEdit && model.draft.product == .city && !chapterID.isEmpty &&
        model.draft.chapters.first?.id.utf8.elementsEqual(chapterID.utf8) == true &&
        model.draft.chapters.filter { $0.id == chapterID }.count == 1
    }
    func open() {
        guard available, presentation == nil, let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        presentation = .init(generation: generation, incarnation: model.editorIncarnation,
            session: model.coordinator.session, identity: model.coordinator.identity, revision: model.draftMutationRevision,
            bytes: bytes, initial: .init(raw: model.draft.preserved["journeyRules"]))
    }
    func isCurrent(_ original: Presentation) -> Bool {
        presentation?.id == original.id && original.generation == generation && available &&
        model.editorIncarnation == original.incarnation && model.coordinator.session == original.session &&
        model.coordinator.identity == original.identity && model.draftMutationRevision == original.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == original.bytes
    }
    @discardableResult func apply(_ buffer: ProjectInitialState, to original: Presentation) -> Bool {
        guard isCurrent(original) else { return false }
        do {
            let serialized = try buffer.serialized(matching: model.draft.preserved["journeyRules"])
            var next = model.draft; next.preserved["journeyRules"] = serialized
            if ProjectEditPendingMaterials.exactData(next) != original.bytes { model.draft = next }
            close(original); return true
        } catch { return false }
    }
    func close(_ original: Presentation) {
        guard presentation?.id == original.id else { return }; presentation = nil; generation += 1
    }
    func retire() { presentation = nil; generation += 1 }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectInitialStateEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectInitialStateController
    init(model: ProjectEditModel, chapterID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID))
    }
    var body: some View {
        let original = controller.presentation
        Section {
            Button { controller.open() } label: { Text("projectInitialState.title", tableName: "ProjectInitialState") }
                .disabled(!controller.available).accessibilityIdentifier("projectInitialState.open")
        }
        .sheet(item: controller.binding(original)) { original in ProjectInitialStateSheet(controller: controller, original: original) }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectInitialStateSheet: View {
    @ObservedObject var controller: ProjectInitialStateController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectInitialStateController.Presentation
    @State private var buffer: ProjectInitialState
    @State private var invalid = false
    init(controller: ProjectInitialStateController, original: ProjectInitialStateController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
        _buffer = State(initialValue: original.initial)
    }
    private func resource(_ kind: ProjectInitialState.Kind) -> Binding<ProjectInitialState.Resource> { kind == .hp ? $buffer.hp : $buffer.luck }
    var body: some View {
        NavigationStack {
            Form {
                if !controller.isCurrent(original) { Text("projectStarter.stale") }
                else if buffer.readOnly { Text("projectInitialState.unsupported", tableName: "ProjectInitialState") }
                else {
                    Text("projectInitialState.scope", tableName: "ProjectInitialState").font(.caption)
                    ForEach(ProjectInitialState.Kind.allCases, id: \.self) { kind in
                        Section {
                            Toggle(isOn: .init(get: { resource(kind).wrappedValue.enabled }, set: { buffer.setEnabled($0, kind: kind); invalid = false })) {
                                Text(kind == .hp ? "projectInitialState.hp" : "projectInitialState.luck", tableName: "ProjectInitialState")
                            }
                            if resource(kind).wrappedValue.enabled {
                                TextField(text: resource(kind).initial) { Text("projectInitialState.initial", tableName: "ProjectInitialState") }.keyboardType(.numberPad)
                                TextField(text: resource(kind).maximum) { Text("projectInitialState.maximum", tableName: "ProjectInitialState") }.keyboardType(.numberPad)
                            }
                            Text(kind == .hp ? "projectInitialState.hpRange" : "projectInitialState.luckRange", tableName: "ProjectInitialState").font(.caption)
                        }
                    }
                    if !buffer.recoveryChanges.isEmpty {
                        Section {
                            Text("projectInitialState.recoveryNotice", tableName: "ProjectInitialState")
                            ForEach(buffer.recoveryChanges) { change in
                                LabeledContent {
                                    Text(verbatim: "\(change.before) → \(change.after)")
                                } label: { Text(LocalizedStringKey("projectInitialState.recovery." + change.key), tableName: "ProjectInitialState") }
                            }
                        }
                    }
                    if invalid { Text("projectInitialState.invalid", tableName: "ProjectInitialState") }
                    Button { invalid = !controller.apply(buffer, to: original) } label: {
                        Text("projectInitialState.confirm", tableName: "ProjectInitialState")
                    }.accessibilityIdentifier("projectInitialState.confirm")
                }
            }
            .navigationTitle(Text("projectInitialState.title", tableName: "ProjectInitialState"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}
