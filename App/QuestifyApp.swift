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
           MerchantFixtureScenario.selected(arguments:ProcessInfo.processInfo.arguments) != nil || ModuleFixture.selected != nil {
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
    #if DEBUG
    @State private var showsScannerFixture = false
    #endif

    var body: some View {
        Group {
            if session.account != nil || browsingAsGuest {
                TabView {
                    DiscoveryHomeView(reader:session).tabItem { Label("discovery.title",systemImage:"sparkle.magnifyingglass") }
                    ActivityBrowserView(reader:session).tabItem { Label("activity.browse",systemImage:"map") }
                    Group {
                        if let account=session.account { AccountView(account:account) }
                        else { WelcomeView() }
                    }.tabItem { Label("account.title",systemImage:"person.crop.circle") }
                }.id(session.account?.id ?? 0)
            } else { WelcomeView(onBrowse:{ browsingAsGuest=true }) }
        }
        .environmentObject(session)
        .task { await session.bootstrap() }
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
