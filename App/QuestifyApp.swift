import SwiftUI

@main
struct QuestifyApp: App {
    @StateObject private var sessionContainer = AppSessionContainer()
    @AppStorage("preferences.language") private var storedLanguage = AppLanguage.system.rawValue
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset-language") {
            UserDefaults.standard.removeObject(forKey: "preferences.language")
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let scenario=ActivityFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ActivityFixtureRootView(scenario:scenario)
                } else if let merchant=MerchantFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    MerchantFixtureRootView(scenario:merchant)
                } else if let club=ClubFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) {
                    ClubFixtureRootView(scenario:club)
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
            .environment(\.locale, AppLanguage(storedValue: storedLanguage).locale)
            .tint(.purple)
        }
    }
}

/// Preserve the app-scoped production session without constructing it in fixture mode.
@MainActor
private final class AppSessionContainer: ObservableObject {
    let session: AppSession?

    init() {
        #if DEBUG
        if ActivityFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           MerchantFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil || ModuleFixture.selected != nil ||
           ClubFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
           ClubActionFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil ||
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
                    DiscoveryHomeView(reader:session).tabItem { Label("discovery.title",systemImage:"sparkle.magnifyingglass") }.tag(0)
                    ActivityBrowserView(reader:session,playReaderForActivity:{ session.playReader(for:.activity($0)) },registrationEnabled:true).tabItem { Label("activity.browse",systemImage:"map") }.tag(1)
                    RoamBrowserView(reader:session.roamReader,onChooseArea:{ showsAreaPicker=true })
                        .tabItem { Label("roam.title",systemImage:"map") }.tag(3)
                    NavigationStack { ClubHomeView(reader:session,onSignIn:{ selectedTab=4 },actionCoordinator:session.clubActionCoordinator) }
                        .tabItem { Label("club.title",systemImage:"person.3") }.tag(2)
                    Group {
                        if let account=session.account { AccountView(account:account) }
                        else { WelcomeView() }
                    }.tabItem { Label("account.title",systemImage:"person.crop.circle") }.tag(4)
                }.id(session.account?.id ?? 0)
            } else { WelcomeView(onBrowse:{ browsingAsGuest=true }) }
        }
        .environmentObject(session)
        .task { await session.bootstrap() }
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
