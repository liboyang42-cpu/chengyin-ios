import SwiftUI

@MainActor final class ProjectNodeDurationController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: UUID
        let lease: ProjectEditStarterController.Lease
        let incarnation: UUID
        let revision: Int
        let snapshot: ProjectNodeDuration
    }
    struct Opening: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    let chapterID: String, nodeID: String
    private let controllerID = UUID()
    private var generation = UUID()
    @Published private(set) var opening: Opening?
    @Published private(set) var text = ""
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; self.chapterID = chapterID; self.nodeID = nodeID
    }
    func capture() -> Capture? {
        guard model.fullEdit, let lease = model.captureStarterLease() else { return nil }
        let snapshot = ProjectNodeDuration(draft: model.draft, chapterID: chapterID, nodeID: nodeID)
        guard snapshot.available else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease,
            incarnation: model.editorIncarnation, revision: model.draftMutationRevision, snapshot: snapshot)
    }
    private func isCurrent(_ capture: Capture) -> Bool {
        capture.controllerID == controllerID && capture.generation == generation && model.fullEdit &&
        model.editorIncarnation == capture.incarnation && model.isCurrentStarterLease(capture.lease) &&
        model.draftMutationRevision == capture.revision && capture.snapshot.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) {
        guard opening == nil, isCurrent(capture) else { return }
        text = String(capture.snapshot.minutes); opening = .init(capture: capture)
    }
    func isCurrent(_ original: Opening) -> Bool { opening?.id == original.id && isCurrent(original.capture) }
    func edit(_ value: String, in original: Opening) {
        guard isCurrent(original) else { return }; text = value
    }
    func canApply(_ original: Opening) -> Bool {
        isCurrent(original) && ProjectNodeDuration.parse(text).map { $0 != original.capture.snapshot.minutes } == true
    }
    @discardableResult func apply(_ original: Opening) -> Bool {
        guard canApply(original), let next = try? original.capture.snapshot.replacing(with: text, in: model.draft) else { return false }
        model.draft = next // Existing autosave / Save local persists the working draft.
        close(original); return true
    }
    func close(_ original: Opening) { guard opening?.id == original.id else { return }; retire() }
    func retire() { opening = nil; text = ""; generation = UUID() }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
            set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodeDurationField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodeDurationController
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let captured = controller.capture()
        let original = controller.opening
        Section {
            Button { guard scenePhase == .active, let captured else { return }; controller.open(captured) } label: {
                Text("projectNodeDuration.edit", tableName: "ProjectNodeDuration")
            }.disabled(captured == nil || original != nil).accessibilityIdentifier("projectNodeDuration.edit")
        }
        .sheet(item: controller.binding(original)) { original in sheet(original) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.retire() } }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
    private func sheet(_ original: ProjectNodeDurationController.Opening) -> some View {
        NavigationStack {
            Form {
                TextField(text: Binding(get: { controller.text }, set: { controller.edit($0, in: original) })) {
                    Text("projectNodeDuration.minutes", tableName: "ProjectNodeDuration")
                }.keyboardType(.numberPad).accessibilityIdentifier("projectNodeDuration.minutes")
                Text("projectNodeDuration.hint", tableName: "ProjectNodeDuration").font(.caption)
                if ProjectNodeDuration.parse(controller.text) == nil {
                    Text("projectNodeDuration.invalid", tableName: "ProjectNodeDuration").font(.caption)
                        .accessibilityIdentifier("projectNodeDuration.invalid")
                }
            }
            .navigationTitle(Text("projectNodeDuration.title", tableName: "ProjectNodeDuration"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { guard scenePhase == .active else { return }; controller.apply(original) } label: {
                        Text("projectNodeDuration.apply", tableName: "ProjectNodeDuration")
                    }.disabled(!controller.canApply(original)).accessibilityIdentifier("projectNodeDuration.apply")
                }
            }
        }
    }
}
