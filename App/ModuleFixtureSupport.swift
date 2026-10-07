#if DEBUG
import SwiftUI

enum ModuleFixture: String {
    case playDirector, playPrefab, playPrefabBoot
    case ownedOrderHistory
    case signedInContentDetail
    case publicTemplateDetail, publicPlayTemplate
    case privateHome
    case nativeEnrollment
    case nativePlatform
    case playBranchHistory
    case playExperience, compareGame
    case journeyContent
    case squareWorkspace = "square-workspace"
    case objectCards
    case socialAccount
    case searchMap
    case teams
    case settingsNative
    case presentationPatterns
    case homeFeed = "home-feed"
    case ticketWallet, square, cooperation, accountCollections, creatorContent, growthCenter, officialEvents, projectEdit
    case discovery, profile, messaging, roam, participants, play, composer, topic, localization
    static var selected: Self? {
        let args=ProcessInfo.processInfo.arguments
        guard let i=args.firstIndex(of:"--uitesting-module"),args.indices.contains(i+1) else { return nil }
        return Self(rawValue:args[i+1])
    }
}

@MainActor
struct ModuleFixtureRootView: View {
    let module: ModuleFixture
    @State private var discovery=DiscoveryFixtureReader()
    @State private var roam=RoamFixtureReader()
    var body: some View {
        VStack(spacing:0) {
            // Keep fixture chrome compact while the actual content retains accessibility5.
            Group {
                if ProcessInfo.processInfo.arguments.contains("--uitesting-max-text") {
                    Label("activity.fixtureNotice", systemImage: "testtube.2").labelStyle(.iconOnly)
                } else { Text("activity.fixtureNotice") }
            }.font(.caption.bold()).padding(8)
                .frame(maxWidth:.infinity).background(.yellow.opacity(0.2))
                .accessibilityIdentifier("module.fixture.notice")
                .modifier(AccessibilityFixtureEnvironmentValue())
            switch module {
            case .playDirector: PlayDirectorPrefabFixtureHostView(scenario: "director")
            case .playPrefab: PlayDirectorPrefabFixtureHostView(scenario: "prefab")
            case .playPrefabBoot: PlayDirectorPrefabFixtureHostView(scenario: "prefabBoot")
            case .ownedOrderHistory: OwnedOrderFixtureHost()
            case .signedInContentDetail: SignedInContentDetailFixtureHost()
            case .publicTemplateDetail: PublicTemplateDetailFixtureHost()
            case .publicPlayTemplate: PublicPlayTemplateFixtureHost()
            case .privateHome: PrivateHomeFixtureHost()
            case .nativeEnrollment: NativeEnrollmentFixtureHost()
            case .nativePlatform: NativePlatformFixtureHost()
            case .playBranchHistory: PlayBranchHistoryFixtureHost()
            case .playExperience: PlayExperienceFixtureHostView()
            case .compareGame: PlayCompareFixtureHost()
            case .journeyContent: JourneyContentFixtureHostView()
            case .squareWorkspace: SquareWorkspaceFixtureHost()
            case .objectCards: ObjectCardFixtureHostView()
            case .socialAccount: SocialAccountFixtureHostView()
            case .searchMap: SearchMapFixtureHostView()
            case .teams: TeamFixtureHostView()
            case .settingsNative: SettingsFixtureHostView()
            case .presentationPatterns: NativePresentationFixtureHost()
            case .homeFeed: HomeFeedFixtureHostView()
            case .ticketWallet: TicketWalletFixtureHostView()
            case .square: SquareFixtureHostView()
            case .officialEvents: OfficialFixtureHostView()
            case .projectEdit:
                if ProcessInfo.processInfo.arguments.contains("--project-owned-flow") { ProjectOwnedContentFixtureHost() }
                else { ProjectEditFixtureHostView() }
            case .growthCenter: GrowthCenterFixtureHostView()
            case .creatorContent: CreatorContentFixtureHostView()
            case .accountCollections: AccountCollectionFixtureHostView()
            case .cooperation: CooperationFixtureHostView()
            case .discovery: DiscoveryHomeView(reader:discovery)
            case .profile: ProfileFixtureHostView()
            case .messaging: MessagingFixtureHostView()
            case .roam: RoamBrowserView(reader:roam)
            case .participants: ParticipantFixtureHostView()
            case .play: PlayFixtureHostView()
            case .composer: MessageActionFixtureHost()
            case .topic: TopicFixtureHostView()
            case .localization: ComputedLocalizationFixtureView()
            }
        }
        .modifier(AccessibilityFixtureOptions())
    }
}
#endif
