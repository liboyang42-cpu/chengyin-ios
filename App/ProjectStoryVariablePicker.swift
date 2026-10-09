import SwiftUI

struct ProjectStoryVariableHostIdentity: Hashable {
    let owner: ObjectIdentifier
    let chapter: Data
    let block: Data
}

@MainActor final class ProjectStoryVariableController: ObservableObject {
    struct Capture {
        let lease: ProjectEditStarterController.Lease
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let snapshot: ProjectStoryVariableInsertion
    }
    struct Opening: Identifiable {
        let id = UUID()
        let capture: Capture
    }
    let model: ProjectEditModel
    let chapterID: String, blockID: String
    @Published private(set) var opening: Opening?
    @Published private(set) var selectedKey: String?
    init(model: ProjectEditModel, chapterID: String, blockID: String) { self.model = model; self.chapterID = chapterID; self.blockID = blockID }
    var snapshot: ProjectStoryVariableInsertion { .init(draft: model.draft, chapterID: chapterID, blockID: blockID) }
    func capture(_ snapshot: ProjectStoryVariableInsertion) -> Capture? {
        guard model.fullEdit, snapshot.chapterID.utf8.elementsEqual(chapterID.utf8), snapshot.blockID.utf8.elementsEqual(blockID.utf8),
              snapshot.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        return .init(lease: lease, incarnation: model.editorIncarnation, session: model.coordinator.session,
            identity: model.coordinator.identity, revision: model.draftMutationRevision, snapshot: snapshot)
    }
    private func isCurrent(_ capture: Capture) -> Bool {
        model.fullEdit && capture.snapshot.chapterID.utf8.elementsEqual(chapterID.utf8) && capture.snapshot.blockID.utf8.elementsEqual(blockID.utf8) &&
        model.isCurrentStarterLease(capture.lease) && model.editorIncarnation == capture.incarnation &&
        model.coordinator.session == capture.session && model.coordinator.identity == capture.identity &&
        model.draftMutationRevision == capture.revision && capture.snapshot.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) {
        guard opening == nil, isCurrent(capture), !capture.snapshot.variables.isEmpty else { return }
        selectedKey = nil; opening = .init(capture: capture)
    }
    func isCurrent(_ original: Opening) -> Bool { opening?.id == original.id && isCurrent(original.capture) }
    func select(_ key: String, in original: Opening) {
        guard isCurrent(original), original.capture.snapshot.canAppend(key), original.capture.snapshot.variables.contains(where: { $0.key.utf8.elementsEqual(key.utf8) }) else { return }
        selectedKey = key
    }
    @discardableResult func append(_ original: Opening) -> Bool {
        guard isCurrent(original), let selectedKey,
              let next = try? original.capture.snapshot.applying(appending: selectedKey, to: model.draft) else { return false }
        model.draft = next // Existing editor observer/autosave and Save local own persistence.
        close(original); return true
    }
    func close(_ original: Opening) {
        guard opening?.id == original.id else { return }; opening = nil; selectedKey = nil
    }
    func retire() { opening = nil; selectedKey = nil }
    func binding(_ original: Opening?) -> Binding<Bool> {
        .init(get: { original.map { self.isCurrent($0) } ?? false }, set: { if !$0, let original { self.close(original) } })
    }
}

@MainActor struct ProjectStoryVariablePicker: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectStoryVariableController
    init(model: ProjectEditModel, chapterID: String, blockID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, blockID: blockID))
    }
    var body: some View {
        let snapshot = controller.snapshot
        let capture = controller.capture(snapshot)
        let original = controller.opening
        VStack(alignment: .leading, spacing: 4) {
            Button { if let capture { controller.open(capture) } } label: { Text("projectStoryVariable.open", tableName: "ProjectStoryVariableInsertion") }
                .buttonStyle(.borderless).disabled(capture == nil || snapshot.variables.isEmpty || original != nil)
                .accessibilityIdentifier("projectStoryVariable.open")
            if let reason = snapshot.reason {
                Text(LocalizedStringKey("projectStoryVariable.reason." + reason.rawValue), tableName: "ProjectStoryVariableInsertion").font(.caption)
            } else if snapshot.variables.isEmpty {
                Text("projectStoryVariable.empty", tableName: "ProjectStoryVariableInsertion").font(.caption)
            }
        }
        .sheet(isPresented: controller.binding(original)) {
            if let original { sheet(original) }
        }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
    private func sheet(_ original: ProjectStoryVariableController.Opening) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(original.capture.snapshot.variables) { variable in
                        Button { controller.select(variable.key, in: original) } label: {
                            HStack {
                                VStack(alignment: .leading) { Text(verbatim: variable.token); Text(verbatim: variable.label).font(.caption) }
                                Spacer()
                                if controller.selectedKey?.utf8.elementsEqual(variable.key.utf8) == true { Image(systemName: "checkmark") }
                            }
                        }.disabled(!original.capture.snapshot.canAppend(variable.key)).accessibilityIdentifier("projectStoryVariable.choice." + variable.key)
                    }
                }
                Section {
                    Text("projectStoryVariable.scope", tableName: "ProjectStoryVariableInsertion").font(.caption)
                    Text("projectStoryVariable.limit", tableName: "ProjectStoryVariableInsertion").font(.caption)
                }
            }
            .navigationTitle(Text("projectStoryVariable.title", tableName: "ProjectStoryVariableInsertion"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { controller.append(original) } label: { Text("projectStoryVariable.append", tableName: "ProjectStoryVariableInsertion") }
                        .disabled(controller.selectedKey == nil || !controller.isCurrent(original)).accessibilityIdentifier("projectStoryVariable.append")
                }
            }
        }
    }
}
