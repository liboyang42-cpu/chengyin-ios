import SwiftUI

@MainActor struct ProjectNodeTemplateSelectionField: View {
    @ObservedObject private var model: ProjectEditModel
    let chapterID: String, nodeID: String
    @StateObject private var controller: ProjectStoryTemplatePresentation
    init(model: ProjectEditModel, chapterID: String, nodeID: String) {
        self.model = model; self.chapterID = chapterID; self.nodeID = nodeID
        _controller = StateObject(wrappedValue: .init(editor: model))
    }
    var body: some View {
        let capture = controller.captureNode(chapterID: chapterID, nodeID: nodeID), original = controller.opening
        Section {
            Button(action: { if let capture { _ = controller.open(capture) } }, label: { Text("projectNodeTemplate.choose", tableName: "ProjectNodeTemplateSelection") })
                .disabled(capture == nil).accessibilityIdentifier("projectNodeTemplate.choose")
            if capture == nil && original == nil { Text("projectNodeTemplate.unavailable", tableName: "ProjectNodeTemplateSelection").font(.caption) }
        }
        .sheet(item: controller.binding(original)) { original in
            ProjectStoryTemplateView(controller: controller, original: original, nodeSelection: true)
        }
        .onChange(of: model.editorIncarnation) { _, _ in if let original { controller.close(original) } }
        .onDisappear { if let original { controller.close(original) } }
    }
}
