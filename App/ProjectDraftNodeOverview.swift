import SwiftUI

@MainActor final class ProjectDraftNodeOverviewController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let nodeIdentityRevision: Int
        let projection: ProjectDraftNodeProjection
    }
    struct Opening: Identifiable { let id = UUID(); let capture: Capture }
    struct Destination: Identifiable, Hashable {
        let id = UUID()
        let capture: Capture
        let row: ProjectDraftNodeProjection.Row
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    let model: ProjectEditModel
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var opening: Opening?
    @Published private(set) var destination: Destination?
    @Published private(set) var activatedID: UUID?
    init(model: ProjectEditModel) { self.model = model }
    var projection: ProjectDraftNodeProjection { .init(draft: model.draft) }
    func capture(_ projection: ProjectDraftNodeProjection) -> Capture? {
        guard model.fullEdit, projection.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease, revision: model.draftMutationRevision,
            nodeIdentityRevision: model.issueNodeIdentityRevision, projection: projection)
    }
    private func owns(_ capture: Capture) -> Bool {
        capture.controllerID == controllerID && capture.generation == generation && model.fullEdit && model.isCurrentStarterLease(capture.lease)
    }
    func isCurrent(_ capture: Capture) -> Bool {
        owns(capture) && capture.revision == model.draftMutationRevision && capture.projection.isCurrent(in: model.draft)
    }
    func open(_ capture: Capture) {
        guard opening == nil, isCurrent(capture) else { return }; opening = .init(capture: capture)
    }
    func isPresented(_ original: Opening) -> Bool { opening?.id == original.id && owns(original.capture) }
    func choose(_ key: ProjectDraftNodeProjection.Key, captured: Capture, in original: Opening) {
        guard isPresented(original), destination == nil, isCurrent(captured), let row = captured.projection.resolve(key, in: model.draft) else { return }
        destination = .init(capture: captured, row: row); activatedID = nil
    }
    @discardableResult func activate(_ original: Destination) -> Bool {
        guard destination?.id == original.id, activatedID == nil, let opening, isPresented(opening), isCurrent(original.capture) else { return false }
        activatedID = original.id; return true
    }
    func isDestinationPresented(_ original: Destination) -> Bool {
        guard destination?.id == original.id, let opening, isPresented(opening), owns(original.capture) else { return false }
        if activatedID == nil { return isCurrent(original.capture) }
        // Like existing issue navigation, normal child text edits keep the same
        // target alive. Identity deletion/reorder/ABA still retires that editor.
        return activatedID == original.id && model.issueNodeIdentityRevision == original.capture.nodeIdentityRevision && projection.row(original.row.id) != nil
    }
    func closeDestination(_ original: Destination) {
        guard destination?.id == original.id else { return }; destination = nil; activatedID = nil
    }
    func close(_ original: Opening) {
        guard opening?.id == original.id else { return }; retire()
    }
    func retire() { opening = nil; destination = nil; activatedID = nil; generation += 1 }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isPresented(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
    func destinationBinding(_ original: Destination?) -> Binding<Destination?> {
        .init(get: { guard let original, self.isDestinationPresented(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.closeDestination(original) } })
    }
}

@MainActor struct ProjectDraftNodeOverviewEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectDraftNodeOverviewController
    init(model: ProjectEditModel) { self.model = model; _controller = StateObject(wrappedValue: .init(model: model)) }
    var body: some View {
        let projection = controller.projection
        let capture = controller.capture(projection)
        let original = controller.opening
        VStack(alignment: .leading, spacing: 4) {
            Button { if let capture { controller.open(capture) } } label: { Text("projectNodeOverview.open", tableName: "ProjectDraftNodeOverview") }
                .buttonStyle(.borderless).disabled(capture == nil).accessibilityIdentifier("projectNodeOverview.open")
            if let reason = projection.reason { Text(LocalizedStringKey("projectNodeOverview.reason." + reason.rawValue), tableName: "ProjectDraftNodeOverview").font(.caption) }
        }
        .sheet(item: controller.binding(original)) { original in ProjectDraftNodeOverview(controller: controller, original: original) }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onDisappear { controller.retire() }
    }
}

@MainActor struct ProjectDraftNodeOverview: View {
    @ObservedObject var controller: ProjectDraftNodeOverviewController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectDraftNodeOverviewController.Opening
    init(controller: ProjectDraftNodeOverviewController, original: ProjectDraftNodeOverviewController.Opening) {
        self.controller = controller; model = controller.model; self.original = original
    }
    var body: some View {
        let projection = controller.projection
        let capture = controller.capture(projection)
        let selected = controller.destination
        NavigationStack {
            List {
                if controller.isPresented(original) {
                    Section {
                        Text("projectNodeOverview.scope", tableName: "ProjectDraftNodeOverview")
                        Text("projectNodeOverview.mapUnavailable", tableName: "ProjectDraftNodeOverview").font(.caption)
                        if projection.excludedPendingCount > 0 {
                            LabeledContent { Text(verbatim: String(projection.excludedPendingCount)) } label: { Text("projectNodeOverview.pendingExcluded", tableName: "ProjectDraftNodeOverview") }
                        }
                    }
                    if let reason = projection.reason { Text(LocalizedStringKey("projectNodeOverview.reason." + reason.rawValue), tableName: "ProjectDraftNodeOverview") }
                    else if projection.rows.isEmpty { Text("projectNodeOverview.empty", tableName: "ProjectDraftNodeOverview") }
                    else {
                        ForEach(projection.rows) { row in
                            Section {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: "#" + String(row.order) + " · " + row.name).font(.headline)
                                    Text(verbatim: "#" + String(row.chapterOrder) + " · " + row.chapterName).font(.subheadline)
                                    Text(verbatim: row.address)
                                    LabeledContent { Text(verbatim: row.longitude) } label: { Text("projectEdit.longitude") }
                                    LabeledContent { Text(verbatim: row.latitude) } label: { Text("projectEdit.latitude") }
                                    Text(LocalizedStringKey("projectNodeOverview.coordinate." + row.coordinates.rawValue), tableName: "ProjectDraftNodeOverview").font(.caption)
                                    Button {
                                        guard let capture else { return }; controller.choose(row.id, captured: capture, in: original)
                                    } label: { Text(model.draft.product == .city ? "projectNodeOverview.openChapter" : "projectNodeOverview.openNode", tableName: "ProjectDraftNodeOverview") }
                                    .disabled(capture == nil || selected != nil).accessibilityIdentifier("projectNodeOverview.node." + String(row.order))
                                }.textSelection(.enabled)
                            }
                        }
                    }
                } else { Text("projectNodeOverview.stale", tableName: "ProjectDraftNodeOverview") }
            }
            .navigationTitle(Text("projectNodeOverview.title", tableName: "ProjectDraftNodeOverview"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { controller.close(original) } } }
            .navigationDestination(item: controller.destinationBinding(selected)) { destination in
                ProjectDraftNodeOverviewDestination(controller: controller, original: destination)
            }
        }
    }
}

@MainActor private struct ProjectDraftNodeOverviewDestination: View {
    @ObservedObject var controller: ProjectDraftNodeOverviewController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectDraftNodeOverviewController.Destination
    init(controller: ProjectDraftNodeOverviewController, original: ProjectDraftNodeOverviewController.Destination) {
        self.controller = controller; model = controller.model; self.original = original
    }
    var body: some View {
        Group {
            if controller.activatedID == original.id && controller.isDestinationPresented(original) {
                if original.capture.lease.product == .city { ProjectEditChapterView(model: model, chapterID: original.row.chapterID) }
                else { ProjectEditNodeView(model: model, chapterID: original.row.chapterID, nodeID: original.row.nodeID) }
            } else { Text("projectNodeOverview.stale", tableName: "ProjectDraftNodeOverview") }
        }.task(id: original.id) { _ = controller.activate(original) }
    }
}
