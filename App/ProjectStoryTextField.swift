import SwiftUI

struct ProjectStoryTextHostIdentity: Hashable {
    let owner: ObjectIdentifier
    let chapter: Data
    let block: Data
}

@MainActor final class ProjectStoryTextController: ObservableObject {
    struct Lifetime: Equatable { let id = UUID() }
    struct Completion {
        let lifetime: Lifetime
        let revision: Int
    }
    let model: ProjectEditModel
    let chapterID: String, blockID: String
    @Published private(set) var text = ""
    @Published private(set) var lifetime: Lifetime?
    private var presented = false
    private var sceneActive = false
    private var lease: ProjectEditStarterController.Lease?
    private var acknowledgedRevision = -1
    private var acknowledged: ProjectEmptyStoryTextRemoval?
    init(model: ProjectEditModel, chapterID: String, blockID: String) {
        self.model = model; self.chapterID = chapterID; self.blockID = blockID
        text = snapshot.content
    }
    var snapshot: ProjectEmptyStoryTextRemoval { .init(draft: model.draft, chapterID: chapterID, blockID: blockID) }
    var canEdit: Bool { model.fullEdit && model.captureStarterLease() != nil && snapshot.reason == nil }
    func appear(sceneActive: Bool) { presented = true; self.sceneActive = sceneActive; synchronize() }
    func disappear() { presented = false; retire(lifetime) }
    func setSceneActive(_ active: Bool) { sceneActive = active; if !active { retire(lifetime) } }
    func begin() {
        guard presented, sceneActive, lifetime == nil, canEdit, let currentLease = model.captureStarterLease() else { return }
        let current = snapshot
        guard current.isCurrent(in: model.draft) else { return }
        lease = currentLease; acknowledged = current; acknowledgedRevision = model.draftMutationRevision
        if !text.utf8.elementsEqual(current.content.utf8) { text = current.content }
        lifetime = .init()
    }
    private func isCurrent(_ original: Lifetime) -> Bool {
        guard presented, sceneActive, lifetime == original, model.fullEdit, let lease, model.isCurrentStarterLease(lease),
              model.draftMutationRevision == acknowledgedRevision, let acknowledged else { return false }
        return acknowledged.isCurrent(in: model.draft)
    }
    var completion: Completion? {
        guard let lifetime, isCurrent(lifetime) else { return nil }
        return .init(lifetime: lifetime, revision: acknowledgedRevision)
    }
    func binding(_ original: Lifetime?) -> Binding<String> {
        .init(get: { self.text }, set: { value in
            guard let original else { return }; self.edit(value, in: original)
        })
    }
    func edit(_ value: String, in original: Lifetime) {
        guard isCurrent(original), let acknowledged,
              let next = try? acknowledged.replacingContent(with: value, in: model.draft) else { synchronize(); return }
        guard !value.utf8.elementsEqual(acknowledged.content.utf8) else { return }
        model.draft = next // The ordinary working-draft/autosave path owns persistence.
        self.acknowledged = snapshot; acknowledgedRevision = model.draftMutationRevision
        text = value // Empty text stays present throughout typing.
    }
    @discardableResult func finish(_ original: Completion) -> Bool {
        guard isCurrent(original.lifetime), original.revision == acknowledgedRevision,
              let acknowledged, let next = try? acknowledged.removingIfEmpty(in: model.draft) else { return false }
        if acknowledged.isEmpty { model.draft = next }
        retire(original.lifetime); return true
    }
    func synchronize() {
        if let lifetime, !isCurrent(lifetime) { retire(lifetime) }
        let current = snapshot
        if !text.utf8.elementsEqual(current.content.utf8) { text = current.content }
    }
    func retire(_ original: Lifetime?) {
        guard let original, lifetime == original else { return }
        lifetime = nil; lease = nil; acknowledged = nil; acknowledgedRevision = -1
    }
}

@MainActor struct ProjectStoryTextField: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectStoryTextController
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase
    init(model: ProjectEditModel, chapterID: String, blockID: String) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model, chapterID: chapterID, blockID: blockID))
    }
    var body: some View {
        let lifetime = controller.lifetime
        let completion = controller.completion
        TextField("projectEdit.story", text: controller.binding(lifetime), axis: .vertical)
            .lineLimit(3...12).focused($focused)
            .accessibilityIdentifier("projectEdit.block." + controller.blockID)
            .disabled(!controller.canEdit)
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            guard focused, scenePhase == .active, let completion else { return }
                            _ = controller.finish(completion); focused = false
                        } label: { Text("projectStoryText.finish", tableName: "ProjectStoryTextField") }
                        .disabled(completion == nil).accessibilityIdentifier("projectStoryText.finish." + controller.blockID)
                        .accessibilityHint(Text("projectStoryText.finishHint", tableName: "ProjectStoryTextField"))
                    }
                }
            }
            .onAppear { controller.appear(sceneActive: scenePhase == .active) }
            .onChange(of: focused) { _, next in
                if next && scenePhase == .active { controller.begin() }
                else { controller.retire(controller.lifetime) } // Unclassified blur NEVER removes text.
            }
            .onChange(of: controller.lifetime) { _, next in if next == nil { focused = false } }
            .onChange(of: model.draftMutationRevision) { _, _ in controller.synchronize() }
            .onChange(of: model.editorIncarnation) { _, _ in controller.retire(controller.lifetime); controller.synchronize() }
            .onChange(of: model.coordinator.session) { _, _ in controller.retire(controller.lifetime) }
            .onChange(of: model.canEdit) { _, allowed in if !allowed { controller.retire(controller.lifetime) } }
            .onChange(of: scenePhase) { _, next in controller.setSceneActive(next == .active); if next != .active { focused = false } }
            .onDisappear { controller.disappear() }
    }
}
