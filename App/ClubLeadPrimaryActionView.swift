import SwiftUI

/// A destination is supplied only by an existing, club-bound composition root.
@MainActor struct ClubLeadPrimaryDestinations {
    var isCurrent: (ClubLeadProgressContext) -> Bool = { _ in false }
    var destination: ((ClubLeadPrimaryAction, ClubLeadProgressContext) -> AnyView?)? = nil
}

@MainActor final class ClubLeadPrimaryActionController: ObservableObject {
    struct Route: Identifiable, Equatable {
        let id = UUID()
        let context: ClubLeadProgressContext
        let action: ClubLeadPrimaryAction
    }
    struct Permit: Equatable { let context: ClubLeadProgressContext; let generation: UUID }
    enum Notice: String { case changed, unavailable }
    @Published private(set) var route: Route?
    @Published private(set) var preparing = false
    @Published private(set) var notice: Notice?
    private var context: ClubLeadProgressContext?
    private var active = false
    private var generation = UUID()

    func activate(_ context: ClubLeadProgressContext) {
        guard self.context != context || !active else { return }
        invalidate(); self.context = context; active = context.canRead
    }
    func invalidate() {
        generation = UUID(); active = false; route = nil; preparing = false; notice = nil
    }
    func dismiss() {
        generation = UUID(); route = nil; preparing = false; notice = nil
    }
    func accepts(_ route: Route) -> Bool {
        active && self.route == route && context == route.context
    }
    func permit(in context: ClubLeadProgressContext) -> Permit? {
        guard active, self.context == context, context.canRead, !preparing, route == nil else { return nil }
        return .init(context: context, generation: generation)
    }
    func prepare(_ permit: Permit, displayed stage: ClubLeadProgressStage, context: ClubLeadProgressContext,
                 isCurrent: () -> Bool, refresh: () async -> ClubLeadProgressSnapshot?) async {
        guard active, self.context == context, permit.context == context, permit.generation == generation, context.canRead, !preparing, route == nil,
              let action = ClubLeadPrimaryAction(stage: stage), isCurrent(), !Task.isCancelled else { return }
        generation = UUID(); let request = generation
        preparing = true; notice = nil
        defer { if generation == request { preparing = false } }
        let fresh = await refresh()
        guard active, self.context == context, generation == request, isCurrent(), !Task.isCancelled else { return }
        guard let fresh else { notice = .unavailable; return }
        guard fresh.stage == stage, ClubLeadPrimaryAction(stage: fresh.stage) == action else { notice = .changed; return }
        route = Route(context: context, action: action)
    }
}

/// Kept mounted while the parent clears its snapshot for the fresh read.
@MainActor struct ClubLeadPrimaryActionSection: View {
    let context: ClubLeadProgressContext
    let snapshot: ClubLeadProgressSnapshot?
    let destinations: ClubLeadPrimaryDestinations
    let isCurrent: () -> Bool
    let refresh: () async -> ClubLeadProgressSnapshot?
    let onReturn: () -> Void
    @StateObject private var controller = ClubLeadPrimaryActionController()
    @Environment(\.scenePhase) private var scenePhase
    private var current: Bool { scenePhase == .active && isCurrent() && destinations.isCurrent(context) }
    var body: some View {
        Section {
            if let snapshot, let action = ClubLeadPrimaryAction(stage: snapshot.stage) {
                Button(LocalizedStringKey(action.titleKey)) {
                    guard let permit = controller.permit(in: context) else { return }
                    let displayed = snapshot.stage
                    Task { await controller.prepare(permit, displayed: displayed, context: context,
                        isCurrent: { current }, refresh: refresh) }
                }.disabled(controller.preparing || controller.route != nil || !current || destinations.destination == nil)
                    .accessibilityIdentifier("club.leadPrimary.open")
            }
            if controller.preparing { ProgressView("club.leadPrimary.checking") }
            if let notice = controller.notice { Text(LocalizedStringKey("club.leadPrimary." + notice.rawValue)).accessibilityIdentifier("club.leadPrimary.notice") }
        }
        .task(id: context) { if scenePhase == .active { controller.activate(context) } }
        .onChange(of: context) { _, _ in controller.invalidate(); if scenePhase == .active { controller.activate(context) } }
        .onChange(of: current) { _, valid in if !valid { controller.invalidate() } else { controller.activate(context) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.activate(context); onReturn() } else { controller.invalidate() }
        }
        .onDisappear { controller.invalidate() }
        .sheet(item: Binding(get: { controller.route }, set: { if $0 == nil { controller.dismiss() } }), onDismiss: {
            controller.dismiss()
            if current { onReturn() }
        }) { route in
            NavigationStack {
                Group {
                    if current, controller.accepts(route), let destination = destinations.destination?(route.action, route.context) {
                        destination
                    } else { Color.clear }
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("club.gov.close") { controller.dismiss() } } }
                .onChange(of: current, initial: true) { _, valid in if !valid { controller.invalidate() } }
            }
        }
    }
}

@MainActor extension AppSession {
    func clubLeadPrimaryDestinations(club: ClubRecord, governance: ClubGovernanceContext) -> ClubLeadPrimaryDestinations {
        let valid: (ClubLeadProgressContext) -> Bool = { [weak self] context in
            guard let self else { return false }
            let live = self.clubGovernanceContext
            return context.feedback.clubID == club.id && club.isOwner && !live.access.allowsOfflineWrites &&
                governance.viewerRevision == live.viewerRevision &&
                context.matches(clubReader: self, reader: self.cooperationFlowReader,
                                access: live.access, projects: self.creatorContentReader)
        }
        return .init(isCurrent: valid, destination: { [weak self] action, context in
            guard let self, valid(context) else { return nil }
            switch action {
            case .publish:
                return AnyView(SessionClubProjectLaunchView(session: self, club: club))
            case .merchants:
                return AnyView(SessionClubMerchantProfileHost(session: self) {
                    List { ClubMerchantDiscoveryView(club: club, clubReader: self, reader: self.cooperationFlowReader) }
                        .navigationTitle("club.merchantDiscovery.title")
                })
            case .sentInvitations:
                return AnyView(ClubInvitationFeedbackView(club: club, clubReader: self,
                    reader: self.cooperationFlowReader, access: governance.access, initialDirection: .sent))
            case .topics, .events:
                return AnyView(ClubGovernanceReadView(operation: action == .events ? .eventTopics : .topics,
                    scope: .init(clubID: club.id), identity: self.clubIdentity, access: governance.access, coordinator: governance.coordinator)
                    .environment(\.clubEnrollmentProfile, governance.enrollmentProfile)
                    .environment(\.clubOwnerRefundCoordinator, governance.ownerRefund)
                    .environment(\.clubOpsTimeFactory, governance.opsTimeFactory)
                    .environment(\.clubCustomerTopics, governance.customerTopics)
                    .environment(\.clubStoryTemplates, governance.storyTemplates))
            }
        })
    }
}
