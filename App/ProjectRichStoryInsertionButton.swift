import SwiftUI

/// Same immutable rendered-action lifetime as the existing text gap action.
@MainActor struct ProjectRichStoryInsertionAction {
    let model: ProjectEditModel
    let snapshot: ProjectRichStoryInsertion
    private let lease: ProjectEditStarterController.Lease
    private let revision: Int
    init?(model: ProjectEditModel, chapterID: String, beforeBlockID: String) {
        let snapshot = ProjectRichStoryInsertion(draft: model.draft, chapterID: chapterID, beforeBlockID: beforeBlockID)
        guard model.fullEdit, snapshot.isCurrent(in: model.draft), let lease = model.captureStarterLease() else { return nil }
        self.model = model; self.snapshot = snapshot; self.lease = lease; revision = model.draftMutationRevision
    }
    @discardableResult func insert(_ kind: ProjectEditBlock.Kind, makeID: () -> String = { UUID().uuidString }) -> Bool {
        guard model.fullEdit, model.isCurrentStarterLease(lease), model.draftMutationRevision == revision,
              snapshot.isCurrent(in: model.draft), let next = try? snapshot.inserting(kind, blockID: makeID(), in: model.draft),
              model.isCurrentStarterLease(lease), model.draftMutationRevision == revision else { return false }
        model.draft = next // Existing working draft autosave / Save local owns persistence.
        return true
    }
}

@MainActor struct ProjectRichStoryInsertionButton: View {
    let action: ProjectRichStoryInsertionAction?
    let beforeBlockID: String
    var body: some View {
        Menu {
            ForEach(ProjectEditRichStoryContract.richKinds, id: \.self) { kind in
                Button(LocalizedStringKey("projectEdit.rich.kind." + kind.rawValue)) { _ = action?.insert(kind) }
                    .disabled(action == nil).accessibilityIdentifier("projectRichStoryInsertion." + kind.rawValue + "." + beforeBlockID)
            }
        } label: { Text("projectRichStoryInsertion.before", tableName: "ProjectRichStoryInsertion") }
            .disabled(action == nil).accessibilityIdentifier("projectRichStoryInsertion.before." + beforeBlockID)
    }
}
