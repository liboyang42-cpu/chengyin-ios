import SwiftUI

@main
struct QuestifyApp: App {
    @AppStorage("preferences.language") private var storedLanguage = AppLanguage.system.rawValue
    var body: some Scene {
        WindowGroup {
            WelcomeView()
                .environment(\.locale, AppLanguage(storedValue: storedLanguage).locale)
        }
    }
}
