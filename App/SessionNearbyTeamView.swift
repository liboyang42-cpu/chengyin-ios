import SwiftUI

/// Existing Team owns /my and detail; this host only passes its already-read owned rows.
@MainActor struct SessionNearbyTeamsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var destination: NearbyTeamDestination?
    @State private var destinationOwner: String?
    @State private var boundOwner: String?
    let context: NearbyQueryContext?
    let joinedTeams: [OwnedTeam]
    let initialTab: Int
    let focusTeamID: NearbyTeamID?
    let onSignIn: (() -> Void)?
    let joinedTeamsStatus: NearbyOwnedTeamsStatus
    let retryJoinedTeams: (() -> Void)?
    init(context: NearbyQueryContext? = nil, joinedTeams: [OwnedTeam] = [], initialTab: Int = 0, focusTeamID: NearbyTeamID? = nil, onSignIn: (() -> Void)? = nil, joinedTeamsStatus: NearbyOwnedTeamsStatus = .loaded, retryJoinedTeams: (() -> Void)? = nil) {
        self.context = context; self.joinedTeams = joinedTeams; self.initialTab = initialTab; self.focusTeamID = focusTeamID; self.onSignIn = onSignIn
        self.joinedTeamsStatus = joinedTeamsStatus; self.retryJoinedTeams = retryJoinedTeams
    }
    var body: some View {
        let renderedOwner = session.teamViewIdentity, renderedSession = session.nearbyTeamSession
        Group {
            if boundOwner == session.teamViewIdentity,
               session.nearbyTeamCoordinator.session == session.nearbyTeamSession {
                NearbyTeamsView(coordinator: session.nearbyTeamCoordinator, context: context, joinedTeams: joinedTeams, initialTab: initialTab, focusTeamID: focusTeamID, onSignIn: onSignIn,
                    joinedTeamsStatus: joinedTeamsStatus, retryJoinedTeams: retryJoinedTeams, discoverySources: discoverySources) {
                        guard destination == nil, boundOwner == renderedOwner,
                              session.teamViewIdentity == renderedOwner, session.nearbyTeamSession == renderedSession,
                              session.nearbyTeamCoordinator.session == renderedSession else { return }
                        destinationOwner = renderedOwner; destination = $0
                    }
                    .id(session.teamViewIdentity)
            } else { ProgressView("team.loading") }
        }
            .task(id: session.teamViewIdentity) {
                guard !Task.isCancelled else { return }
                let owner = session.teamViewIdentity
                session.nearbyTeamCoordinator.bind(session.nearbyTeamSession)
                boundOwner = owner
            }
            .navigationDestination(isPresented: Binding(get: { destination != nil }, set: { if !$0 { destination = nil } })) {
                if let destination, destinationOwner == session.teamViewIdentity { destinationView(destination) }
                else { ContentUnavailableView("nearby.stale", systemImage: "arrow.clockwise") }
            }
            .onChange(of: session.teamViewIdentity) { _, _ in destination = nil; destinationOwner = nil }
    }
    private var discoverySources: NearbyMapDiscoverySources {
        .init(places: session.roamReader, events: session.roamNearbyEventsReader,
            selectManualArea: { query in
                guard query.valid, let point = RoamCoordinate(latitude: query.latitude, longitude: query.longitude) else { return }
                // The already-explicit manual Search action supplies query context only, not GPS/approval.
                if session.roamArea?.coordinate != point { session.roamArea = .init(coordinate: point, label: "") }
            }, destination: { item in
                switch item {
                case .place:
                    return AnyView(RoamItemDetailView(item: item, reader: session.roamReader,
                        mediaScope: session.platformConsumers.scope, makeExternalMaps: session.platformConsumers.mapsFactory,
                        stampDestination: { AnyView(SessionRoamStampCameraView()) },
                        posterDestination: { AnyView(SessionRoamPosterView(node: $0)) },
                        eventDestination: { AnyView(RoamNearbyEventsDetailHost(target: $0, session: session)) },
                        couponWalletDestination: session.makeRoamCouponWalletDestination(reader: session.roamReader)))
                case .event(let event):
                    guard let target = RoamEventDestination(event: event) else { return AnyView(RoamStatusView(issue: .notConfigured)) }
                    return AnyView(NearbyMapEventDetailSheet(content: AnyView(RoamNearbyEventsDetailHost(target: target, session: session))))
                case .route, .player: return AnyView(RoamStatusView(issue: .notConfigured))
                }
            })
    }
    @ViewBuilder private func destinationView(_ destination: NearbyTeamDestination) -> some View {
        switch destination {
        case .team(let id): SessionTeamDetailView(lookup: .id(id.rawValue))
        case .activity(let id): ActivityDetailView(id: id, reader: session, playReaderForActivity: { session.playReader(for: .activity($0)) }, registrationEnabled: true)
        case .topic(let id): SessionTopicDetailView(id: id, session: session)
        }
    }
}
