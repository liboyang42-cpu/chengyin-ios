import SwiftUI

@main
struct QuestifyApp: App {
    @StateObject private var session = AppSession()
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
                if let account = session.account {
                    TabView {
                        ActivityBrowserView().tabItem { Label("activity.browse",systemImage:"map") }
                        AccountView(account:account).tabItem { Label("account.title",systemImage:"person.crop.circle") }
                    }.id(account.id)
                }
                else { WelcomeView() }
            }
                .environmentObject(session)
                .environment(\.locale, AppLanguage(storedValue: storedLanguage).locale)
                .task { await session.bootstrap() }
        }
    }
}
