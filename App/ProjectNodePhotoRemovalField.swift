import SwiftUI

@MainActor final class ProjectNodePhotoRemovalController: ObservableObject {
    struct Capture {
        let lease: ProjectEditStarterController.Lease
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let snapshot: ProjectNodePhotoRemoval
    }
    struct Confirmation: Identifiable {
        let id = UUID()
        let capture: Capture
        let photo: ProjectNodePhotoRemoval.Photo
    }
    let model: ProjectEditModel
    let chapterID: String, nodeID: String
    @Published private(set) var confirmation: Confirmation?
    init(model: ProjectEditModel, chapterID: String, nodeID: String) { self.model = model; self.chapterID = chapterID; self.nodeID = nodeID }
    var snapshot: ProjectNodePhotoRemoval { .init(draft: model.draft, chapterID: chapterID, nodeID: nodeID) }
    func capture(_ snapshot: ProjectNodePhotoRemoval) -> Capture? {
        guard model.fullEdit, snapshot.chapterID.utf8.elementsEqual(chapterID.utf8), snapshot.nodeID.utf8.elementsEqual(nodeID.utf8),
              snapshot.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        return .init(lease: lease, incarnation: model.editorIncarnation, session: model.coordinator.session,
            identity: model.coordinator.identity, revision: model.draftMutationRevision, snapshot: snapshot)
    }
    private func isCurrent(_ captured: Capture) -> Bool {
        model.fullEdit && captured.snapshot.chapterID.utf8.elementsEqual(chapterID.utf8) && captured.snapshot.nodeID.utf8.elementsEqual(nodeID.utf8) &&
        model.isCurrentStarterLease(captured.lease) && model.editorIncarnation == captured.incarnation &&
        model.coordinator.session == captured.session && model.coordinator.identity == captured.identity &&
        model.draftMutationRevision == captured.revision && captured.snapshot.isCurrent(in: model.draft)
    }
    func open(slot: Int, captured: Capture) {
        guard confirmation == nil, isCurrent(captured), let photo = captured.snapshot.photos.first(where: { $0.id == slot }) else { return }
        confirmation = .init(capture: captured, photo: photo)
    }
    func isCurrent(_ original: Confirmation) -> Bool { confirmation?.id == original.id && isCurrent(original.capture) }
    @discardableResult func apply(_ original: Confirmation) -> Bool {
        guard isCurrent(original), let next = try? original.capture.snapshot.applying(removing: original.photo.id, to: model.draft) else { return false }
        if ProjectEditPendingMaterials.exactData(next) != ProjectEditPendingMaterials.exactData(model.draft) {
            // Match the existing raw field and route-mapping editor: apply to the
            // working draft. Its existing observer/autosave and Save local action
            // own persistence; this confirmation does not claim a completed save.
            model.draft = next
        }
        close(original); return true
    }
    func close(_ original: Confirmation) {
        guard confirmation?.id == original.id else { return }; confirmation = nil
    }
    func retire() { confirmation = nil }
    func binding(_ original: Confirmation?) -> Binding<Bool> {
        .init(get: { original.map { self.isCurrent($0) } ?? false },
              set: { if !$0, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodePhotoRemovalField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodePhotoRemovalController
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let snapshot = controller.snapshot
        let captured = controller.capture(snapshot)
        let original = controller.confirmation
        Section {
            if let reason = snapshot.reason {
                Text(LocalizedStringKey("projectNodePhotos.reason." + reason.rawValue), tableName: "ProjectNodePhotoRemoval").font(.caption)
            } else {
                LabeledContent { Text(verbatim: String(snapshot.photos.count) + "/9") } label: { Text("projectNodePhotos.count", tableName: "ProjectNodePhotoRemoval") }
                if snapshot.photos.isEmpty { Text("projectNodePhotos.empty", tableName: "ProjectNodePhotoRemoval").foregroundStyle(.secondary) }
                ForEach(snapshot.photos) { photo in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "#" + String(photo.id + 1)).font(.headline)
                        Text(verbatim: photo.reference).font(.caption).textSelection(.enabled)
                        Button(role: .destructive) {
                            guard let captured else { return }; controller.open(slot: photo.id, captured: captured)
                        } label: { Text("projectNodePhotos.remove", tableName: "ProjectNodePhotoRemoval") }
                        .disabled(captured == nil || original != nil).accessibilityIdentifier("projectNodePhotos.remove." + String(photo.id))
                    }
                }
            }
            Text("projectNodePhotos.scope", tableName: "ProjectNodePhotoRemoval").font(.caption)
        } header: { Text("projectNodePhotos.title", tableName: "ProjectNodePhotoRemoval") }
        .confirmationDialog(Text("projectNodePhotos.confirmTitle", tableName: "ProjectNodePhotoRemoval"),
            isPresented: controller.binding(original), titleVisibility: .visible) {
                if let original {
                    Button(role: .destructive) { controller.apply(original) } label: { Text("projectNodePhotos.confirm", tableName: "ProjectNodePhotoRemoval") }
                    Button("action.cancel", role: .cancel) { controller.close(original) }
                }
            } message: {
                if let original { Text(verbatim: "#" + String(original.photo.id + 1) + " · " + original.photo.reference) }
                Text("projectNodePhotos.scope", tableName: "ProjectNodePhotoRemoval")
            }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
}
