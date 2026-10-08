import SwiftUI

/// Both the swipe callback and its confirmation retain the exact rendered draft.
/// A callback never resolves old offsets against a replacement chapter list.
@MainActor final class ProjectChapterRemovalController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let draftBytes: Data
        let chapterIDs: [String]
    }
    struct Confirmation: Identifiable {
        let id = UUID()
        let capture: Capture
        let chapters: [ProjectEditChapter]
        let readback: ProjectEditCoordinator.ChapterRemovalReadback
    }
    let model: ProjectEditModel
    private let controllerID = UUID()
    private var generation = 0
    private var saving = false
    @Published private(set) var confirmation: Confirmation?
    var saveUnconfirmed: Bool { model.coordinator.hasUnconfirmedChapterRemoval }
    @Published private(set) var readbackResult: ProjectEditCoordinator.ChapterRemovalReadbackResult?
    @Published private(set) var failedConfirmation: Confirmation?

    init(model: ProjectEditModel) { self.model = model }

    func capture() -> Capture? {
        guard !saveUnconfirmed, let lease = model.captureStarterLease(), !model.draft.chapters.isEmpty,
              (try? ProjectChapterRemoval.selecting(model.draft.chapters.map(\.id), in: model.draft)) != nil,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease,
                     revision: model.draftMutationRevision, draftBytes: bytes, chapterIDs: model.draft.chapters.map(\.id))
    }
    func isCurrent(_ value: Capture) -> Bool {
        value.controllerID == controllerID && value.generation == generation &&
        model.isCurrentStarterLease(value.lease) && model.draftMutationRevision == value.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes &&
        model.draft.chapters.map(\.id) == value.chapterIDs
    }
    func isCurrent(_ value: Confirmation) -> Bool {
        guard confirmation?.id == value.id else { return false }
        if saveUnconfirmed, failedConfirmation?.id == value.id { return readbackContextIsCurrent(value.capture) }
        return isCurrent(value.capture)
    }
    private func readbackContextIsCurrent(_ value: Capture) -> Bool {
        value.controllerID == controllerID && value.generation == generation && model.ownsVisit &&
        model.coordinator.session == value.lease.session && model.coordinator.identity == value.lease.identity &&
        model.coordinator.snapshot?.scope == .full && model.editorIncarnation == value.lease.incarnation &&
        model.draftMutationRevision == value.revision && ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes
    }
    func open(offsets: IndexSet, captured: Capture?) {
        guard !saving, !saveUnconfirmed, let captured, isCurrent(captured), !offsets.isEmpty,
              offsets.allSatisfy({ captured.chapterIDs.indices.contains($0) }) else { return }
        if let confirmation, isCurrent(confirmation) { return }
        let ids = offsets.map { captured.chapterIDs[$0] }
        guard let chapters = try? ProjectChapterRemoval.selecting(ids, in: model.draft),
              let readback = model.coordinator.captureChapterRemovalReadback(for: model.draft, removing: ids) else { return }
        readbackResult = nil
        confirmation = .init(capture: captured, chapters: chapters, readback: readback)
    }
    func confirm(_ value: Confirmation) {
        guard !saving, !saveUnconfirmed, isCurrent(value),
              let next = try? ProjectChapterRemoval.removing(value.chapters.map(\.id), from: model.draft) else { return }
        saving = true
        defer { saving = false }
        guard model.persistLocalChange(next, lease: value.capture.lease) else {
            model.coordinator.suspendLocalWritesAfterChapterRemoval(value.readback)
            failedConfirmation = value
            return
        }
        failedConfirmation = nil
        confirmation = nil
        generation += 1
    }
    func close(_ value: Confirmation) {
        guard !saving, confirmation?.id == value.id else { return }
        confirmation = nil
        if !saveUnconfirmed { generation += 1 }
    }
    var canInspect: Bool {
        guard !saving, saveUnconfirmed, let failedConfirmation else { return false }
        return readbackContextIsCurrent(failedConfirmation.capture)
    }
    func inspect() {
        guard canInspect, let failedConfirmation else { return }
        let result = model.coordinator.inspectChapterRemoval(failedConfirmation.readback)
        guard readbackContextIsCurrent(failedConfirmation.capture) else { readbackResult = .stale; return }
        readbackResult = result
        // Readback is informational. It does not repair the active pointer, replace
        // the displayed draft, acknowledge the save or release the consumed intent.
    }
    func retire() {
        confirmation = nil; readbackResult = nil; generation += 1
    }
    func binding(_ original: Confirmation?) -> Binding<Confirmation?> {
        Binding(get: {
            guard let original, self.isCurrent(original) else { return nil }
            return original
        }, set: { next in
            guard next == nil, let original else { return }
            self.close(original)
        })
    }
}

@MainActor struct ProjectChapterRemovalPresentation: ViewModifier {
    @ObservedObject var model: ProjectEditModel
    @ObservedObject var controller: ProjectChapterRemovalController
    func body(content: Content) -> some View {
        let original = controller.confirmation
        content.sheet(item: controller.binding(original)) { value in
            NavigationStack {
                Form {
                    if controller.isCurrent(value) {
                        Section {
                            Text("projectChapterRemoval.warning")
                            Text("projectChapterRemoval.localOnly").font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("projectChapterRemoval.selected") {
                            ForEach(value.chapters) { chapter in
                                VStack(alignment: .leading, spacing: 6) {
                                    ProjectEditName(value: chapter.name, fallback: "projectEdit.untitledChapter")
                                    LabeledContent("projectEdit.nodeCount", value: String(chapter.nodes.count))
                                }.accessibilityElement(children: .combine)
                            }
                        }
                        if controller.saveUnconfirmed {
                            Section { ProjectChapterRemovalStatus(controller: controller) }
                        }
                        Section {
                            Button("projectChapterRemoval.confirm", role: .destructive) { controller.confirm(value) }
                                .disabled(controller.saveUnconfirmed)
                                .accessibilityIdentifier("projectChapterRemoval.confirm")
                        }
                    } else { Text("projectStarter.stale") }
                }
                .appNavigationTitle("projectChapterRemoval.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey(controller.saveUnconfirmed ? "projectChapterRemoval.closeUnconfirmed" : "action.cancel")) {
                        controller.close(value)
                    }.accessibilityIdentifier("projectChapterRemoval.cancel")
                } }
            }
        }
    }
}

@MainActor struct ProjectChapterRemovalStatus: View {
    @ObservedObject var controller: ProjectChapterRemovalController
    @ObservedObject private var model: ProjectEditModel
    init(controller: ProjectChapterRemovalController) {
        self.controller = controller; model = controller.model
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("projectChapterRemoval.saveUnconfirmed").accessibilityIdentifier("projectChapterRemoval.saveUnconfirmed")
            if let result = controller.readbackResult, controller.canInspect {
                Text(LocalizedStringKey(resultKey(result))).accessibilityIdentifier("projectChapterRemoval.readbackResult")
            } else if !controller.canInspect {
                Text("projectChapterRemoval.readback.stale")
            }
            Button("projectChapterRemoval.inspect") { controller.inspect() }
                .disabled(!controller.canInspect).accessibilityIdentifier("projectChapterRemoval.inspect")
        }
    }
    private func resultKey(_ result: ProjectEditCoordinator.ChapterRemovalReadbackResult) -> String {
        switch result {
        case .original: return "projectChapterRemoval.readback.original"
        case .removed: return "projectChapterRemoval.readback.removed"
        case .other: return "projectChapterRemoval.readback.other"
        case .missing: return "projectChapterRemoval.readback.missing"
        case .unavailable: return "projectChapterRemoval.readback.unavailable"
        case .stale: return "projectChapterRemoval.readback.stale"
        }
    }
}
