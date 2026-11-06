import SwiftUI

/// Injection point for a real CLUB/TEAM/HANGOUT source screen. No global space inventory
/// endpoint exists in the supplied backend; a legacy IM projection cannot supply this scope.
@MainActor struct NativeChannelManagementEntry: View {
    let scope: NativeChannelManagementScope
    let makeFlow: (NativeChannelManagementScope) -> NativeChannelManagementCoordinator?
    var destinations = NativeChannelManagementDestinations()
    /// The space's display name from the source screen, shown as the channel home's header.
    var spaceName: String? = nil
    @StateObject private var directoryRoute = NativeChannelManagementRouteState()
    var body: some View {
        let visit = directoryRoute.binding
        NavigationLink(isActive: visit) {
            NativeChannelManagementLaunchView(scope: scope, makeFlow: makeFlow, destinations: destinations, routeIsPresented: visit, spaceName: spaceName)
                .id(directoryRoute.visitID)
        } label: {
            Label { Text("directory", tableName: "NativeChannelManagement") } icon: { Image(systemName: "number.square") }
        }.accessibilityIdentifier("ncm.normalEntry")
    }
}

@MainActor private struct NativeChannelManagementLaunchView: View {
    let scope: NativeChannelManagementScope
    let makeFlow: (NativeChannelManagementScope) -> NativeChannelManagementCoordinator?
    let destinations: NativeChannelManagementDestinations
    let routeIsPresented: Binding<Bool>
    var spaceName: String? = nil
    @State private var model: NativeChannelManagementCoordinator?
    @State private var attempted = false
    @State private var ownerVisit = UUID()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        let parentVisit = routeIsPresented
        Group {
            if let model {
                NativeChannelManagementDirectoryView(model: model, destinations: destinations, parentRouteIsActive: { [weak model] in parentVisit.wrappedValue && model?.isCurrent == true },
                                                     spaceName: spaceName)
                    .id(ownerVisit)
            } else if attempted {
                ContentUnavailableView {
                    Label { Text("unavailable", tableName: "NativeChannelManagement") } icon: { Image(systemName: "lock.shield") }
                } actions: {
                    Button { reopen() } label: { Text("refresh", tableName: "NativeChannelManagement") }
                        .disabled(scenePhase != .active)
                        .accessibilityIdentifier("ncm.launch.retry")
                }
            }
            else { ProgressView() }
        }
        .nativeChannelFlowPage()
        .task { if !attempted { reopen() } }
        .onChange(of: routeIsPresented.wrappedValue) { _, presented in
            if !presented { model?.retire() }
        }
        .onDisappear { if !routeIsPresented.wrappedValue { model?.retire() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if model?.isCurrent != true { reopen() }
            } else {
                // Retire the old authority; its protected original journal remains intact.
                model?.retire()
            }
        }
    }
    private func reopen() {
        guard routeIsPresented.wrappedValue, scenePhase == .active else { return }
        model?.retire()
        let next = makeFlow(scope)
        model = next?.scope == scope && next?.isCurrent == true ? next : nil
        ownerVisit = UUID()
        attempted = true
    }
}

/// Normal team screens provide only an original aggregate ID. This hook neither
/// creates an approval nor treats joined/leader UI fields as channel permissions.
@MainActor struct NativeTeamChannelManagementHooks {
    let makeFlow: @MainActor (NativeChannelManagementScope) -> NativeChannelManagementCoordinator?
    var destinations = NativeChannelManagementDestinations()
}
private struct NativeTeamChannelManagementHooksKey: EnvironmentKey {
    static let defaultValue: NativeTeamChannelManagementHooks? = nil
}
extension EnvironmentValues {
    var teamChannelManagementHooks: NativeTeamChannelManagementHooks? {
        get { self[NativeTeamChannelManagementHooksKey.self] }
        set { self[NativeTeamChannelManagementHooksKey.self] = newValue }
    }
}

/// P01–03 / C08-2: the original TeamDetail identifies guild_kind=3. Directory,
/// manager inventory, metadata CAS and permission CAS remain the existing owners.
@MainActor struct NativeChannelManagementTeamEntry: View {
    var destinations = NativeChannelManagementDestinations()
    let detail: TeamDetail
    let makeFlow: @MainActor (NativeChannelManagementScope) -> NativeChannelManagementCoordinator?
    var body: some View {
        if detail.joined == true, detail.team.id > 0,
           let id = try? NativeChannelManagementID(String(detail.team.id)),
           let scope = try? NativeChannelManagementScope(guildKind: 3, guildID: id) {
            NativeChannelManagementEntry(scope: scope, makeFlow: { selected in
                guard selected == scope, let flow = makeFlow(selected), flow.scope == scope else { return nil }
                return flow
            }, destinations: destinations, spaceName: detail.team.title)
            // Only explicitly supplied TEAM-safe adapters. Never turns a team ID into a conversation ID or grants Webhook.
            .accessibilityIdentifier("ncm.team.normalEntry")
        }
    }
}
