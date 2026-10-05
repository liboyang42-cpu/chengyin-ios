import SwiftUI

/// No tracking provider is approved in the current app. Never simulate successful cleanup.
@MainActor final class DormantComplianceRoamEffects: ComplianceRoamEffects {
    func stopTracking() async throws { throw ComplianceFailure.unavailable }
    func clearMapPrivacy() async throws { throw ComplianceFailure.unavailable }
    func invalidateMapPrivacyCaches() {}
}

@MainActor struct SessionDoorInviterView: View {
    @ObservedObject var session: AppSession
    var body: some View {
        Group {
            if let queue = session.doorReferralQueue {
                DoorInviterSheet(session: session.doorReferralSession, queue: queue, enabled: false)
            } else { Text("door.disabled") }
        }.id(session.sessionRevision)
    }
}

/// Lives outside account-keyed tabs so a guest invitation survives the existing login overlay.
@MainActor struct NativeEntryLandingView: View {
    let entry: NativeEntryPresentation
    @ObservedObject var session: AppSession
    let goHome: () -> Void
    @State private var destination: DoorDestination?
    @State private var failure: String?
    @State private var showsLogin = false
    var body: some View {
        NavigationStack {
            Group {
                switch entry.intent {
                case .routeError(let failure):
                    NativeRouteErrorView(failure: failure, goHome: { session.dismissNativeEntry(); goHome() })
                case .badge(let parameters):
                    ObjectBadgeRoutePreview(parameters: parameters, expectedScope: entry.id, currentScope: { session.nativeEntry?.id ?? UUID() })
                case .teamInvitation(let route):
                    if session.account == nil {
                        VStack(spacing: 16) {
                            Text("nativeNav.team.signInDetail")
                            Button("team.signIn") { showsLogin = true }
                        }.padding()
                    } else {
                        SessionTeamDetailView(lookup: .invitation(route.code)).id(session.teamViewIdentity)
                    }
                case .publicMerchant(let target):
                    PublicMerchantHomeView(target: target, context: session.publicMerchantHomeContext).id(session.sessionRevision)
                case .merchantInvitation(let route):
                    MerchantOperatorInvitationLandingView(invitation: route.invitation,
                        reader: session.merchantEngagementReader, journal: session.merchantBusinessJournal,
                        exportRecovery: session.merchantExportRecovery, requestSignIn: { showsLogin = true })
                        .id(session.sessionRevision)
                case .door:
                    doorDestination
                        .task(id: session.doorReferralSession) {
                            guard session.doorReferralSession.restored else { return }
                            guard let model = session.doorEntryCoordinator else { destination = .home; failure = "door.disabled"; return }
                            // AppSession received this intent once. Never re-capture/refire after account changes.
                            await model.resolve()
                            guard !Task.isCancelled else { return }
                            destination = model.destination; failure = model.failure
                        }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("door.close") { session.dismissNativeEntry() } } }
            .sheet(isPresented: $showsLogin) {
                if case .teamInvitation = entry.intent { LoginView(intent: .player) }
                else { LoginView(intent: .merchant) }
            }
        }
        .onDisappear { session.doorEntryCoordinator?.cancel() }
    }
    @ViewBuilder private var doorDestination: some View {
        switch destination {
        case .activityPlay(let activityID, _):
            SessionPlayRuntimeView(session: session, destination: .journey(.activity(activityID)))
        case .topicSelfPlay(let topicID):
            SessionPlayRuntimeView(session: session, destination: .journey(.topic(topicID)))
        case .topicDetail(let topicID):
            SessionTopicDetailView(id: topicID, session: session)
        case .home:
            VStack(spacing: 16) {
                if let failure {
                    if ["door.disabled", "door.unavailable"].contains(failure) { Text(LocalizedStringKey(failure)) }
                    else { Text(verbatim: failure) }
                }
                Button("homeFeed.title") { session.dismissNativeEntry(); goHome() }
            }.padding()
        case nil: ProgressView("door.resolving")
        }
    }
}


@MainActor struct SessionMerchantMarketingDestination: View {
    @ObservedObject var session: AppSession
    let destination: MerchantInsightDestination
    var body: some View {
        Group {
            switch destination {
            case .topicCooperation: CooperationFlowWorkbench(reader: session.cooperationFlowReader)
            case .decoration: MerchantOperationsDocumentView(reader: session.merchantOperationsReader, destination: .decor, imageHost: session.retainedMerchantImages)
            case .content: ProjectEditView(coordinator: session.projectEditor(product: .city), sessionRevision: session.sessionRevision, publisherClient: session.publisherLifecycleContext?.client, publisherHost: { AnyView(SessionPublisherLifecycleView(session: session, resource: $0)) })
            }
        }.id(session.sessionRevision)
    }
}
