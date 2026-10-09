import SwiftUI

@MainActor final class ProjectEditIssueNavigation: ObservableObject {
    struct Scope: Equatable {
        let incarnation: UUID
        let session: ProjectEditSession?
        let identity: ProjectEditDraftIdentity?
        let editScope: ProjectEditScope
    }
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let scope: Scope
        let revision: Int
        let identityRevision: Int
        let bytes: Data
        let issue: ProjectEditIssue
        let location: ProjectEditIssueLocation
    }
    struct Row: Identifiable {
        let id: Int
        let issue: ProjectEditIssue
        let capture: Capture?
    }
    struct Destination: Identifiable {
        let id = UUID()
        let capture: Capture
    }
    let model: ProjectEditModel
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var destination: Destination?
    @Published private(set) var rootRequest: Destination?
    @Published private(set) var stale = false
    init(model: ProjectEditModel) { self.model = model }
    private var scope: Scope? {
        guard model.canEdit, let snapshot = model.coordinator.snapshot else { return nil }
        return .init(incarnation: model.editorIncarnation, session: model.coordinator.session,
                     identity: model.coordinator.identity, editScope: snapshot.scope)
    }
    func rows(_ issues: [ProjectEditIssue]) -> [Row] {
        guard !issues.isEmpty else { return [] }
        let currentScope = scope, bytes = ProjectEditPendingMaterials.exactData(model.draft)
        let actual = currentScope.map { ProjectEditIssueLocation.rows(in: model.draft, scope: $0.editScope) } ?? []
        return issues.enumerated().map { index, issue in
            let matches = actual.filter { $0.issue == issue }
            var captured: Capture?
            if let currentScope, let bytes, matches.count == 1, let location = matches[0].location {
                captured = .init(controllerID: controllerID, generation: generation, scope: currentScope,
                    revision: model.draftMutationRevision, identityRevision: identityRevision(location), bytes: bytes, issue: issue, location: location)
            }
            return .init(id: index, issue: issue, capture: captured)
        }
    }
    private func identityRevision(_ location: ProjectEditIssueLocation) -> Int {
        switch location {
        case .root: return 0
        case .chapter: return model.structureRevision
        case .node: return model.issueNodeIdentityRevision
        case .ticket: return model.issueTicketIdentityRevision
        }
    }
    func isCurrent(_ value: Capture) -> Bool {
        value.controllerID == controllerID && value.generation == generation && scope == value.scope &&
        model.draftMutationRevision == value.revision && ProjectEditPendingMaterials.exactData(model.draft) == value.bytes &&
        ProjectEditIssueLocation.location(for: value.issue, in: model.draft, scope: value.scope.editScope) == value.location
    }
    func open(_ value: Capture) {
        guard isCurrent(value) else { stale = true; return }
        stale = false
        switch value.location {
        case .root: destination = nil; rootRequest = .init(capture: value)
        default: rootRequest = nil; destination = .init(capture: value)
        }
    }
    func isPresented(_ value: Destination) -> Bool {
        // The initial click is revision-bound; edits in the destination retain
        // its stable identity rather than closing the editor after each key.
        destination?.id == value.id && value.capture.controllerID == controllerID &&
        value.capture.generation == generation && scope == value.capture.scope &&
        identityRevision(value.capture.location) == value.capture.identityRevision && value.capture.location.exists(in: model.draft)
    }
    func close(_ value: Destination) { if destination?.id == value.id { destination = nil } }
    func retire() { destination = nil; rootRequest = nil; stale = false; generation += 1 }
    func binding(_ original: Destination?) -> Binding<Destination?> {
        .init(get: { guard let original, self.isPresented(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectEditIssueNavigationPresentation: ViewModifier {
    @ObservedObject var controller: ProjectEditIssueNavigation
    func body(content: Content) -> some View {
        let original = controller.destination
        ScrollViewReader { proxy in
            content
                .onChange(of: controller.rootRequest?.id) { _, _ in
                    guard let request = controller.rootRequest, controller.isCurrent(request.capture) else { return }
                    proxy.scrollTo(request.capture.location.anchor, anchor: .center)
                }
                .navigationDestination(item: controller.binding(original)) { value in
                    ProjectEditLocatedIssueView(controller: controller, original: value)
                }
                .onChange(of: controller.model.editorIncarnation) { _, _ in controller.retire() }
        }
    }
}

@MainActor private struct ProjectEditLocatedIssueView: View {
    @ObservedObject var controller: ProjectEditIssueNavigation
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectEditIssueNavigation.Destination
    init(controller: ProjectEditIssueNavigation, original: ProjectEditIssueNavigation.Destination) {
        self.controller = controller; model = controller.model; self.original = original
    }
    var body: some View {
        if controller.isPresented(original) {
            switch original.capture.location {
            case .chapter(let id, let anchor):
                ProjectEditChapterView(model: model, chapterID: id, initialIssueAnchor: anchor)
            case .node(let chapterID, let nodeID, let anchor):
                ProjectEditNodeView(model: model, chapterID: chapterID, nodeID: nodeID, initialIssueAnchor: anchor)
            case .ticket(let id, let anchor):
                ProjectEditTicketView(model: model, ticketID: id, initialIssueAnchor: anchor)
            case .root: EmptyView()
            }
        } else { Text("projectStarter.stale") }
    }
}

@MainActor struct ProjectEditIssueInitialScroll: ViewModifier {
    let anchor: String?
    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content.task(id: anchor) {
                guard let anchor else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }
}
