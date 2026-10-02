import SwiftUI

@main
struct QuestifyApp: App {
    @StateObject private var sessionContainer = AppSessionContainer()
    @AppStorage("preferences.language") private var storedLanguage = RegionalLaunchConfiguration.language(nil).rawValue
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset-language") {
            UserDefaults.standard.set(AppLanguage.system.rawValue,forKey:"preferences.language")
        }
        if ProcessInfo.processInfo.arguments.contains("--uitesting-first-launch-language") {
            UserDefaults.standard.removeObject(forKey:"preferences.language")
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--merchant-npc-fixture") {
                    NavigationStack { MerchantNPCFixtureView() }
                } else if ProcessInfo.processInfo.arguments.contains("--publisher-lifecycle-fixture") {
                    PublisherLifecycleFixtureRoot()
                } else if ProcessInfo.processInfo.arguments.contains("--retained-images-fixture") {
                    RetainedImageFixtureView(mode: fixtureArgument("--retained-images-fixture") ?? "success")
                } else if ProcessInfo.processInfo.arguments.contains("--square-governance-fixture") {
                    SquareGovernanceFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--shop-npc-fixture") {
                    ShopNPCFixtureView(enabled: fixtureArgument("--shop-npc-fixture") == "enabled")
                } else if ProcessInfo.processInfo.arguments.contains("--club-community-fixture") {
                    ClubCommunityFixtureRoot()
                } else if ProcessInfo.processInfo.arguments.contains("--public-merchant-home-fixture") {
                    PublicMerchantHomeFixtureView(scenario: fixtureArgument("--public-merchant-home-fixture") ?? "profile")
                } else if ProcessInfo.processInfo.arguments.contains("--door-referral-fixture") {
                    DoorReferralFixtureView()
                } else if ProcessInfo.processInfo.arguments.contains("--merchant-marketing-fixture") {
                    MerchantMarketingFixtureHost(scenario: fixtureArgument("--merchant-marketing-scenario") ?? "normal", initialSurface: MerchantMarketingCoordinator.Surface(rawValue: fixtureArgument("--merchant-marketing-fixture") ?? "dashboard") ?? .dashboard)
                } else if ProcessInfo.processInfo.arguments.contains("--im-expanded-fixture") {
                    IMExpandedFixtureRoot(scenario: ProcessInfo.processInfo.arguments.last ?? "dormant")
                } else if ProcessInfo.processInfo.arguments.contains("--ui-coupon-management") {
                    CouponManagementFixtureHost()
                } else if WalletCommerceFixtureHost.selected {
                    WalletCommerceFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--ui-publishing-modes") {
                    PublishingModesFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--nearby-team-fixture") {
                    NearbyTeamFixtureRoot()
                } else if ProcessInfo.processInfo.arguments.contains("--official-action-fixture") {
                    OfficialActionFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-engagement-fixture") {
                    MerchantEngagementFixtureHostView()
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-business-fixture") {
                    MerchantBusinessFixtureHostView()
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-content-fixture") {
                    MerchantContentFixtureScenarioView()
                } else if ProcessInfo.processInfo.arguments.contains("--cooperation-flow-fixture") {
                    CoopFlowFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-club-governance") {
                    ClubGovernanceFixtureHost()
                } else if ProcessInfo.processInfo.arguments.contains("--ui-template-authoring") {
                    TemplateAuthoringFixtureHostView()
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-order-lifecycle-fixture") {
                    OrderLifecycleFixtureHostView()
                } else if RoamExperienceFixtureHostView.selected {
                    RoamExperienceFixtureHostView()
                } else if let scenario=ActivityFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ActivityFixtureRootView(scenario:scenario)
                } else if let merchant=MerchantFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    MerchantFixtureRootView(scenario:merchant)
                } else if ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-operations-fixture") {
                    MerchantOperationsFixtureHostView()
                } else if let onboarding=MerchantOnboardingFixtureRoot.selected(arguments:ProcessInfo.processInfo.arguments) {
                    MerchantOnboardingFixtureRoot(name:onboarding)
                } else if let club=ClubFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ClubFixtureRootView(scenario:club)
                } else if let clubOperations = ClubOperationsFixtureHostView.selected(arguments: ProcessInfo.processInfo.arguments) {
                    ClubOperationsFixtureHostView(scenario: clubOperations)
                } else if let clubManagement=ClubManagementFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ClubManagementFixtureRootView(scenario:clubManagement)
                } else if let profileEdit=ProfileEditFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ProfileEditFixtureHost(scenario:profileEdit)
                } else if let clubAction=ClubActionFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ClubActionFixtureRootView(scenario:clubAction)
                } else if let registration=RegistrationFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    RegistrationFixtureHostView(scenario:registration)
                } else if let module=ModuleFixture.selected {
                    ModuleFixtureRootView(module:module)
                } else if let session=sessionContainer.session {
                    SessionRootView(session:session)
                }
                #else
                if let session=sessionContainer.session {
                    SessionRootView(session:session)
                }
                #endif
            }
            .environment(\.locale, RegionalLaunchConfiguration.language(storedLanguage).locale)
            .tint(QuestifyPalette.accent)
        }
    }
}

/// Preserve the app-scoped production session without constructing it in fixture mode.
@MainActor
private final class AppSessionContainer: ObservableObject {
    let session: AppSession?

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--merchant-npc-fixture") || ProcessInfo.processInfo.arguments.contains("--publisher-lifecycle-fixture") || ProcessInfo.processInfo.arguments.contains("--retained-images-fixture") || ProcessInfo.processInfo.arguments.contains("--square-governance-fixture") || ProcessInfo.processInfo.arguments.contains("--shop-npc-fixture") || ProcessInfo.processInfo.arguments.contains("--club-community-fixture") || ProcessInfo.processInfo.arguments.contains("--public-merchant-home-fixture") || ProcessInfo.processInfo.arguments.contains("--door-referral-fixture") || ProcessInfo.processInfo.arguments.contains("--merchant-marketing-fixture") || ProcessInfo.processInfo.arguments.contains("--im-expanded-fixture") || ProcessInfo.processInfo.arguments.contains("--ui-coupon-management") || WalletCommerceFixtureHost.selected || ProcessInfo.processInfo.arguments.contains("--ui-publishing-modes") ||
           ProcessInfo.processInfo.arguments.contains("--nearby-team-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--official-action-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-club-governance") ||
           ProcessInfo.processInfo.arguments.contains("--ui-template-authoring") ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-order-lifecycle-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-engagement-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-business-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-content-fixture") ||
           ProcessInfo.processInfo.arguments.contains("--cooperation-flow-fixture") ||
           RoamExperienceFixtureHostView.selected || ActivityFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           MerchantFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil || ModuleFixture.selected != nil ||
           ProcessInfo.processInfo.arguments.contains("--uitesting-merchant-operations-fixture") ||
           MerchantOnboardingFixtureRoot.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           ClubFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           ClubActionFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           ClubOperationsFixtureHostView.selected(arguments: ProcessInfo.processInfo.arguments) != nil ||
           ClubManagementFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           ProfileEditFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           RegistrationFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil {
            session=nil
            return
        }
        #endif
        session=AppSession()
    }
}

/// Only the normal root starts account restoration.
@MainActor
private struct SessionRootView: View {
    @ObservedObject var session: AppSession
    @State private var browsingAsGuest=false
    @State private var selectedTab=0
    @State private var showsAreaPicker=false
    #if DEBUG
    @State private var showsScannerFixture = false
    #endif

    var body: some View {
        Group {
            if session.account != nil || browsingAsGuest {
                TabView(selection:$selectedTab) {
                    SessionHomeFeedView(onSignIn:{ selectedTab=4 }).tabItem { Label("homeFeed.title",systemImage:"house") }.tag(0)
                    ActivityBrowserView(reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true).tabItem { Label("activity.browse",systemImage:"map") }.tag(1)
                    RoamBrowserView(reader:session.roamReader,onChooseArea:{ showsAreaPicker=true },experienceReader:session.roamExperienceReader, nearbyTeamsDestination: { AnyView(SessionNearbyTeamsView(context: session.nearbyTeamQueryContext)) }, mediaScope:session.platformConsumers.scope, makeExternalMaps:session.platformConsumers.mapsFactory)
                        .tabItem { Label("roam.title",systemImage:"map") }.tag(3)
                    NavigationStack { ClubHomeView(reader:session,onSignIn:{ selectedTab=4 },actionCoordinator:session.clubActionCoordinator,management:session.clubManagementContext, community:session.clubCommunityContext) }
                        .tabItem { Label("club.title",systemImage:"person.3") }.tag(2)
                    Group {
                        if let account=session.account { AccountView(account:account,onOpenGuideDestination:{ destination in selectedTab = destination == .roam ? 3 : 0 }).id(session.sessionRevision) }
                        else { WelcomeView() }
                    }.tabItem { Label("account.title",systemImage:"person.crop.circle") }.tag(4)
                }.id(session.account?.id ?? 0)
            } else { WelcomeView(onBrowse:{ browsingAsGuest=true }) }
        }
        .background {
            if session.account != nil { RetainedImagePresenterHost(host: session.retainedImagePickerHost).frame(width: 0, height: 0) }
        }
        .environmentObject(session)
        .environment(\.complianceSignupDestination, { AnyView(SessionComplianceSignupView(session: session)) })
        .environment(\.merchantCouponManagementDestination, { AnyView(SessionCouponManagementView()) })
        .task { await session.bootstrap() }
        .onOpenURL { session.receiveNativeURL($0) }
        .sheet(item: Binding(get: { session.nativeEntry }, set: { if $0 == nil { session.dismissNativeEntry() } })) { entry in
            NativeEntryLandingView(entry: entry, session: session, goHome: { browsingAsGuest = true; selectedTab = 0 })
        }
        .sheet(isPresented:$showsAreaPicker) { RoamAreaPicker(onSelect:{ session.roamArea=$0 }) }
        #if DEBUG
        .sheet(isPresented: $showsScannerFixture) { NativeQRScanner { _ in } }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--uitesting-scanner") {
                showsScannerFixture = true
            }
        }
        #endif
    }
}

#if DEBUG
private func fixtureArgument(_ flag: String) -> String? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") else { return nil }
    return args[index + 1]
}
#endif
