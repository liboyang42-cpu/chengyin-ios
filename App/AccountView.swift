import SwiftUI

struct AccountView: View {
    let account: Account
    var onOpenGuideDestination: ((SocialGuideDestination) -> Void)? = nil
    @EnvironmentObject private var session: AppSession
    private struct SavedTopicRoute: Identifiable, Hashable { let id: Int }
    private enum CreatorRoute: Hashable { case topic(Int), activity(Int), playTemplate(Int) }
    @State private var creatorRoute: CreatorRoute?
    @State private var savedTopic: SavedTopicRoute?
    @State private var showsSettings=false
    @State private var showsTickets=false
    @State private var showsCooperation=false
    @State private var confirmsLogout=false
    @State private var showsMerchantApplication=false
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
                Section("account.details") {
                    LabeledContent("account.name",value:account.nickname)
                    LabeledContent("account.id",value:String(account.id))
                    LabeledContent("account.role") { Text(roleLabel) }
                    NavigationLink { ProfileEditView(coordinator:session.profileEditCoordinator,sessionRevision:session.sessionRevision) } label: {
                        Label("profile.edit.title",systemImage:"pencil")
                    }.accessibilityIdentifier("account.editProfile")
                }
                Section {
                    NavigationLink { SocialPublicProfileView(memberID: account.id, reader: session.socialAccountReader, squareReader: session.squareReader, actions: session.socialActionCoordinator).id(session.socialAccountReader.identity) } label: {
                        Label("social.profile", systemImage: "person.crop.rectangle")
                    }.accessibilityIdentifier("account.publicProfile")
                    NavigationLink { SocialInviteHistoryView(reader: session.socialAccountReader, squareReader: session.squareReader, actions: session.socialActionCoordinator).id(session.socialAccountReader.identity) } label: {
                        Label("social.invites.title", systemImage: "person.2.badge.plus")
                    }.accessibilityIdentifier("account.inviteHistory")
                    NavigationLink { SocialPlayGuideView(reader: session.socialAccountReader, onOpenDestination: onOpenGuideDestination).id(session.socialAccountReader.identity) } label: {
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
                    NavigationLink {
                        CreatorContentProjectsView(reader:session.creatorContentReader,onOpen:{ destination in
                            switch destination {
                            case .topic(let id): creatorRoute = .topic(id)
                            case .activity(let id): creatorRoute = .activity(id)
                            case .playTemplate(let id): creatorRoute = .playTemplate(id)
                            }
                        }).id(session.creatorContentReader.scope)
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
                    NavigationLink { GrowthCenterView(reader:session.growthCenterReader).id(session.growthCenterReader.scope) } label: {
                        Label("growth.title",systemImage:"chart.bar.xaxis")
                    }.accessibilityIdentifier("account.growthCenter")
                }
                Section {
                    NavigationLink { SessionWalletCommerceView().id(session.walletCommerceScope) } label: {
                        Label("wallet.title", systemImage: "wallet.pass")
                    }.accessibilityIdentifier("account.wallet")
                }
                AccountCollectionAccountLinks(reader:session.accountCollectionReader,onOpenTopic:{ savedTopic=SavedTopicRoute(id:$0) }).id(session.accountCollectionReader.scope)
                Section {
                    NavigationLink { SessionObjectCardsView() } label: {
                        Label("objects.title", systemImage: "rectangle.stack")
                    }.accessibilityIdentifier("account.objectCards")
                }
                ProfileAccountLinks(reader:session.profileReader,participantCoordinator:session.participantCoordinator,orderLifecycleCoordinator:session.orderLifecycleCoordinator, mediaScope:session.platformConsumers.scope, makeExternalMaps:session.platformConsumers.mapsFactory)
                Section {
                    NavigationLink { MessagingHomeView(reader:session.messagingReader,mediaReader:session.socialMessageMediaReader,senderForConversation:{ session.messageSender(for:$0) },expanded:session.imExpandedNavigation).id(session.messagingReader.identity) } label: {
                        Label("messaging.title",systemImage:"bubble.left.and.bubble.right")
                    }.accessibilityIdentifier("account.messages")
                    NavigationLink { ClubHomeView(reader:session,actionCoordinator:session.clubActionCoordinator,management:session.clubManagementContext, community:session.clubCommunityContext) } label: { Label("club.title",systemImage:"person.3") }
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
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("settings.title",systemImage:"gearshape") { showsSettings=true }
                }
            }
            .navigationDestination(isPresented:$showsMerchantApplication) {
                MerchantOnboardingView(session:session,coordinator:session.merchantOnboardingCoordinator)
            }
            .navigationDestination(item:$creatorRoute) { route in
                switch route {
                case .topic(let id): SessionTopicDetailView(id: id, session: session).id(session.topicReader.scope)
                case .activity(let id): ActivityDetailView(id:id,reader:session)
                    .toolbar { if let resource = try? PublishedResource(kind: .activity, value: id) { PublisherLifecycleNavigationLink(session: session, resource: resource) } }
                case .playTemplate(let id): DiscoveryTemplateDetailView(id: id, reader: session, authoringFactory: { session.templateAuthoringEditor(adopting: $0) }, authoringRevision: session.sessionRevision).id(session.templateAuthoringViewIdentity)
                }
            }
            .navigationDestination(item:$savedTopic) { route in
                SessionTopicDetailView(id: route.id, session: session).id(session.topicReader.scope)
            }
            .sheet(isPresented:$showsSettings) { SettingsView() }
            .sheet(isPresented:$showsCooperation) { CooperationBrowserView(reader:session.cooperationReader,onClose:{ showsCooperation=false }).id(session.cooperationReader.scope) }
            .sheet(isPresented:$showsTickets) { TicketWalletView(reader:session.ticketWalletReader,onClose:{ showsTickets=false },makeTeamCoordinator:{ session.makeTeamCoordinator() },orderLifecycleCoordinator:session.orderLifecycleCoordinator).id(session.ticketWalletReader.scope) }
            .confirmationDialog("auth.signOutConfirm",isPresented:$confirmsLogout,titleVisibility:.visible) {
                Button("auth.signOut",role:.destructive) { Task { await session.logout() } }
                Button("action.cancel",role:.cancel) {}
            }
        }
    }
}
