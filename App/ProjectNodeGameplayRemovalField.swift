import SwiftUI

@MainActor final class ProjectNodeGameplayRemovalController: ObservableObject {
    struct Confirmation: Identifiable {
        let id = UUID(), lease: ProjectEditStarterController.Lease
        let revision: Int, bytes: Data, templateID: Int
        let nodeName: String
    }
    let model: ProjectEditModel
    let chapterID: String, nodeID: String
    @Published private(set) var confirmation: Confirmation?
    @Published private(set) var saveUnconfirmed = false
    init(model: ProjectEditModel, chapterID: String, nodeID: String) { self.model = model; self.chapterID = chapterID; self.nodeID = nodeID }
    var node: ProjectEditNode? {
        guard let index = ProjectNodeGameplayRemoval.index(chapterID: chapterID, nodeID: nodeID, in: model.draft) else { return nil }
        return model.draft.chapters[index.chapter].nodes[index.node]
    }
    var available: Bool { !saveUnconfirmed && model.captureStarterLease() != nil && (node?.templateID ?? 0) > 0 }
    func open() {
        guard available, confirmation == nil, let lease = model.captureStarterLease(), let node, let templateID = node.templateID,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        confirmation = .init(lease: lease, revision: model.draftMutationRevision, bytes: bytes, templateID: templateID, nodeName: node.name)
    }
    func isCurrent(_ original: Confirmation) -> Bool {
        confirmation?.id == original.id && available && model.isCurrentStarterLease(original.lease) &&
        model.draftMutationRevision == original.revision && ProjectEditPendingMaterials.exactData(model.draft) == original.bytes && node?.templateID == original.templateID
    }
    func clear(_ original: Confirmation) {
        guard isCurrent(original), let next = try? ProjectNodeGameplayRemoval.clearing(chapterID: chapterID, nodeID: nodeID, in: model.draft) else { return }
        guard model.persistLocalChange(next, lease: original.lease) else { saveUnconfirmed = true; confirmation = nil; return }
        close(original)
    }
    func close(_ original: Confirmation) { if confirmation?.id == original.id { confirmation = nil } }
    func retire() { confirmation = nil }
    func binding(_ original: Confirmation?) -> Binding<Bool> {
        .init(get: { original.map { self.isCurrent($0) } ?? false }, set: { if !$0, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodeGameplayRemovalField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodeGameplayRemovalController
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let original = controller.confirmation
        Section {
            Button(role: .destructive, action: { controller.open() }, label: { Text("projectNodeGameplay.remove", tableName: "ProjectNodeGameplayRemoval") })
                .disabled(!controller.available).accessibilityIdentifier("projectNodeGameplay.remove")
            Text("projectNodeGameplay.scope", tableName: "ProjectNodeGameplayRemoval").font(.caption)
            if controller.saveUnconfirmed { Text("projectNodeGameplay.saveUnconfirmed", tableName: "ProjectNodeGameplayRemoval") }
            else if !controller.available { Text("projectNodeGameplay.unavailable", tableName: "ProjectNodeGameplayRemoval").font(.caption) }
        }
        .confirmationDialog(Text("projectNodeGameplay.confirmTitle", tableName: "ProjectNodeGameplayRemoval"),
            isPresented: controller.binding(original), titleVisibility: .visible) {
                if let original {
                    Button(role: .destructive, action: { controller.clear(original) }, label: { Text("projectNodeGameplay.confirm", tableName: "ProjectNodeGameplayRemoval") })
                    Button("action.cancel", role: .cancel) { controller.close(original) }
                }
            } message: {
                if let original { Text(verbatim: original.nodeName + " · #" + String(original.templateID)) }
                Text("projectNodeGameplay.impact", tableName: "ProjectNodeGameplayRemoval")
            }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
}
