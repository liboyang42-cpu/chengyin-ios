import SwiftUI

@MainActor final class ProjectTeamConfigurationController: ObservableObject {
    struct Capture {
        let controller: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let bytes: Data
        let baselineBytes: Data
    }
    struct Presentation: Identifiable { let id = UUID(); let capture: Capture }
    let model: ProjectEditModel
    private let identity = UUID()
    private var generation = 0
    @Published private(set) var presentation: Presentation?
    @Published private(set) var buffer: ProjectTeamConfiguration?
    init(model: ProjectEditModel) { self.model = model }
    var available: Bool { model.fullEdit && model.draft.product == .city }
    func capture() -> Capture? {
        guard available, let lease = model.captureStarterLease(), let baseline = model.coordinator.snapshot,
              let bytes = ProjectEditPendingMaterials.exactData(model.draft),
              let baselineBytes = ProjectEditPendingMaterials.exactData(baseline) else { return nil }
        return .init(controller: identity, generation: generation, lease: lease,
                     revision: model.draftMutationRevision, bytes: bytes, baselineBytes: baselineBytes)
    }
    private func current(_ capture: Capture) -> Bool {
        capture.controller == identity && capture.generation == generation && available &&
        model.isCurrentStarterLease(capture.lease) && model.draftMutationRevision == capture.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == capture.bytes &&
        model.coordinator.snapshot.flatMap({ ProjectEditPendingMaterials.exactData($0) }) == capture.baselineBytes
    }
    func open(_ capture: Capture) {
        guard presentation == nil, current(capture) else { return }
        buffer = .init(draft: model.draft, baseline: model.coordinator.snapshot); presentation = .init(capture: capture)
    }
    func isCurrent(_ original: Presentation) -> Bool { presentation?.id == original.id && current(original.capture) }
    func selectMode(_ value: ProjectTeamConfiguration.Mode, in original: Presentation) {
        guard isCurrent(original) else { return }; buffer?.selectMode(value)
    }
    func selectMaximum(_ value: Int, in original: Presentation) {
        guard isCurrent(original) else { return }; buffer?.selectMaximum(value)
    }
    @discardableResult func apply(_ original: Presentation) -> Bool {
        guard isCurrent(original), let buffer, let next = try? buffer.applying(to: model.draft) else { return false }
        if ProjectEditPendingMaterials.exactData(next) != original.capture.bytes { model.draft = next }
        close(original); return true
    }
    func close(_ original: Presentation) { guard presentation?.id == original.id else { return }; retire() }
    func retire() { presentation = nil; buffer = nil; generation += 1 }
    func synchronize() { if let presentation, !isCurrent(presentation) { retire() } }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        .init(get: { guard let original, self.isCurrent(original) else { return nil }; return original },
              set: { if $0 == nil, let original { self.close(original) } })
    }
}

@MainActor struct ProjectTeamConfigurationEntry: View {
    @ObservedObject private var model: ProjectEditModel
    @StateObject private var controller: ProjectTeamConfigurationController
    init(model: ProjectEditModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        let captured = controller.capture(), original = controller.presentation
        Section {
            if model.draft.product == .city {
                Button { if let captured { controller.open(captured) } } label: { text("title") }
                    .disabled(captured == nil || original != nil).accessibilityIdentifier("projectTeamConfiguration.open")
            }
            if model.fullEdit && !ProjectTeamConfiguration.canSubmit(model.draft, baseline: model.coordinator.snapshot) { text("unsupported").font(.caption) }
        }
        .sheet(item: controller.binding(original)) { original in ProjectTeamConfigurationSheet(controller: controller, original: original) }
        .onChange(of: model.draftMutationRevision) { _, _ in controller.synchronize() }
        .onChange(of: model.editorIncarnation) { _, _ in controller.retire() }
        .onChange(of: model.coordinator.session) { _, _ in controller.synchronize() }
        .onDisappear { controller.retire() }
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey("projectTeamConfiguration." + key), tableName: "ProjectTeamConfiguration") }
}

@MainActor private struct ProjectTeamConfigurationSheet: View {
    @ObservedObject var controller: ProjectTeamConfigurationController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectTeamConfigurationController.Presentation
    init(controller: ProjectTeamConfigurationController, original: ProjectTeamConfigurationController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
    }
    var body: some View {
        NavigationStack {
            Form {
                if !controller.isCurrent(original) { text("stale") }
                else if let buffer = controller.buffer {
                    if buffer.readOnly { text("unsupported") }
                    else {
                        text("scope").font(.caption)
                        Picker(selection: Binding(get: { controller.buffer?.mode ?? .off }, set: { controller.selectMode($0, in: original) })) {
                            text("modeOff").tag(ProjectTeamConfiguration.Mode.off)
                            text("modeAtRegistration").tag(ProjectTeamConfiguration.Mode.atRegistration)
                            text("modeAfterRegistration").tag(ProjectTeamConfiguration.Mode.afterRegistration)
                        } label: { text("mode") }
                        Picker(selection: Binding(get: { controller.buffer?.maximum ?? 4 }, set: { controller.selectMaximum($0, in: original) })) {
                            ForEach(2...4, id: \.self) { value in Text(verbatim: String(value)).tag(value) }
                        } label: { text("maximum") }
                        text("defaults").font(.caption)
                        text("capacityScope").font(.caption)
                    }
                }
            }
            .navigationTitle(Text("projectTeamConfiguration.title", tableName: "ProjectTeamConfiguration"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { controller.close(original) } label: { text("cancel") } }
                ToolbarItem(placement: .confirmationAction) { Button { _ = controller.apply(original) } label: { text("apply") }
                    .disabled(!controller.isCurrent(original) || controller.buffer?.readOnly != false) }
            }
        }
        .onDisappear { controller.close(original) }
    }
    private func text(_ key: String) -> Text { Text(LocalizedStringKey("projectTeamConfiguration." + key), tableName: "ProjectTeamConfiguration") }
}
