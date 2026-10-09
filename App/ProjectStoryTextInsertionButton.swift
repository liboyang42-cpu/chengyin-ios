import SwiftUI

/// An immutable rendered action. The existing FULL editor lease and every-setter
/// revision reject stale menus, changed owners and repeated invocations.
@MainActor struct ProjectStoryTextInsertionAction {
    let model: ProjectEditModel
    let snapshot: ProjectStoryTextInsertion
    private let lease: ProjectEditStarterController.Lease
    private let revision: Int
    init?(model: ProjectEditModel, chapterID: String, beforeBlockID: String) {
        let snapshot = ProjectStoryTextInsertion(draft: model.draft, chapterID: chapterID, beforeBlockID: beforeBlockID)
        guard model.fullEdit, snapshot.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        self.model = model; self.snapshot = snapshot; self.lease = lease; revision = model.draftMutationRevision
    }
    @discardableResult func insert(makeID: () -> String = { UUID().uuidString }) -> Bool {
        guard model.fullEdit, model.isCurrentStarterLease(lease), model.draftMutationRevision == revision,
              snapshot.isCurrent(in: model.draft), let next = try? snapshot.inserting(blockID: makeID(), in: model.draft),
              model.isCurrentStarterLease(lease), model.draftMutationRevision == revision else { return false }
        model.draft = next // Normal working draft; existing autosave/Save local own persistence.
        return true
    }
}

@MainActor struct ProjectStoryTextInsertionButton: View {
    let action: ProjectStoryTextInsertionAction?
    let beforeBlockID: String
    var body: some View {
        Button { _ = action?.insert() } label: { Text("projectStoryTextInsertion.before", tableName: "ProjectStoryTextInsertion") }
            .disabled(action == nil).accessibilityIdentifier("projectStoryTextInsertion.before." + beforeBlockID)
    }
}
