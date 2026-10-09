import SwiftUI

/// Saved-node and pending-candidate captures cannot be interchanged.
@MainActor enum ProjectNodePlaceTargetSnapshot {
    case saved(ProjectNodePlaceSelection)
    case pending(ProjectPendingNodePlaceCapture)
    func isCurrent(model: ProjectEditModel) -> Bool {
        switch self {
        case .saved(let value): return value.isCurrent(in: model.draft)
        case .pending(let value): return value.isCurrent(model: model)
        }
    }
    func apply(_ poi: SearchMapCityNode, model: ProjectEditModel) -> Bool {
        guard isCurrent(model: model) else { return false }
        switch self {
        case .saved(let value):
            guard let next = try? value.applying(poi, to: model.draft) else { return false }
            if ProjectEditPendingMaterials.exactData(next) != ProjectEditPendingMaterials.exactData(model.draft) { model.draft = next }
            return true
        case .pending(let value): return value.apply(poi, model: model)
        }
    }
}
@MainActor struct ProjectPendingNodePlaceContext {
    let controller: ProjectEditPendingController
    let destination: ProjectEditPendingController.Destination
    func capture() -> ProjectPendingNodePlaceCapture? {
        guard controller.model.fullEdit, destination.kind == .edit, controller.isCurrent(destination),
              Data(controller.candidate.id.utf8) == Data(destination.target.materialID.utf8),
              controller.model.draft.pendingMaterials?.filter({ $0.id == destination.target.materialID }).count == 1,
              !controller.model.draft.chapters.flatMap(\.nodes).contains(where: { $0.id == destination.target.materialID }),
              let bytes = ProjectEditPendingMaterials.exactData(controller.candidate),
              let draft = ProjectEditPendingMaterials.exactData(controller.model.draft) else { return nil }
        return .init(context: self, revision: controller.candidateRevision, bytes: bytes, draft: draft)
    }
}
@MainActor struct ProjectPendingNodePlaceCapture {
    let context: ProjectPendingNodePlaceContext
    let revision: Int
    let bytes: Data, draft: Data
    func isCurrent(model: ProjectEditModel) -> Bool {
        context.controller.model === model && model.fullEdit && context.destination.kind == .edit &&
        context.controller.isCurrent(context.destination) && context.controller.candidateRevision == revision &&
        Data(context.controller.candidate.id.utf8) == Data(context.destination.target.materialID.utf8) &&
        ProjectEditPendingMaterials.exactData(context.controller.candidate) == bytes &&
        ProjectEditPendingMaterials.exactData(model.draft) == draft
    }
    func apply(_ poi: SearchMapCityNode, model: ProjectEditModel) -> Bool {
        guard isCurrent(model: model),
              let next = try? ProjectNodePlaceSelection.replacingLocation(of: context.controller.candidate, with: poi),
              let nextBytes = ProjectEditPendingMaterials.exactData(next) else { return false }
        if nextBytes == bytes { return true }
        // Only the staged candidate changes. Existing Save material is the sole persistence action.
        context.controller.node(for: context.destination).wrappedValue = next
        return context.controller.isCurrent(context.destination) && context.controller.candidateRevision == revision + 1 &&
            ProjectEditPendingMaterials.exactData(context.controller.candidate) == nextBytes &&
            ProjectEditPendingMaterials.exactData(model.draft) == draft
    }
}
struct ProjectPendingNodePlaceHostIdentity: Hashable {
    let owner: ObjectIdentifier, controller: ObjectIdentifier
    let reader: ObjectIdentifier?
    let destination: UUID
    let node: Data
}
@MainActor struct ProjectPendingNodePlacePickerEntry: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var pending: ProjectEditPendingController
    let destination: ProjectEditPendingController.Destination
    @Environment(\.projectNodePlaceReader) private var reader
    var body: some View {
        ProjectNodePlacePickerHost(model: model, reader: reader, chapterID: "", nodeID: destination.target.materialID,
            pendingTarget: .init(controller: pending, destination: destination))
            .id(ProjectPendingNodePlaceHostIdentity(owner: ObjectIdentifier(model), controller: ObjectIdentifier(pending),
                reader: reader.map(ObjectIdentifier.init), destination: destination.id, node: Data(destination.target.materialID.utf8)))
    }
}
