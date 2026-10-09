import SwiftUI

@MainActor struct ProjectEditPendingSection: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectEditPendingController
    @Environment(\.locale) private var locale
    var body: some View {
        if let materials = model.draft.pendingMaterials, !materials.isEmpty {
            Section("projectPending.title") {
                Text("projectPending.localOnly")
                if controller.saveUnconfirmed { Text("projectPending.saveUnconfirmed").accessibilityIdentifier("projectPending.saveUnconfirmed") }
                if controller.actionUnavailable { Text("projectPending.unavailable") }
                ForEach(materials) { material in
                    let target = controller.capture(material.id)
                    let newChapter = controller.captureNewChapter(material.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(material.kind == .place ? "projectPending.kindPlace" : "projectPending.kindNode")).font(.caption)
                        Text(verbatim: material.node.name).font(.headline).accessibilityIdentifier("projectPending.name." + material.id)
                        Text(verbatim: material.node.description)
                        Text(verbatim: material.node.address)
                        if !material.node.imgUrl.isEmpty { Text(verbatim: material.node.imgUrl).font(.caption) }
                        HStack {
                            Button("projectPending.edit") { controller.open(target) }.buttonStyle(.borderless)
                                .accessibilityIdentifier("projectPending.edit." + material.id)
                            if !model.draft.chapters.isEmpty {
                                Menu {
                                    ForEach(model.draft.chapters) { chapter in
                                        Button { controller.chooseChapter(chapter.id, target: target) } label: { ProjectEditName(value: chapter.name, fallback: "projectEdit.untitledChapter") }
                                            .accessibilityIdentifier("projectPending.chapter." + chapter.id)
                                    }
                                } label: { Text(LocalizedStringKey(model.draft.product == .city ? "projectPending.arrangeStory" : "projectPending.chooseChapter")) }
                                .accessibilityIdentifier("projectPending.arrange." + material.id)
                            }
                            Button("projectPending.remove", role: .destructive) { controller.open(target, kind: .remove) }.buttonStyle(.borderless)
                                .accessibilityIdentifier("projectPending.remove." + material.id)
                        }
                        Button {
                            let ordinal = model.draft.chapters.filter { $0.preserved["opening"] != .bool(true) }.count + 1
                            let name = String(localized: LocalizedStringResource("projectStarter.defaultChapter", defaultValue: "Chapter \(ordinal)", locale: locale))
                            controller.createChapter(newChapter, name: name)
                        } label: { Text(LocalizedStringKey(model.draft.product == .city ? "projectPending.newStoryChapter" : "projectPending.newFreeChapter")) }
                        .buttonStyle(.borderless).disabled(newChapter == nil)
                        .accessibilityIdentifier("projectPending.newChapter." + material.id)
                    }.disabled(target == nil)
                }
            }
        }
    }
}

@MainActor struct ProjectEditPendingPresentation: ViewModifier {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectEditPendingController
    func body(content: Content) -> some View {
        let original = controller.destination
        content.sheet(item: Binding<ProjectEditPendingController.Destination?>(get: {
            guard let value = controller.destination, controller.isCurrent(value) else { return nil }; return value
        }, set: { next in if next == nil, let original { controller.close(original) } })) { value in
            NavigationStack { ProjectEditPendingDestination(model: model, controller: controller, original: value) }
        }
    }
}

@MainActor private struct ProjectEditPendingDestination: View {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectEditPendingController
    let original: ProjectEditPendingController.Destination
    private var closeTitle: String { if controller.saveUnconfirmed { return "projectPending.closeUnconfirmed" }; if case .story = original.kind { return "projectPending.backToMaterials" }; return "action.cancel" }
    var body: some View {
        Group {
            if controller.isCurrent(original) {
                switch original.kind {
                case .edit:
                    Form {
                        Section { Text("projectPending.localOnly") }
                        if controller.saveUnconfirmed { Section { Text("projectPending.saveUnconfirmed").accessibilityIdentifier("projectPending.saveUnconfirmed") } }
                        ProjectPendingNodePlacePickerEntry(model: model, pending: controller, destination: original)
                        ProjectEditNodeFields(node: controller.node(for: original))
                            .descriptionEditing(.init(model: model, sourceID: "pending:\(original.id)",
                                isCurrent: { controller.isCurrent(original) }))
                            .merchantDraftSelection(.init(
                            model: model, node: controller.node(for: original), sourceID: "pending:\(original.id)",
                            nodeRevision: { controller.candidateRevision }, isCurrent: { controller.isCurrent(original) }))
                    }.appNavigationTitle("projectPending.edit")
                        .scrollDismissesKeyboard(.interactively)
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button("projectPending.saveMaterial") { controller.save(original) }.disabled(!controller.canSave(original)).accessibilityIdentifier("projectPending.save")
                        } }
                case .remove:
                    Form {
                        Section {
                            Text("projectPending.removeConfirm")
                            Text(verbatim: controller.candidate.name)
                            if controller.saveUnconfirmed { Text("projectPending.saveUnconfirmed").accessibilityIdentifier("projectPending.saveUnconfirmed") }
                            Button("projectPending.remove", role: .destructive) { controller.remove(original) }
                                .buttonStyle(.borderless).accessibilityIdentifier("projectPending.confirmRemove")
                        }
                    }.appNavigationTitle("projectPending.remove")
                case .story(let chapterID):
                    ProjectEditChapterView(model: model, chapterID: chapterID,
                        chapterOverride: controller.storyChapter(original), chapterIsCurrent: { controller.isCurrent(original) },
                        mediaScope: controller.captureStoryMediaScope(original), pendingGap: { before in
                            let slot = controller.slot(original, before: before)
                            return AnyView(VStack(alignment: .leading) {
                                if controller.saveUnconfirmed { Text("projectPending.saveUnconfirmed") }
                                Button("projectPending.insertHere") { controller.insert(slot) }
                                    .buttonStyle(.borderless).disabled(!controller.canInsert(original))
                                    .accessibilityIdentifier("projectPending.insert." + (before ?? "end"))
                            })
                        }, pendingMaterialName: controller.candidate.name)
                        .id(original.id)
                }
            } else { Text("projectStarter.stale") }
        }.navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(LocalizedStringKey(closeTitle)) { controller.close(original) }.accessibilityIdentifier("projectPending.close")
            } }
    }
}
