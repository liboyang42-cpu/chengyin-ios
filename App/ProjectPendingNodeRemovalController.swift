import SwiftUI

@MainActor final class ProjectPendingNodeRemovalController: ObservableObject {
    struct Scope: Equatable {
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let lease: ProjectEditStarterController.Lease?
    }
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let scope: Scope
        let revision: Int
        let bytes: Data
        let nodeIDs: [String]
    }
    struct Confirmation: Identifiable {
        let id = UUID()
        let capture: Capture
        let receipt: ProjectPendingNodeRemoval.Receipt
    }
    struct Undo: Identifiable {
        let id = UUID()
        let capture: Capture
        let receipt: ProjectPendingNodeRemoval.Receipt
        let deadline: TimeInterval
    }
    let model: ProjectEditModel
    let chapterID: String
    private let controllerID = UUID()
    private let now: () -> TimeInterval
    private var generation = 0
    private var expiry: Task<Void, Never>?
    @Published private(set) var confirmation: Confirmation?
    @Published private(set) var undo: Undo?
    @Published private(set) var saveUnconfirmed = false

    init(model: ProjectEditModel, chapterID: String,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.model = model; self.chapterID = chapterID; self.now = now
    }
    private var scope: Scope? {
        guard model.fullEdit, model.draft.product == .freeExplore else { return nil }
        let lease = model.captureStarterLease()
        // Signed-in persistence must retain the established full lease. Guest
        // editing stays in memory and retires as soon as any identity appears.
        guard model.coordinator.session == nil || lease != nil else { return nil }
        return .init(incarnation: model.editorIncarnation, session: model.coordinator.session,
                     identity: model.coordinator.identity, lease: lease)
    }
    func capture() -> Capture? {
        guard !saveUnconfirmed, let scope,
              let chapter = model.draft.chapters.first(where: { $0.id == chapterID }),
              let first = chapter.nodes.first,
              (try? ProjectPendingNodeRemoval.moving([first.id], chapterID: chapterID, in: model.draft)) != nil,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, scope: scope,
                     revision: model.draftMutationRevision, bytes: bytes, nodeIDs: chapter.nodes.map(\.id))
    }
    private func current(_ value: Capture) -> Bool {
        !saveUnconfirmed && value.controllerID == controllerID && value.generation == generation &&
        scope == value.scope && model.draftMutationRevision == value.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == value.bytes
    }
    func isCurrent(_ value: Confirmation) -> Bool { confirmation?.id == value.id && current(value.capture) }
    func canUndo(_ value: Undo) -> Bool {
        undo?.id == value.id && now() < value.deadline && current(value.capture)
    }
    func open(offsets: IndexSet, captured: Capture?) {
        guard confirmation == nil, let captured, current(captured), !offsets.isEmpty,
              offsets.allSatisfy({ captured.nodeIDs.indices.contains($0) }),
              let receipt = try? ProjectPendingNodeRemoval.moving(offsets.map { captured.nodeIDs[$0] }, chapterID: chapterID, in: model.draft) else { return }
        confirmation = .init(capture: captured, receipt: receipt)
    }
    private func persist(_ value: ProjectEditDraft, captured: Capture) -> Bool {
        guard current(captured) else { return false }
        if let lease = captured.scope.lease { return model.persistLocalChange(value, lease: lease) }
        guard captured.scope.session == nil, model.coordinator.session == nil else { return false }
        model.draft = value; model.changed(); return true
    }
    func confirm(_ value: Confirmation) {
        guard isCurrent(value) else { return }
        var receipt = value.receipt
        if let undo, canUndo(undo), let combined = try? ProjectPendingNodeRemoval.combining(undo.receipt, with: receipt) {
            receipt = combined
        }
        guard persist(value.receipt.after, captured: value.capture) else {
            failSave(); return
        }
        confirmation = nil
        // Empty chapters still need a postimage capture for Undo.
        guard let scope, let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { retire(); return }
        let capture = Capture(controllerID: controllerID, generation: generation, scope: scope,
            revision: model.draftMutationRevision, bytes: bytes,
            nodeIDs: model.draft.chapters.first(where: { $0.id == chapterID })?.nodes.map(\.id) ?? [])
        let next = Undo(capture: capture, receipt: receipt, deadline: now() + 5)
        undo = next; expiry?.cancel()
        expiry = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire(next.id)
        }
    }
    func restore(_ value: Undo) {
        guard canUndo(value), let original = try? ProjectPendingNodeRemoval.restoring(value.receipt, in: model.draft) else { synchronize(); return }
        guard persist(original, captured: value.capture) else { failSave(); return }
        undo = nil; expiry?.cancel(); generation += 1
    }
    private func failSave() {
        // The model only adopts confirmed writes. A partial envelope/pointer
        // save is not called a rollback; the unchanged full node remains shown.
        saveUnconfirmed = true; confirmation = nil; undo = nil; expiry?.cancel()
    }
    private func expire(_ id: UUID) {
        guard undo?.id == id else { return }
        undo = nil
    }
    func synchronize() {
        if let confirmation, !isCurrent(confirmation) { self.confirmation = nil }
        if let undo, !canUndo(undo) { self.undo = nil; expiry?.cancel() }
    }
    func close(_ value: Confirmation) { if confirmation?.id == value.id { confirmation = nil } }
    func retire() {
        confirmation = nil; undo = nil; saveUnconfirmed = false; generation += 1; expiry?.cancel()
    }
    func binding(_ original: Confirmation?) -> Binding<Confirmation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectPendingNodeRemovalStatus: View {
    @ObservedObject var controller: ProjectPendingNodeRemovalController
    var body: some View {
        if controller.saveUnconfirmed {
            Text("projectPendingNodeRemoval.saveUnconfirmed", tableName: "ProjectPendingNodeRemoval")
                .accessibilityIdentifier("projectPendingNodeRemoval.saveUnconfirmed")
        } else if let undo = controller.undo, controller.canUndo(undo) {
            VStack(alignment: .leading) {
                Text("projectPendingNodeRemoval.moved", tableName: "ProjectPendingNodeRemoval")
                Button { controller.restore(undo) } label: {
                    Text("projectPendingNodeRemoval.undo", tableName: "ProjectPendingNodeRemoval")
                }.accessibilityIdentifier("projectPendingNodeRemoval.undo")
            }
        }
    }
}

@MainActor struct ProjectPendingNodeRemovalPresentation: ViewModifier {
    @ObservedObject var controller: ProjectPendingNodeRemovalController
    func body(content: Content) -> some View {
        let original = controller.confirmation
        content.sheet(item: controller.binding(original)) { value in
            NavigationStack {
                Form {
                    if controller.isCurrent(value) {
                        Text("projectPendingNodeRemoval.warning", tableName: "ProjectPendingNodeRemoval")
                        ForEach(value.receipt.before.chapters.flatMap(\.nodes).filter { value.receipt.nodeIDs.contains($0.id) }) { node in
                            Text(verbatim: node.name)
                        }
                        if value.capture.scope.session == nil {
                            Text("projectPendingNodeRemoval.guest", tableName: "ProjectPendingNodeRemoval")
                        }
                        Button(role: .destructive) { controller.confirm(value) } label: {
                            Text("projectPendingNodeRemoval.confirm", tableName: "ProjectPendingNodeRemoval")
                        }.accessibilityIdentifier("projectPendingNodeRemoval.confirm")
                    } else { Text("projectStarter.stale") }
                }
                .navigationTitle(Text("projectPendingNodeRemoval.title", tableName: "ProjectPendingNodeRemoval"))
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { controller.close(value) }
                        .accessibilityIdentifier("projectPendingNodeRemoval.cancel")
                } }
            }
        }
    }
}
