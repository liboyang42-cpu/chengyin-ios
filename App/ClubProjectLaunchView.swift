import SwiftUI

@MainActor final class ClubProjectLaunchModel: ObservableObject {
    struct Permit: Equatable { let context: ClubProjectLaunchContext; let visibility: UUID }
    enum Phase: Equatable { case idle, loading, ready, failed, denied, editorUnavailable }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var target: ClubProjectLaunchTarget?
    private var bound: ClubProjectLaunchContext?
    private var visibility: UUID?
    private var generation = UUID()
    func activate(_ context: ClubProjectLaunchContext) -> Permit? {
        guard context.canRead, !Task.isCancelled else { leave(); return nil }
        if bound != context || visibility == nil { bound = context; visibility = UUID(); generation = UUID(); target = nil; phase = .idle }
        return permit(in: context)
    }
    func permit(in context: ClubProjectLaunchContext) -> Permit? {
        guard bound == context, context.canRead, let visibility else { return nil }; return .init(context: context, visibility: visibility)
    }
    func leave() { visibility = nil; generation = UUID(); target = nil; phase = .idle }
    private func accepts(_ p: Permit) -> Bool { bound == p.context && visibility == p.visibility && p.context.canRead }
    func isCurrent(_ value: ClubProjectLaunchTarget, context: ClubProjectLaunchContext, reader: any ClubReading, editorContextID: String) -> Bool {
        target == value && value.context == context && permit(in: context) != nil && context.matches(reader: reader, editorContextID: editorContextID)
    }
    func unavailable(_ value: ClubProjectLaunchTarget) {
        guard target == value else { return }; target = nil; phase = .editorUnavailable
    }
    /// Both initial entry and every mode choice re-read ownership; choosing never sends a project.
    @discardableResult func read(_ p: Permit, product: ProjectEditProduct? = nil, reader: any ClubReading, editorContextID: @escaping () -> String) async -> ClubProjectLaunchTarget? {
        guard accepts(p), p.context.matches(reader: reader, editorContextID: editorContextID()), !Task.isCancelled else { return nil }
        generation = UUID(); let request = generation
        target = nil; phase = .loading
        let current = { [self] in accepts(p) && generation == request && !Task.isCancelled && p.context.matches(reader: reader, editorContextID: editorContextID()) }
        defer { if accepts(p), generation == request, phase == .loading { phase = .idle } }
        do {
            let club = try await reader.clubDetail(id: p.context.clubID, isCurrent: current)
            guard current() else { return nil }
            guard club.id == p.context.clubID, club.isOwner else { phase = .denied; return nil }
            if let product { target = try .init(context: p.context, product: product) }
            phase = .ready; return target
        } catch {
            guard current() else { return nil }; phase = .failed; return nil
        }
    }
}

@MainActor struct ClubProjectEditorPresentation: Identifiable {
    let target: ClubProjectLaunchTarget
    let coordinator: ProjectEditCoordinator
    let session: ProjectEditSession
    var id: UUID { target.id }
    init?(target: ClubProjectLaunchTarget, coordinator: ProjectEditCoordinator) {
        guard let session = coordinator.session, target.matches(projectSession: session) else { return nil }
        self.target = target; self.coordinator = coordinator; self.session = session
    }
    var hasCurrentSession: Bool { coordinator.session == session && target.matches(projectSession: session) }
}

@MainActor struct SessionClubProjectLaunchView: View {
    @ObservedObject var session: AppSession
    let club: ClubRecord
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ClubProjectLaunchModel()
    @State private var presented: ClubProjectEditorPresentation?
    private var context: ClubProjectLaunchContext { .init(club: club, reader: session, editorContextID: session.projectEditorContextID) }
    var body: some View {
        let scope = context
        List {
            Section {
                Text("club.projectLaunch.localHint")
                Text(verbatim: club.name).font(.headline)
                LabeledContent("club.ops.clubID", value: String(club.id))
            }
            if !scope.canRead || model.phase == .denied { Text("club.projectLaunch.ownerRequired") }
            else {
                if model.phase == .loading { ProgressView("club.loading") }
                if model.phase == .failed { Text("club.projectLaunch.failed") }
                if model.phase == .editorUnavailable { Text("club.projectLaunch.editorUnavailable") }
                if model.phase == .ready && model.target == nil {
                    Section("club.projectLaunch.chooseMode") {
                        Button("club.projectLaunch.city") { choose(.city, scope: scope) }.accessibilityIdentifier("club.projectLaunch.city")
                        Button("club.projectLaunch.freeExplore") { choose(.freeExplore, scope: scope) }.accessibilityIdentifier("club.projectLaunch.freeExplore")
                    }
                }
                Button(LocalizedStringKey(model.phase == .failed ? "action.retry" : "club.refresh")) { reload(scope) }
                    .disabled(model.phase == .loading || presented != nil || model.permit(in: scope) == nil)
                    .accessibilityIdentifier("club.projectLaunch.reload")
            }
        }
        .navigationTitle("club.projectLaunch.title")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { model.leave(); dismiss() }.accessibilityIdentifier("club.projectLaunch.cancel") } }
        .task(id: scope) {
            presented = nil
            guard let permit = model.activate(scope) else { return }
            await model.read(permit, reader: session, editorContextID: { session.projectEditorContextID })
        }
        .onChange(of: scope) { _, _ in presented = nil }
        .onDisappear { presented = nil; model.leave() }
        .sheet(item: $presented, onDismiss: { reload(scope) }) { selection in
            NavigationStack {
                Group {
                    if current(selection) {
                        // The existing editor retains all local restore/discard, review and submission gates.
                        ProjectEditView(coordinator: selection.coordinator, sessionRevision: session.sessionRevision, seed: selection.target.seed)
                            .id(selection.id)
                    } else { Color.clear }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { presented = nil } } }
                .onChange(of: current(selection), initial: true) { _, valid in if !valid { presented = nil } }
            }
        }
    }
    private func current(_ selection: ClubProjectEditorPresentation) -> Bool {
        selection.hasCurrentSession && model.isCurrent(selection.target, context: context, reader: session, editorContextID: session.projectEditorContextID)
    }
    private func reload(_ scope: ClubProjectLaunchContext) {
        guard context == scope, scope.matches(reader: session, editorContextID: session.projectEditorContextID), let permit = model.permit(in: scope) else { return }
        Task { await model.read(permit, reader: session, editorContextID: { session.projectEditorContextID }) }
    }
    private func choose(_ product: ProjectEditProduct, scope: ClubProjectLaunchContext) {
        guard presented == nil, model.phase == .ready, model.target == nil, context == scope, let permit = model.permit(in: scope) else { return }
        Task {
            guard let target = await model.read(permit, product: product, reader: session, editorContextID: { session.projectEditorContextID }),
                  presented == nil, model.isCurrent(target, context: context, reader: session, editorContextID: session.projectEditorContextID) else { return }
            let coordinator = session.projectEditor(product: target.seed.product)
            guard let selection = ClubProjectEditorPresentation(target: target, coordinator: coordinator), current(selection) else { model.unavailable(target); return }
            presented = selection
        }
    }
}
