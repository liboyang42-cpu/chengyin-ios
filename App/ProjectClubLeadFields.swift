import SwiftUI

@MainActor final class ProjectClubLeadController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let draftBytes: Data
    }
    let model: ProjectEditModel
    private let controllerID = UUID()
    @Published private(set) var generation = 0
    init(model: ProjectEditModel) { self.model = model }
    func matchesHost(_ model: ProjectEditModel) -> Bool { self.model === model }
    func capture() -> Capture? {
        guard ProjectClubLead.isEligible(model.draft), ProjectClubLead.supportsEditing(model.draft),
              let lease = model.captureStarterLease(),
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease,
                     revision: model.draftMutationRevision, draftBytes: bytes)
    }
    func isCurrent(_ value: Capture) -> Bool {
        value.controllerID == controllerID && value.generation == generation &&
        model.isCurrentStarterLease(value.lease) && model.draftMutationRevision == value.revision &&
        ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes &&
        ProjectClubLead.isEligible(model.draft) && ProjectClubLead.supportsEditing(model.draft)
    }
    func apply(_ enabled: Bool, captured: Capture?) {
        guard let captured, isCurrent(captured),
              let next = try? ProjectClubLead.applying(enabled, to: model.draft),
              ProjectEditPendingMaterials.exactData(next) != captured.draftBytes else { return }
        // The parent owns autosave/review. This working-draft edit does not claim
        // durable persistence, publish a topic or send an invitation.
        model.draft = next
    }
    func binding(_ captured: Capture?) -> Binding<Bool> {
        Binding(get: { ProjectClubLead.isSelected(self.model.draft) },
                set: { self.apply($0, captured: captured) })
    }
    func retire() { generation += 1 }
}

@MainActor struct ProjectClubLeadFields: View {
    @ObservedObject var model: ProjectEditModel
    var body: some View {
        ProjectClubLeadHost(model: model).id(ObjectIdentifier(model))
    }
}

@MainActor private struct ProjectClubLeadHost: View {
    @ObservedObject var model: ProjectEditModel
    @StateObject private var controller: ProjectClubLeadController
    init(model: ProjectEditModel) {
        self.model = model; _controller = StateObject(wrappedValue: .init(model: model))
    }
    var body: some View {
        let ownsHost = controller.matchesHost(model)
        let captured = ownsHost ? controller.capture() : nil
        Section("projectClubLead.title") {
            if ownsHost && ProjectClubLead.isEligible(model.draft) && ProjectClubLead.supportsEditing(model.draft) {
                Toggle("projectClubLead.enabled", isOn: controller.binding(captured))
                    .disabled(captured == nil).accessibilityIdentifier("projectClubLead.enabled")
                Text("projectClubLead.hint").font(.footnote).foregroundStyle(.secondary)
            } else if ownsHost {
                ProjectClubLeadSummary(draft: model.draft)
            }
        }.onDisappear { controller.retire() }
    }
}

struct ProjectClubLeadSummary: View {
    let draft: ProjectEditDraft
    var body: some View {
        if !ProjectClubLead.supportsEditing(draft) {
            Text("projectClubLead.unsupported").accessibilityIdentifier("projectClubLead.unsupported")
        } else if !ProjectClubLead.isEligible(draft) {
            Text("projectClubLead.ineligible").accessibilityIdentifier("projectClubLead.ineligible")
        } else {
            LabeledContent {
                Text(LocalizedStringKey(ProjectClubLead.isSelected(draft) ? "projectEdit.yes" : "projectEdit.no"))
            } label: { Text("projectClubLead.enabled") }
        }
    }
}
