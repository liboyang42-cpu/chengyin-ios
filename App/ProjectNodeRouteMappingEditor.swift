import SwiftUI

@MainActor final class ProjectNodeRouteMappingController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let lease: ProjectEditStarterController.Lease
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let revision: Int
        let bytes: Data
        let mapping: ProjectNodeRouteMapping
        let row: ProjectNodeRouteMapping.Row
        let targets: [ProjectNodeRouteMapping.Target]
    }
    let model: ProjectEditModel
    let chapterID: String, nodeID: String
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel, chapterID: String, nodeID: String) { self.model = model; self.chapterID = chapterID; self.nodeID = nodeID }
    var mapping: ProjectNodeRouteMapping { .init(draft: model.draft, chapterID: chapterID, nodeID: nodeID) }
    var available: Bool { model.fullEdit && model.captureStarterLease() != nil }
    func open(edgeID: String) {
        let snapshot = mapping
        guard available, presentation == nil, snapshot.reason == nil,
              let row = snapshot.rows.first(where: { $0.id.utf8.elementsEqual(edgeID.utf8) }), row.reason == nil,
              let lease = model.captureStarterLease(), let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return }
        presentation = .init(lease: lease, incarnation: model.editorIncarnation, session: model.coordinator.session,
            identity: model.coordinator.identity, revision: model.draftMutationRevision, bytes: bytes,
            mapping: snapshot, row: row, targets: snapshot.targets(for: edgeID))
    }
    func isCurrent(_ original: Presentation) -> Bool {
        presentation?.id == original.id && available && model.isCurrentStarterLease(original.lease) &&
        model.editorIncarnation == original.incarnation && model.coordinator.session == original.session &&
        model.coordinator.identity == original.identity && model.draftMutationRevision == original.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == original.bytes
    }
    @discardableResult func apply(targetID: Int, original: Presentation) -> Bool {
        guard isCurrent(original), original.targets.contains(where: { $0.id == targetID && $0.reason == nil }),
              let next = try? original.mapping.applying(edgeID: original.row.id, targetID: targetID, to: model.draft) else { return false }
        // Reuse the editor's existing working-draft/autosave path. Open, cancel and
        // selecting the existing destination do not touch revision or persistence.
        if ProjectEditPendingMaterials.exactData(next) != original.bytes { model.draft = next }
        close(original); return true
    }
    func close(_ original: Presentation) { if presentation?.id == original.id { presentation = nil } }
    func retire() { presentation = nil }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectNodeRouteMappingEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodeRouteMappingController
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let original = controller.presentation
        let mapping = controller.mapping
        Section {
            Text("projectRouteMapping.scope", tableName: "ProjectNodeRouteMapping").font(.caption)
            if let reason = mapping.reason { ProjectNodeRouteMappingReason(reason: reason) }
            ForEach(mapping.rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: row.label)
                    Text(verbatim: row.triggerType + ":" + row.outcomeCode + " · " + row.id).font(.caption).foregroundStyle(.secondary)
                    LabeledContent { Text(verbatim: String(row.targetID)) } label: { Text("projectRouteMapping.current", tableName: "ProjectNodeRouteMapping") }
                    if let reason = row.reason { ProjectNodeRouteMappingReason(reason: reason) }
                    Button { controller.open(edgeID: row.id) } label: { Text("projectRouteMapping.choose", tableName: "ProjectNodeRouteMapping") }
                        .disabled(!controller.available || row.reason != nil)
                        .accessibilityIdentifier("projectRouteMapping.open." + row.id)
                }
            }
        } header: { Text("projectRouteMapping.title", tableName: "ProjectNodeRouteMapping") }
        .sheet(item: controller.binding(original)) { original in ProjectNodeRouteMappingSheet(controller: controller, original: original) }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
}
@MainActor private struct ProjectNodeRouteMappingReason: View {
    let reason: ProjectNodeRouteMapping.Reason
    var body: some View { Text(LocalizedStringKey("projectRouteMapping.reason." + reason.rawValue), tableName: "ProjectNodeRouteMapping").font(.caption).foregroundStyle(.secondary) }
}
@MainActor private struct ProjectNodeRouteMappingSheet: View {
    @ObservedObject var controller: ProjectNodeRouteMappingController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectNodeRouteMappingController.Presentation
    @State private var selected: Int
    @State private var invalid = false
    init(controller: ProjectNodeRouteMappingController, original: ProjectNodeRouteMappingController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model; _selected = State(initialValue: original.row.targetID)
    }
    var body: some View {
        NavigationStack {
            Form {
                if !controller.isCurrent(original) { Text("projectStarter.stale") }
                else {
                    Text(verbatim: original.row.label + " · " + original.row.outcomeCode)
                    Text("projectRouteMapping.scope", tableName: "ProjectNodeRouteMapping").font(.caption)
                    ForEach(original.targets) { target in
                        VStack(alignment: .leading) {
                            Button {
                                selected = target.id; invalid = false
                            } label: {
                                HStack {
                                    Text(verbatim: target.label + " · #" + String(target.id))
                                    Spacer()
                                    if selected == target.id { Image(systemName: "checkmark") }
                                }
                            }.disabled(target.reason != nil).accessibilityIdentifier("projectRouteMapping.target." + String(target.id))
                            if let reason = target.reason { ProjectNodeRouteMappingReason(reason: reason) }
                        }
                    }
                    if invalid { ProjectNodeRouteMappingReason(reason: .changed) }
                    Button { invalid = !controller.apply(targetID: selected, original: original) } label: { Text("projectRouteMapping.confirm", tableName: "ProjectNodeRouteMapping") }
                        .disabled(!original.targets.contains(where: { $0.id == selected && $0.reason == nil }))
                        .accessibilityIdentifier("projectRouteMapping.confirm")
                }
            }
            .navigationTitle(Text("projectRouteMapping.title", tableName: "ProjectNodeRouteMapping"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
        }
    }
}
