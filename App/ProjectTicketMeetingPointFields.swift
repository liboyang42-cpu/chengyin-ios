import SwiftUI

struct ProjectTicketMeetingPointHostIdentity: Hashable {
    let model: ObjectIdentifier
    let ticketID: String
}

@MainActor final class ProjectTicketMeetingPointController: ObservableObject {
    struct Capture {
        let controllerID: UUID
        let generation: Int
        let lease: ProjectEditStarterController.Lease
        let revision: Int
        let draftBytes: Data
    }
    struct Presentation: Identifiable {
        let id = UUID()
        let capture: Capture
        let initial: ProjectTicketMeetingPoint
    }
    let model: ProjectEditModel
    let ticketID: String
    private let controllerID = UUID()
    private var generation = 0
    @Published private(set) var presentation: Presentation?
    init(model: ProjectEditModel, ticketID: String) { self.model = model; self.ticketID = ticketID }
    func matchesHost(model: ProjectEditModel, ticketID: String) -> Bool { self.model === model && self.ticketID == ticketID }
    var ticket: ProjectEditTicket? {
        guard model.draft.tickets.filter({ $0.id == ticketID }).count == 1 else { return nil }
        return model.draft.tickets.first { $0.id == ticketID }
    }
    func capture() -> Capture? {
        guard model.draft.product == .city, let lease = model.captureStarterLease(),
              let ticket, ProjectTicketMeetingPoint.supportsEditing(ticket),
              let bytes = ProjectEditPendingMaterials.exactData(model.draft) else { return nil }
        return .init(controllerID: controllerID, generation: generation, lease: lease,
                     revision: model.draftMutationRevision, draftBytes: bytes)
    }
    func isCurrent(_ value: Capture) -> Bool {
        guard value.controllerID == controllerID, value.generation == generation,
              model.draft.product == .city, model.isCurrentStarterLease(value.lease),
              model.draftMutationRevision == value.revision,
              ProjectEditPendingMaterials.exactData(model.draft) == value.draftBytes,
              let ticket, ProjectTicketMeetingPoint.supportsEditing(ticket) else { return false }
        return true
    }
    func isCurrent(_ value: Presentation) -> Bool { presentation?.id == value.id && isCurrent(value.capture) }
    func open(_ value: Capture?) {
        guard let value, isCurrent(value), let ticket else { return }
        if let presentation, isCurrent(presentation) { return }
        presentation = .init(capture: value, initial: .init(ticket: ticket))
    }
    func apply(_ value: ProjectTicketMeetingPoint, to original: Presentation) {
        guard isCurrent(original), let ticket, let nextTicket = try? value.applying(to: ticket),
              let index = model.draft.tickets.firstIndex(where: { $0.id == ticketID }) else { return }
        var next = model.draft; next.tickets[index] = nextTicket
        // Apply only to the working draft. The existing parent autosave/review flow
        // owns persistence and never receives a new success claim from this sheet.
        if ProjectEditPendingMaterials.exactData(next) != original.capture.draftBytes { model.draft = next }
        close(original)
    }
    func close(_ value: Presentation) {
        guard presentation?.id == value.id else { return }
        presentation = nil; generation += 1
    }
    func retire() { presentation = nil; generation += 1 }
    func binding(_ original: Presentation?) -> Binding<Presentation?> {
        Binding(get: {
            guard let original, self.isCurrent(original) else { return nil }; return original
        }, set: { value in
            guard value == nil, let original else { return }; self.close(original)
        })
    }
}

@MainActor struct ProjectTicketMeetingPointFields: View {
    @ObservedObject var model: ProjectEditModel
    let ticketID: String
    var body: some View {
        ProjectTicketMeetingPointHost(model: model, ticketID: ticketID)
            .id(ProjectTicketMeetingPointHostIdentity(model: ObjectIdentifier(model), ticketID: ticketID))
    }
}

@MainActor private struct ProjectTicketMeetingPointHost: View {
    @ObservedObject var model: ProjectEditModel
    let ticketID: String
    @StateObject private var controller: ProjectTicketMeetingPointController
    init(model: ProjectEditModel, ticketID: String) {
        self.model = model; self.ticketID = ticketID
        _controller = StateObject(wrappedValue: .init(model: model, ticketID: ticketID))
    }
    var body: some View {
        let ownsHost = controller.matchesHost(model: model, ticketID: ticketID)
        let capture = ownsHost ? controller.capture() : nil
        let original = controller.presentation
        Group {
            if ownsHost, let ticket = controller.ticket { ProjectTicketMeetingPointSummary(ticket: ticket) }
            Button("projectTicketMeetingPoint.edit") {
                guard ownsHost else { return }; controller.open(capture)
            }.disabled(capture == nil).accessibilityIdentifier("projectTicketMeetingPoint.edit")
        }
        .sheet(item: controller.binding(original)) { value in
            ProjectTicketMeetingPointSheet(controller: controller, original: value)
        }
        .onDisappear { controller.retire() }
    }
}

@MainActor private struct ProjectTicketMeetingPointSheet: View {
    @ObservedObject var controller: ProjectTicketMeetingPointController
    @ObservedObject private var model: ProjectEditModel
    let original: ProjectTicketMeetingPointController.Presentation
    @State private var candidate: ProjectTicketMeetingPoint
    init(controller: ProjectTicketMeetingPointController, original: ProjectTicketMeetingPointController.Presentation) {
        self.controller = controller; self.original = original; model = controller.model
        _candidate = State(initialValue: original.initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                if controller.isCurrent(original) {
                    Section {
                        TextField("projectEdit.meetingPoint", text: $candidate.name)
                            .accessibilityIdentifier("projectEdit.meetingPoint")
                        TextField("projectTicketMeetingPoint.address", text: $candidate.address, axis: .vertical)
                            .accessibilityIdentifier("projectTicketMeetingPoint.address")
                    }
                    Section("projectTicketMeetingPoint.coordinates") {
                        TextField("projectEdit.longitude", text: $candidate.longitude).keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("projectTicketMeetingPoint.longitude")
                        TextField("projectEdit.latitude", text: $candidate.latitude).keyboardType(.numbersAndPunctuation)
                            .accessibilityIdentifier("projectTicketMeetingPoint.latitude")
                        Text("projectTicketMeetingPoint.datum").font(.footnote).foregroundStyle(.secondary)
                        if !candidate.hasValidCoordinates { Text("projectTicketMeetingPoint.invalidCoordinates") }
                    }
                    Section { Text("projectTicketMeetingPoint.workingDraft").font(.footnote).foregroundStyle(.secondary) }
                } else { Text("projectStarter.stale") }
            }
            .appNavigationTitle("projectTicketMeetingPoint.title").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { controller.close(original) }
                        .accessibilityIdentifier("projectTicketMeetingPoint.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("projectTicketMeetingPoint.apply") { controller.apply(candidate, to: original) }
                        .disabled(!controller.isCurrent(original) || !candidate.canApply)
                        .accessibilityIdentifier("projectTicketMeetingPoint.apply")
                }
            }
        }.onDisappear { controller.close(original) }
    }
}

/// Both the editor and immutable confirmation use the same source-aware projection.
struct ProjectTicketMeetingPointSummary: View {
    let ticket: ProjectEditTicket
    var body: some View {
        let value = ProjectTicketMeetingPoint(ticket: ticket)
        Group {
            LabeledContent("projectEdit.meetingPoint", value: value.name)
            LabeledContent("projectTicketMeetingPoint.address", value: value.address)
            if !value.longitude.isEmpty || !value.latitude.isEmpty {
                LabeledContent("projectEdit.longitude", value: value.longitude)
                LabeledContent("projectEdit.latitude", value: value.latitude)
                Text("projectTicketMeetingPoint.datum").font(.footnote).foregroundStyle(.secondary)
            }
            if !ProjectTicketMeetingPoint.supportsEditing(ticket) { Text("projectTicketMeetingPoint.unsupported").font(.footnote) }
            else if !value.hasValidCoordinates { Text("projectTicketMeetingPoint.invalidCoordinates").font(.footnote) }
        }.accessibilityIdentifier("projectTicketMeetingPoint.summary")
    }
}
