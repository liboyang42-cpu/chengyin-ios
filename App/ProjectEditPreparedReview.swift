import SwiftUI

struct ProjectEditPreparedReviewLease: Equatable {
    let session: ProjectEditSession
    let identity: ProjectEditDraftIdentity
    let incarnation: UUID
}

@MainActor extension ProjectEditModel {
    func currentReviewLease() -> ProjectEditPreparedReviewLease? {
        guard canEdit, let session = coordinator.session, let identity = coordinator.identity else { return nil }
        return .init(session: session, identity: identity, incarnation: editorIncarnation)
    }
    func ownsReview(_ value: ProjectEditConfirmation) -> Bool {
        guard let reviewLease else { return false }
        return confirmation?.id == value.id && coordinator.confirmation?.id == value.id &&
            reviewLease.session == coordinator.session && reviewLease.identity == coordinator.identity &&
            reviewLease.incarnation == editorIncarnation
    }
    func reviewIsCurrent(_ value: ProjectEditConfirmation) -> Bool {
        guard ownsReview(value), let current = ProjectEditPendingMaterials.exactData(draft),
              let captured = ProjectEditPendingMaterials.exactData(value.draft) else { return false }
        return current == captured
    }
    func cancelReview(_ value: ProjectEditConfirmation) {
        guard ownsReview(value) else { return }; cancelReview()
    }
}

/// Dismissal/confirmation stay bound to the originally presented immutable request.
@MainActor struct ProjectEditPreparedReviewPresentation: ViewModifier {
    @ObservedObject var model: ProjectEditModel
    func body(content: Content) -> some View {
        let original = model.confirmation
        content.sheet(item: Binding<ProjectEditConfirmation?>(get: {
            guard let value = model.confirmation, model.reviewIsCurrent(value) else { return nil }; return value
        }, set: { next in if next == nil, let original { model.cancelReview(original) } })) { value in
            ProjectEditPreparedReviewDestination(model: model, original: value)
        }
    }
}

@MainActor private struct ProjectEditPreparedReviewDestination: View {
    @ObservedObject var model: ProjectEditModel
    let original: ProjectEditConfirmation
    var body: some View {
        if model.reviewIsCurrent(original) {
            ProjectEditReviewView(confirmation: original, canSimulate: model.coordinator.canSimulate,
                canSubmit: model.coordinator.canSubmit, busy: model.busy, localSaveConfirmed: model.reviewLocalSaveConfirmed,
                cancel: { model.cancelReview(original) }, confirm: { Task { await model.submit(original) } })
        } else { Text("projectPrepared.stale") }
    }
}

struct ProjectEditPreparedNodesView: View {
    let value: ProjectEditPreparedNodes
    var body: some View {
        Section("projectPrepared.nodes") {
            Text("projectPrepared.scope")
            if value.omitted { Text("projectPrepared.omittedChapters").accessibilityIdentifier("projectPrepared.omittedChapters") }
            else if let chapters = value.chapters {
                if chapters.isEmpty { Text("projectPrepared.emptyChapters") }
                ForEach(chapters) { chapter in
                    VStack(alignment: .leading, spacing: 10) {
                        if chapter.isObject {
                        ProjectEditPreparedValue(value: chapter.name).font(.headline)
                            .accessibilityIdentifier("projectPrepared.chapter.\(chapter.id).name")
                        LabeledContent { ProjectEditPreparedValue(value: chapter.description) } label: { Text("projectEdit.story") }
                        if let nodes = chapter.nodes {
                            if nodes.isEmpty { Text("projectPrepared.emptyNodes") }
                            ForEach(nodes) { node in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("projectPrepared.nodePosition \(node.id + 1)").font(.headline)
                                    if node.isObject {
                                        ForEach(ProjectEditPreparedNodes.Field.allCases) { field in
                                            LabeledContent {
                                                ProjectEditPreparedValue(value: node.value(field))
                                                    .accessibilityIdentifier("projectPrepared.chapter.\(chapter.id).node.\(node.id)." + field.rawValue)
                                            } label: { Text(LocalizedStringKey("projectPrepared.field." + field.rawValue)) }
                                        }
                                    } else { Text("projectPrepared.unsupported") }
                                }.padding(.vertical, 4)
                            }
                        } else { Text(LocalizedStringKey(chapter.nodesOmitted ? "projectPrepared.omittedNodes" : "projectPrepared.unsupported")) }
                        } else { Text("projectPrepared.unsupported") }
                    }
                }
            } else { Text("projectPrepared.unsupported") }
        }
    }
}

private struct ProjectEditPreparedValue: View {
    let value: ProjectEditPreparedNodes.Value
    var body: some View {
        Group {
            if let text = value.text {
                if text.isEmpty { Text("projectPrepared.emptyValue") }
                else { Text(verbatim: text) }
            } else { Text(LocalizedStringKey(value.raw == nil ? "projectPrepared.omittedValue" : "projectPrepared.unsupported")) }
        }.multilineTextAlignment(.trailing).textSelection(.enabled)
    }
}

struct ProjectEditPreparedPayloadView: View {
    let payload: [String: ProjectEditJSON]
    @State private var expanded = false
    var body: some View {
        Section {
            DisclosureGroup("projectPrepared.allFields", isExpanded: $expanded) {
                if expanded {
                    if let bytes = ProjectEditPendingMaterials.exactData(payload) {
                        Text(verbatim: String(decoding: bytes, as: UTF8.self)).textSelection(.enabled)
                            .accessibilityIdentifier("projectPrepared.allFields")
                    } else { Text("projectPrepared.unsupported") }
                }
            }
        }
    }
}
