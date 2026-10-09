import SwiftUI

@MainActor struct ProjectNodeTemplateCreationLaunch {
    let coordinator: TemplateAuthoringCoordinator
    let sessionRevision: UInt64
    let metadataReader: (any DiscoveryReading)?
    let imageSelectionApproved: () -> Bool
}
private struct ProjectNodeTemplateCreationFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> ProjectNodeTemplateCreationLaunch?)? = nil
}
extension EnvironmentValues {
    var projectNodeTemplateCreationFactory: (@MainActor () -> ProjectNodeTemplateCreationLaunch?)? {
        get { self[ProjectNodeTemplateCreationFactoryKey.self] }
        set { self[ProjectNodeTemplateCreationFactoryKey.self] = newValue }
    }
}
@MainActor final class ProjectNodeTemplateCreationController: ObservableObject {
    struct Opening: Identifiable {
        let id = UUID()
        let node: ProjectStoryTemplatePresentation.Opening
        let launch: ProjectNodeTemplateCreationLaunch
        let authorSession: TemplateAuthoringSession
        let authorIdentity: TemplateAuthoringIdentity
    }
    let model: ProjectEditModel
    let selector: ProjectStoryTemplatePresentation
    let chapterID: String, nodeID: String
    @Published private(set) var opening: Opening?
    @Published private(set) var returned: TemplateAuthoringSavedDraft?
    @Published private(set) var unavailable = false
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; self.chapterID = chapterID; self.nodeID = nodeID; selector = .init(editor: model)
    }
    var available: Bool { opening == nil && selector.captureNode(chapterID: chapterID, nodeID: nodeID) != nil }
    /// Called only by the user's explicit Create action. Never automatically clears a pending mutation.
    func open(_ make: (@MainActor () -> ProjectNodeTemplateCreationLaunch?)?) {
        guard available, let node = selector.captureNode(chapterID: chapterID, nodeID: nodeID), let launch = make?() else { unavailable = true; return }
        launch.coordinator.open()
        guard selector.isCurrent(node), let session = launch.coordinator.session, session.accountID == node.lease.session.accountID,
              session.ownerKey.utf8.elementsEqual(node.lease.session.ownerKey.utf8), session.epoch == node.lease.session.epoch else { unavailable = true; return }
        if let previous = launch.coordinator.savedDraft {
            guard launch.coordinator.beginNewDraft(after: previous) else { unavailable = true; return }
        }
        guard !launch.coordinator.locked else { unavailable = true; return }
        opening = .init(node: node, launch: launch, authorSession: session, authorIdentity: launch.coordinator.identity)
        returned = nil; unavailable = false
    }
    func isCurrent(_ original: Opening) -> Bool {
        opening?.id == original.id && selector.isCurrent(original.node) &&
        original.launch.coordinator.session == original.authorSession && original.launch.coordinator.identity == original.authorIdentity
    }
    func canReturn(_ saved: TemplateAuthoringSavedDraft, original: Opening) -> Bool {
        isCurrent(original) && returned == nil && original.launch.coordinator.savedDraft == saved &&
        saved.identity == original.authorIdentity && saved.ownerKey.utf8.elementsEqual(original.authorSession.ownerKey.utf8)
    }
    @discardableResult func accept(_ saved: TemplateAuthoringSavedDraft, original: Opening) -> Task<Void, Never>? {
        guard canReturn(saved, original: original), let task = selector.openCreatedNode(original.node, id: saved.memberTemplateID) else { return nil }
        returned = saved; return task
    }
    private func authorizes(_ saved: TemplateAuthoringSavedDraft, original: Opening) -> Bool {
        isCurrent(original) && returned == saved && original.launch.coordinator.savedDraft == saved &&
        saved.identity == original.authorIdentity && saved.ownerKey.utf8.elementsEqual(original.authorSession.ownerKey.utf8)
    }
    /// Creation has an additional author/receipt lifetime beyond the project's target lease.
    @discardableResult func apply(_ review: ProjectStoryTemplatePresentation.Review, original: Opening) -> Task<Void, Never>? {
        guard let saved = returned, authorizes(saved, original: original),
              review.source.row.id == saved.memberTemplateID, selector.opening?.id == original.node.id else { return nil }
        return selector.apply(review, original: original.node, authorization: { [weak self] in
            self?.authorizes(saved, original: original) == true
        })
    }
    func retryRead(_ original: Opening) {
        guard isCurrent(original), let returned, selector.review == nil else { return }
        _ = selector.refreshCreatedNode(original.node, id: returned.memberTemplateID)
    }
    func close(_ original: Opening) {
        guard opening?.id == original.id else { return }
        if let selected = selector.opening { selector.close(selected) }
        opening = nil; returned = nil
    }
    func binding(_ original: Opening?) -> Binding<Opening?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}
@MainActor struct ProjectNodeTemplateCreationField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectNodeTemplateCreationController
    @Environment(\.projectNodeTemplateCreationFactory) private var factory
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, nodeID: nodeID))
    }
    var body: some View {
        let original = controller.opening
        Section {
            Button(action: { controller.open(factory) }, label: { Text("projectNodeCreate.create", tableName: "ProjectNodeTemplateCreation") })
                .disabled(factory == nil || !controller.available).accessibilityIdentifier("projectNodeCreate.create")
            Text("projectNodeCreate.scope", tableName: "ProjectNodeTemplateCreation").font(.caption)
            if factory == nil || (original == nil && (!controller.available || controller.unavailable)) {
                Text("projectNodeCreate.unavailable", tableName: "ProjectNodeTemplateCreation").font(.caption)
            }
        }
        .sheet(item: controller.binding(original)) { original in ProjectNodeTemplateCreationHost(controller: controller, selector: controller.selector, original: original) }
        .onChange(of: model.editorIncarnation) { _, _ in if let original { controller.close(original) } }
        .onDisappear { if let original { controller.close(original) } }
    }
}
@MainActor private struct ProjectNodeTemplateCreationHost: View {
    @ObservedObject var controller: ProjectNodeTemplateCreationController
    @ObservedObject var selector: ProjectStoryTemplatePresentation
    let original: ProjectNodeTemplateCreationController.Opening
    var body: some View {
        Group {
            if controller.returned != nil {
                if selector.opening != nil, let returned = controller.returned {
                    NavigationStack {
                        Form {
                            Text("projectNodeCreate.returnScope", tableName: "ProjectNodeTemplateCreation")
                            Text(verbatim: "#" + String(returned.memberTemplateID.rawValue))
                            if let review = selector.review, review.source.row.id == returned.memberTemplateID {
                                Text(verbatim: review.source.row.title)
                                Button(action: { _ = controller.apply(review, original: original) },
                                    label: { Text("projectNodeCreate.apply", tableName: "ProjectNodeTemplateCreation") })
                                    .disabled(selector.busy || !controller.isCurrent(original))
                            } else if !selector.busy {
                                Text("projectNodeCreate.readFailed", tableName: "ProjectNodeTemplateCreation")
                                Button(action: { controller.retryRead(original) }, label: { Text("projectNodeCreate.retryRead", tableName: "ProjectNodeTemplateCreation") })
                            }
                            if selector.busy { ProgressView() }
                            if selector.state == .saveFailed { Text("projectStoryTemplate.saveFailed") }
                        }
                        .navigationTitle(Text("projectNodeCreate.reviewTitle", tableName: "ProjectNodeTemplateCreation"))
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
                    }
                }
            } else {
                NavigationStack {
                    TemplateAuthoringView(coordinator: original.launch.coordinator, sessionRevision: original.launch.sessionRevision,
                        metadataReader: original.launch.metadataReader, imageSelectionApproved: original.launch.imageSelectionApproved,
                        onSavedDraft: { _ = controller.accept($0, original: original) },
                        canReturnSavedDraft: { controller.canReturn($0, original: original) })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { controller.close(original) } } }
                }
            }
        }
        .onChange(of: selector.opening?.id) { _, current in if controller.returned != nil && current == nil { controller.close(original) } }
        .onDisappear { controller.close(original) }
    }
}
