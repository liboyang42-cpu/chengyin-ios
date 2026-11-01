import SwiftUI

@MainActor struct SessionHomeFeedView:View {
    @EnvironmentObject private var session:AppSession
    var onSignIn:(()->Void)? = nil
    @State private var path:[HomeFeedDestination]=[]
    @State private var activeContinuationScope:PlaySessionScope?=nil
    @State private var continuationCoordinator = HomeContinuationCoordinator()
    @State private var continuationCards:[HomeIndexParityPresentation.ContinuationCard]=[]
    @State private var continuationReadAvailability:HomeContinuationReadAvailability = .unauthenticated
    @State private var showsGlobalSearch=false
    @State private var showsTemplates=false
    @State private var showsSquare=false
    @State private var showsOfficialEvents=false
    @State private var showsProjectEditor=false
    @State private var showsClubApplication=false
    @State private var showsMerchantApplication=false
    var body:some View {
        navigationRoot
        .id(session.homeFeedReader.scope)
        .task(id:session.playerJourneyReader.scope) { await reloadContinuationCards() }
        .onChange(of:session.homeFeedReader.scope) { _,_ in resetForHomeScopeChange() }
        .onChange(of:session.officialEventReader.scope) { _,_ in showsOfficialEvents=false }
        .onChange(of:session.sessionRevision) { _,_ in resetForSessionRevisionChange() }
        .sheet(isPresented:$showsGlobalSearch) {
            NavigationStack {
                SessionGlobalSearchView(onSignIn:{ showsGlobalSearch=false;onSignIn?() })
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button("action.close") { showsGlobalSearch=false } } }
            }.id(session.searchMapReader.scope)
        }
        .sheet(isPresented:$showsProjectEditor) {
            NavigationStack {
                ProjectEditLaunchView().toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("action.close") { showsProjectEditor=false } }
                }
            }.id(session.sessionRevision)
        }
        .sheet(isPresented:$showsOfficialEvents) {
            OfficialEventsBrowserView(reader:session.officialEventReader,actions:session.officialActionCoordinator,onClose:{ showsOfficialEvents=false },onLogin:{
                showsOfficialEvents=false
                onSignIn?()
            },topicLinks:OfficialTopicLinks(reader:session.topicReader,destination:{ AnyView(SessionTopicDetailView(id:$0,session:session)) })).id(session.officialEventReader.scope)
        }
        .sheet(isPresented:$showsSquare) { SessionSquareBrowserView(session: session, onClose: { showsSquare = false }, onSignIn: { showsSquare = false; onSignIn?() }).id(session.squareReader.scope) }
        .sheet(isPresented:$showsTemplates) {
            NavigationStack {
                DiscoveryTemplateBrowserView(reader: session, authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision, authoringCompletion: session.templateAuthoringCompletionContext).id(session.templateAuthoringViewIdentity)
                    .toolbar {
                        ToolbarItem(placement:.cancellationAction) {
                            Button("action.close") { showsTemplates=false }
                        }
                    }
            }
        }
    }
    private var navigationRoot: some View {
        NavigationStack(path:$path) {
            // Unzoned content needs a separately verified event/backend timezone.
            // Market and interface language alone do not establish one.
            HomeFeedView(
                reader:session.homeFeedReader,
                unavailableMessageKey: session.homeReadAvailability.messageKey,
                viewerNickname: session.account?.nickname,
                selectedCity: session.roamArea?.label,
                showsHeroBanners: true,
                continuationCards: continuationCards,
                continuationReadAvailability: continuationReadAvailability,
                onActionBanner: handleActionBanner,
                onContinuation: handleContinuation,
                onRetryContinuation: { Task { await reloadContinuationCards() } }
            ) { path.append($0) }
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("square.title",systemImage:"square.grid.2x2") { showsSquare=true }
                            .accessibilityIdentifier("homeFeed.openSquare")
                    }
                    ToolbarItemGroup(placement:.topBarTrailing) {
                        Button("searchMap.title",systemImage:"magnifyingglass") { showsGlobalSearch=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openGlobalSearch")
                        Button("projectEdit.title", systemImage:"square.and.pencil") { showsProjectEditor=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openProjectEditor")
                        Button("official.title",systemImage:"sparkles") { showsOfficialEvents=true }
                            .labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                            .accessibilityIdentifier("homeFeed.openOfficialEvents")
                        Button("discovery.browseTemplates",systemImage:"square.stack.3d.up") { showsTemplates=true }
                            .accessibilityIdentifier("homeFeed.openTemplates")
                    }
                }
                .navigationDestination(for:HomeFeedDestination.self) { destination in
                    switch destination {
                    case .activity(let id): ActivityDetailView(id:id,reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true)
                    case .topic(let id): SessionTopicDetailView(id: id, session: session)
                    }
                }
                .navigationDestination(item:$activeContinuationScope) { scope in
                    continuationDestination(scope)
                }
        }
        .onChange(of:activeContinuationScope) { _,next in if next == nil { Task { await reloadContinuationCards() } } }
        .onChange(of:path) { _,next in if next.isEmpty { Task { await reloadContinuationCards() } } }
        .sheet(isPresented:$showsClubApplication) { clubApplicationSheet }
        .sheet(isPresented:$showsMerchantApplication) { merchantApplicationSheet }
    }
    @ViewBuilder private func continuationDestination(_ scope: PlaySessionScope) -> some View {
        if session.playExperience(for: scope) != nil {
            SessionPlayRuntimeView(session: session, destination: .journey(scope))
                .environment(\.playThemeAuxiliaryProvider, session.playThemeAuxiliaryProvider)
        } else {
            switch scope {
            case .activity(let id): ActivityDetailView(id:id,reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true)
            case .topic(let id): SessionTopicDetailView(id: id, session: session)
            }
        }
    }
    private var clubApplicationSheet: some View {
        NavigationStack {
            ClubHomeView(
                reader: session,
                onSignIn: { showsClubApplication = false; onSignIn?() },
                actionCoordinator: session.clubActionCoordinator,
                management: session.clubManagementContext,
                community: session.clubCommunityContext,
                topicDestination: { AnyView(SessionTopicDetailView(id: $0, session: session)) }
            )
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("action.close") { showsClubApplication = false }
                }
            }
        }.id(session.sessionRevision)
    }
    private var merchantApplicationSheet: some View {
        NavigationStack {
            MerchantOnboardingView(
                session: session,
                coordinator: session.merchantOnboardingCoordinator
            )
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button("action.close") { showsMerchantApplication = false }
                }
            }
        }.id(session.sessionRevision)
    }
    private func resetForHomeScopeChange() {
        path=[]
        activeContinuationScope=nil
        continuationCoordinator.reset()
        continuationCards=[]
        continuationReadAvailability = .unauthenticated
        showsGlobalSearch=false
        showsTemplates=false
        showsSquare=false
        showsOfficialEvents=false
        showsProjectEditor=false
        showsClubApplication=false
        showsMerchantApplication=false
    }
    private func resetForSessionRevisionChange() {
        activeContinuationScope=nil
        continuationCoordinator.reset()
        continuationCards=[]
        continuationReadAvailability = .unauthenticated
        showsProjectEditor=false
        showsClubApplication=false
        showsMerchantApplication=false
    }
    private func handleActionBanner(_ banner: HomeIndexParityPresentation.ActionBanner) {
        switch banner.id {
        case "club_apply":
            if session.account == nil { onSignIn?() } else { showsClubApplication = true }
        case "merchant_apply":
            if session.account == nil { onSignIn?() } else { showsMerchantApplication = true }
        default:
            break
        }
    }
    private func handleContinuation(_ card: HomeIndexParityPresentation.ContinuationCard) {
        Task {
            let decision = await continuationCoordinator.verifyNavigation(
                for: card,
                currentOwnerScope: { session.currentHomeContinuationOwnerScope },
                canEnterRuntime: { session.playExperience(for: $0) != nil },
                hasDurableOrLivePause: { await session.hasResumablePlayState(for: $0) }
            )
            continuationCards = continuationCoordinator.cards
            continuationReadAvailability = continuationCoordinator.readAvailability
            switch decision {
            case .enterRuntime(let scope):
                activeContinuationScope = scope
            case .openDetail(let destination):
                path.append(destination)
            case .staleRejected:
                await reloadContinuationCards()
            }
        }
    }
    private func reloadContinuationCards() async {
        let reader = session.playerJourneyReader
        let cards = await continuationCoordinator.reload(
            ownerScope: session.currentHomeContinuationOwnerScope,
            isAuthenticated: session.isSignedIn && session.account != nil && reader.isAuthenticated,
            isJourneyReadConfigured: reader.isConfigured,
            currentOwnerScope: { session.currentHomeContinuationOwnerScope },
            loadParticipations: { try await reader.participations() },
            loadPausedRuns: { records in await session.loadPausedContinueRuns(participations: records) }
        )
        continuationCards = cards
        continuationReadAvailability = continuationCoordinator.readAvailability
    }
}
