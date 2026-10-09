import SwiftUI

struct ProjectAlbumPhotoRemovalIdentity: Hashable {
    let owner: ObjectIdentifier
    let chapter: Data, block: Data
    let index: Int
}

@MainActor final class ProjectAlbumPhotoRemovalController: ObservableObject {
    struct Capture {
        let controllerID: UUID, generation: UUID, incarnation: UUID
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let snapshot: ProjectAlbumPhotoRemoval
    }
    struct Opening: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    let chapterID: String, blockID: String, index: Int
    private let controllerID = UUID()
    private var generation = UUID()
    @Published private(set) var active = false
    @Published private(set) var opening: Opening?
    init(model: ProjectEditModel, chapterID: String, blockID: String, index: Int) {
        self.model = model; self.chapterID = chapterID; self.blockID = blockID; self.index = index
    }
    func setActive(_ value: Bool) {
        guard value != active else { return }; active = value; generation = UUID(); opening = nil
    }
    func capture() -> Capture? {
        guard active, model.fullEdit, let lease = model.captureStarterLease() else { return nil }
        let snapshot = ProjectAlbumPhotoRemoval(draft: model.draft, chapterID: chapterID, blockID: blockID, index: index)
        guard snapshot.available else { return nil }
        return .init(controllerID: controllerID, generation: generation, incarnation: model.editorIncarnation,
                     lease: lease, revision: model.draftMutationRevision, snapshot: snapshot)
    }
    private func isCurrent(_ capture: Capture) -> Bool {
        active && capture.controllerID == controllerID && capture.generation == generation && model.fullEdit &&
        model.editorIncarnation == capture.incarnation && model.isCurrentStarterLease(capture.lease) &&
        model.draftMutationRevision == capture.revision && capture.snapshot.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) { guard opening == nil, isCurrent(capture) else { return }; opening = .init(capture: capture) }
    func isCurrent(_ original: Opening) -> Bool { opening?.id == original.id && isCurrent(original.capture) }
    @discardableResult func remove(_ original: Opening) -> Bool {
        guard isCurrent(original), let next = try? original.capture.snapshot.removing(in: model.draft) else { return false }
        model.draft = next // Existing working-draft save flow owns persistence, not remote media deletion.
        close(original); return true
    }
    func close(_ original: Opening) { guard opening?.id == original.id else { return }; opening = nil; generation = UUID() }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectAlbumPhotoRemovalButton: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectAlbumPhotoRemovalController
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, chapterID: String, blockID: String, index: Int) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, blockID: blockID, index: index))
    }
    var body: some View {
        let captured = controller.capture(), original = controller.opening
        Button(role: .destructive) {
            guard scenePhase == .active, let captured else { return }; controller.open(captured)
        } label: { Text("projectEdit.rich.removeImage") }
            .buttonStyle(.borderless).disabled(captured == nil || original != nil)
            .accessibilityIdentifier("projectAlbumRemoval.open." + String(controller.index))
            .sheet(item: controller.binding(original)) { original in confirmation(original) }
            .onAppear { controller.setActive(scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in controller.setActive(phase == .active) }
            .onDisappear { controller.setActive(false) }
    }
    private func confirmation(_ original: ProjectAlbumPhotoRemovalController.Opening) -> some View {
        let snapshot = original.capture.snapshot
        return NavigationStack {
            Form {
                LabeledContent { Text(verbatim: "\(snapshot.index + 1) / \(snapshot.count)") } label: {
                    Text("projectAlbumRemoval.position", tableName: "ProjectAlbumPhotoRemoval")
                }
                if !snapshot.caption.isEmpty { Text(verbatim: snapshot.caption) }
                Text(verbatim: snapshot.reference).textSelection(.enabled)
                Text("projectAlbumRemoval.hint", tableName: "ProjectAlbumPhotoRemoval").font(.caption)
                Button(role: .destructive) {
                    guard scenePhase == .active else { return }; controller.remove(original)
                } label: { Text("projectAlbumRemoval.confirm", tableName: "ProjectAlbumPhotoRemoval") }
                    .disabled(!controller.isCurrent(original)).accessibilityIdentifier("projectAlbumRemoval.confirm")
            }.privacySensitive()
                .navigationTitle(Text("projectAlbumRemoval.title", tableName: "ProjectAlbumPhotoRemoval"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
    }
}
