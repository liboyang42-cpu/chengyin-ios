import SwiftUI

@MainActor struct AccountView: View {
    let account: Account
    var privateHomeCoordinator: PrivateHomeCoordinator? = nil
    var onOpenGuideDestination: ((SocialGuideDestination) -> Void)? = nil
    @EnvironmentObject private var session: AppSession
    @State private var savedTopicOwner = ProfileFavoriteTopicNavigationOwner()
    @State private var savedPostOwner = ProfileFavoriteNavigationOwner()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSettings=false
    @State private var settingsGuideHandoff = SettingsGuideHandoff()
    @State private var showsTickets=false
    @State private var showsCooperation=false
    @State private var confirmsLogout=false
    @State private var showsMerchantApplication=false
    private var localCoverOwner: ProfileLocalCoverOwner? {
        ProfileLocalCoverOwner.make(accountID: account.id, configuration: session.regionalConfiguration)
    }
    private var roleLabel: LocalizedStringKey {
        switch account.effectiveRole {
        case "merchant": return "account.role.merchant"
        case "player": return "account.role.player"
        case "club": return "account.role.club"
        default: return "account.role.other"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { SessionDoorInviterView(session: session) } label: { Text("door.inviter.title") }
                        .accessibilityIdentifier("door.inviter.entry")
                }
                Section { PrivateHomeAccountLink(coordinator: privateHomeCoordinator) }
                ProfileLocalCoverSection(owner: localCoverOwner, reader: session.socialAccountReader)
                Section("account.details") {
                    LabeledContent("account.name",value:account.nickname)
                    LabeledContent("account.id",value:String(account.id))
                    LabeledContent("account.role") { Text(roleLabel) }
                    NavigationLink { ProfileEditView(coordinator:session.profileEditCoordinator,sessionRevision:session.contentDetailRevision,categoryReader:session) } label: {
                        Label("profile.edit.title",systemImage:"pencil")
                    }.accessibilityIdentifier("account.editProfile")
                }
                Section {
                    NavigationLink { ProfilePublicInfoHost(reader: session.makeProfilePublicInfoReader(memberID: account.id)) { profileReader in
                        SocialPublicProfileView(memberID: account.id, reader: profileReader, squareReader: session.squareReader, actions: session.socialActionCoordinator, selfOrdersAccess: .init(session: session), selfProjectsAccess: .init(session: session), selfGrowthAccess: .init(reader: session.growthCenterReader, owner: session.socialAccountReader.identity), weeklyPointsAccess: .init(reader: session.profileWeeklyPointsReader, owner: session.socialAccountReader.identity), selfMedalsReader: session.profileReader, selfEditAccess: .init(coordinator: session.profileEditCoordinator, sessionRevision: session.contentDetailRevision, categoryReader: session), localCoverOwner: localCoverOwner, isCurrent: { profileReader.isCurrent })
                    }.id(session.socialAccountReader.identity) } label: {
                        Label("social.profile", systemImage: "person.crop.rectangle")
                    }.accessibilityIdentifier("account.publicProfile")
                    NavigationLink { SocialInviteHistoryView(reader: session.profileInviteHistoryReader, squareReader: session.squareReader, actions: session.socialActionCoordinator).id(session.profileInviteHistoryReader.identity) } label: {
                        Label("social.invites.title", systemImage: "person.2.badge.plus")
                    }.accessibilityIdentifier("account.inviteHistory")
                    NavigationLink { ProfileGuideHost(reader: session.makeProfileGuideReader(), makeArticleReader: { session.makeProfileGuideArticleReader($0) }, onOpenDestination: onOpenGuideDestination, templateReader: session).id(session.socialAccountReader.identity) } label: {
                        Label("social.guide.title", systemImage: "book")
                    }.accessibilityIdentifier("account.playGuide")
                }
                Section {
                    Button { showsTickets=true } label: { Label("ticketWallet.title",systemImage:"ticket") }
                        .accessibilityIdentifier("account.ticketWallet")
                    NavigationLink { SessionTeamHomeView() } label: { Label("team.title", systemImage: "person.3") }
                        .accessibilityIdentifier("account.teams")
                }
                Section {
                    WorkshopOwnedAccountLink(browser: session.workshopOwnedBrowser)
                    WorkshopPurchasedAccountLink(browser: session.workshopPurchasedBrowser, makeInstall: { session.makeWorkshopPaidInstallController(item: $0) }, makeText: { session.makeWorkshopPaidInstalledTextController(reference: $0) }, makeProfessional: { session.makeWorkshopPaidProfessionalController(reference: $0) })
                        .environment(\.workshopGeneratedTemplateReaderFactory, { session.makeOwnedMemberTemplateReader() })
                    OwnerDraftAccountLink(browser: session.ownerDraftBrowser)
                    NavigationLink {
                        SessionCreatorProjectsView(session: session)
                    } label: { Label("creatorContent.projects",systemImage:"square.stack") }
                    .accessibilityIdentifier("account.creatorProjects")
                    NavigationLink { ProjectEditLaunchView().id(session.sessionRevision) } label: {
                        Label("projectEdit.title", systemImage: "square.and.pencil")
                    }.accessibilityIdentifier("account.projectEditor")
                    NavigationLink { TemplateAuthoringLaunchView().id(session.templateAuthoringViewIdentity) } label: {
                        Label("templateAuthor.title", systemImage: "square.and.pencil")
                    }.accessibilityIdentifier("account.templateAuthoring")
                    NavigationLink { CreatorContentCenterView(reader:session.creatorContentReader, publisherContext: session.publisherLifecycleContext).id(session.creatorContentReader.scope) } label: {
                        Label("creatorContent.center",systemImage:"pencil.and.outline")
                    }.accessibilityIdentifier("account.creatorCenter")
                }
                Section {
                    NavigationLink { GrowthCenterView(reader:session.growthCenterReader).id(session.growthCenterReader.scope)
                            .environment(\.growthExploreHomeAction, onOpenGuideDestination.map { open in { open(.home) } })
                    } label: {
                        Label("growth.title",systemImage:"chart.bar.xaxis")
                    }.accessibilityIdentifier("account.growthCenter")
                }
                Section {
                    NavigationLink { SessionWalletCommerceView().id(session.walletCommerceScope) } label: {
                        Label("wallet.title", systemImage: "wallet.pass")
                    }.accessibilityIdentifier("account.wallet")
                }
                AccountCollectionAccountLinks(reader:session.accountCollectionReader,onOpenTopic:{
                    guard let selected = session.profileFavoritesReader.selectTopic($0, renderedScope: session.profileFavoritesReader.scope) else { return }
                    _ = savedTopicOwner.open(selected, scope: session.profileFavoritesReader.scope)
                },rewards:session.nonCashRewardReader,onOpenPost:{
                    guard let selected = session.profileFavoritesReader.selectPost($0, renderedScope: session.profileFavoritesReader.scope) else { return }
                    _ = savedPostOwner.open(selected, scope: session.profileFavoritesReader.scope)
                }, favoriteRemoval: session.makeProfileFavoriteRemovalController(scope: session.profileFavoritesReader.scope), couponReader: session.profileOwnedCouponReader, favoritesReader: session.profileFavoritesReader).id(session.accountCollectionReader.scope)
                Section {
                    NavigationLink { SessionObjectCardsView() } label: {
                        Label("objects.title", systemImage: "rectangle.stack")
                    }.accessibilityIdentifier("account.objectCards")
                }
                Section { ProfileComplaintPreparationLink(session: session) }
                PlayerJourneyAccountLinks()
                ProfileAccountLinks(reader:session.profileReader,ordersDestination:{ AnyView(SessionOwnedOrdersView(session: session)) },participantCoordinator:session.participantCoordinator,orderLifecycleCoordinator:session.orderLifecycleCoordinator, mediaScope:session.platformConsumers.scope, makeExternalMaps:session.platformConsumers.mapsFactory)
                Section {
                    NavigationLink { MessagingHomeView(reader:session.messagingReader,mediaReader:session.socialMessageMediaReader,senderForConversation:{ session.messageSender(for:$0) },expanded:session.imExpandedNavigation,squareDestination:{ close in AnyView(SessionSquareBrowserView(session: session, onClose: close, onSignIn: close)) }).id(session.messagingViewIdentity) } label: {
                        Label("messaging.title",systemImage:"bubble.left.and.bubble.right")
                    }.accessibilityIdentifier("account.messages")
                    NavigationLink { ClubHomeView(reader:session,actionCoordinator:session.clubActionCoordinator,management:session.clubManagementContext, community:session.clubCommunityContext, topicDestination: { AnyView(SessionTopicDetailView(id: $0, session: session)) }).id(session.sessionRevision) } label: { Label("club.title",systemImage:"person.3") }
                        .accessibilityIdentifier("account.clubs")
                }
                Section {
                    Button { showsCooperation=true } label: { Label("cooperation.title",systemImage:"person.2") }
                        .accessibilityIdentifier("account.cooperation")
                    NavigationLink { MerchantHomeView(reader:session,marketingModel:session.merchantMarketingCoordinator,marketingDestination:{ AnyView(SessionMerchantMarketingDestination(session:session,destination:$0)) },openApplication:{ showsMerchantApplication=true },operationsReader:session.merchantOperationsReader,operationsDestinationFactory:{ session.merchantOperationsDestination($0, access: $1) },businessReader:session.merchantBusinessReader,businessJournal:session.merchantBusinessJournal,contentService:session.merchantContentService,cooperationFlowReader:session.cooperationFlowReader,engagementReader:session.merchantEngagementReader,exportRecovery:session.merchantExportRecovery) } label: {
                        Label("merchant.title",systemImage:"storefront")
                    }.accessibilityIdentifier("account.merchant")
                    Button { showsMerchantApplication=true } label: {
                        Label("merchant.onboarding.openApplication",systemImage:"doc.text")
                    }.accessibilityIdentifier("account.merchantApplication")
                }
                Section {
                    Button("auth.signOut",role:.destructive) { confirmsLogout=true }
                }
            }
            .appNavigationTitle("account.title")
            .environment(\.nativeVerificationDestination, { AnyView(SessionNativeVerificationView()) })
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("settings.title",systemImage:"gearshape") {
                        if settingsGuideHandoff.begin() { showsSettings=true }
                    }
                }
            }
            .navigationDestination(isPresented:$showsMerchantApplication) {
                MerchantOnboardingView(session:session,coordinator:session.merchantOnboardingCoordinator)
            }
            .background {
                ProfileFavoriteTopicNavigationLayer(owner: savedTopicOwner) { selected in
                    ProfileFavoriteTopicDestination(selection: selected, session: session,
                        makeReader: { session.makeProfileFavoriteTopicReader(selected) }).id(selected.id)
                }
                ProfileFavoriteNavigationLayer(owner: savedPostOwner) { selected in
                    ProfileFavoriteDetailDestination(selection: selected,
                        makeReader: { session.makeProfileFavoriteDetailReader(selected) },
                        accountReader: session.socialAccountReader, actions: session.socialActionCoordinator)
                        .id(selected.id)
                }
            }
            .onChange(of: session.profileFavoritesReader.scope) { _, scope in
                savedPostOwner.updateScope(scope); savedTopicOwner.updateScope(scope)
            }
            .sheet(isPresented:$showsSettings, onDismiss: settingsDismissHandler) {
                let presentation = settingsGuideHandoff.presentation
                let revision = session.sessionRevision
                SettingsView(onOpenGuideDestination: onOpenGuideDestination.map { open in { destination in
                    guard showsSettings, session.sessionRevision == revision,
                          settingsGuideHandoff.request(presentation, action: {
                              guard session.sessionRevision == revision else { return }
                              open(destination)
                          }) else { return }
                    showsSettings = false
                } })
            }
            .sheet(isPresented:$showsCooperation) { CooperationBrowserView(reader:session.cooperationReader,onClose:{ showsCooperation=false },peerReader:session.cooperationFlowReader).id(session.cooperationReader.scope) }
            .sheet(isPresented:$showsTickets) { TicketWalletView(reader:session.ticketWalletReader,onClose:{ showsTickets=false },makeTeamCoordinator:{ session.makeTeamCoordinator() },orderLifecycleCoordinator:session.orderLifecycleCoordinator).environment(\.ticketWalletPlayProvider, ticketPlayProvider).environment(\.ticketWalletPendingOrderProvider, ticketPendingOrderProvider).id(session.ticketWalletReader.scope) }
            .confirmationDialog("auth.signOutConfirm",isPresented:$confirmsLogout,titleVisibility:.visible) {
                Button("auth.signOut",role:.destructive) { Task { await session.logout() } }
                Button("action.cancel",role:.cancel) {}
            }
        }
        .onAppear { savedPostOwner.appear(scope: session.profileFavoritesReader.scope, foreground: scenePhase == .active); savedTopicOwner.appear(scope: session.profileFavoritesReader.scope, foreground: scenePhase == .active) }
        .onDisappear { savedPostOwner.disappear(); savedTopicOwner.disappear() }
        .onChange(of: scenePhase) { _, phase in savedPostOwner.setForeground(phase == .active); savedTopicOwner.setForeground(phase == .active) }
    }

    private var settingsDismissHandler: () -> Void {
        let presentation = settingsGuideHandoff.presentation
        return { settingsGuideHandoff.finish(presentation)?() }
    }

    @MainActor private var ticketPendingOrderProvider: TicketWalletPendingOrderProvider {
        TicketWalletPendingOrderProvider(reader: session.ticketWalletReader, coordinator: session.orderLifecycleCoordinator,
            revision: session.sessionRevision, currentRevision: { session.sessionRevision })
    }

    @MainActor private var ticketPlayProvider: TicketWalletPlayProvider {
        TicketWalletPlayProvider(reader: session.ticketWalletReader, revision: session.sessionRevision,
            currentRevision: { session.sessionRevision }) { entry in
            AnyView(SessionPlayRuntimeView(session: session, destination: .journey(entry.scope))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            TicketWalletDetailView(id: entry.registrationID, reader: session.ticketWalletReader)
                                .environment(\.ticketWalletPlayProvider, nil)
                                .id(session.ticketWalletReader.scope)
                        } label: { Label("ticketWallet.detail", systemImage: "ticket") }
                        .accessibilityIdentifier("ticketWallet.play.ticket")
                    }
                })
        }
    }
}
