import SwiftUI

@MainActor struct ProjectEditStarterPresentation: ViewModifier {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectEditStarterController
    func body(content: Content) -> some View {
        let original = controller.destination
        content.sheet(item: Binding<ProjectEditStarterController.Destination?>(get: {
            guard let value = controller.destination, controller.isCurrent(value) else { return nil }; return value
        }, set: { next in
            if next == nil, let original { controller.close(original) }
        })) { value in
            NavigationStack { ProjectEditStarterDestination(model: model, controller: controller, original: value) }
        }
    }
}

@MainActor private struct ProjectEditStarterDestination: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectEditStarterController
    let original: ProjectEditStarterController.Destination
    var body: some View {
        Group {
            if controller.isCurrent(original) {
                switch original.kind {
                case .story:
                    ProjectEditChapterView(model: model, chapterID: original.chapterID, starterLease: original)
                case .firstNode:
                    Form {
                        Section {
                            Text("projectPending.firstNodeScope").accessibilityIdentifier("projectStarter.firstNodeScope")
                            Text(verbatim: model.starterChapter(original).wrappedValue.name)
                        }
                        if controller.saveUnconfirmed { Section { Text("projectPending.saveUnconfirmed").accessibilityIdentifier("projectPending.saveUnconfirmed") } }
                        ProjectEditNodeFields(node: controller.node(for: original))
                            .descriptionEditing(.init(model: model, sourceID: "starter:\(original.id)",
                                isCurrent: { controller.isCurrent(original) }))
                            .merchantDraftSelection(.init(
                            model: model, node: controller.node(for: original), sourceID: "starter:\(original.id)",
                            nodeRevision: { controller.candidateRevision }, isCurrent: { controller.isCurrent(original) }))
                    }.appNavigationTitle("projectStarter.firstNodeTitle").navigationBarTitleDisplayMode(.inline)
                        .scrollDismissesKeyboard(.interactively)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(LocalizedStringKey(controller.willSaveToPending(original) ? "projectPending.saveMaterial" : "projectStarter.addToChapter")) { controller.finish(original) }
                                    .disabled(!controller.canFinish(original)).accessibilityIdentifier("projectStarter.finishNode")
                            }
                        }
                }
            } else { Text("projectStarter.stale") }
        }.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LocalizedStringKey(controller.saveUnconfirmed ? "projectPending.closeUnconfirmed" : (original.kind == .story ? "projectStarter.backToChapters" : "action.cancel"))) { controller.close(original) }
                    .accessibilityIdentifier("projectStarter.close")
            }
        }
    }
}
