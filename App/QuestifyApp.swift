import SwiftUI

@main
struct QuestifyApp: App {
    @StateObject private var session = AppSession()
    @AppStorage("preferences.language") private var storedLanguage = AppLanguage.system.rawValue
    var body: some Scene {
        WindowGroup {
            Group {
                if let account = session.account { AccountView(account: account) }
                else { WelcomeView() }
            }
                .environmentObject(session)
                .environment(\.locale, AppLanguage(storedValue: storedLanguage).locale)
                .task { await session.bootstrap() }
        }
    }
}
