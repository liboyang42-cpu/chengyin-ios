import SwiftUI

struct SettingsView: View {
    @AppStorage("preferences.language") private var storedLanguage = RegionalLaunchConfiguration.language(nil).rawValue
    @Environment(\.dismiss) private var dismiss

    private var language: Binding<AppLanguage> {
        Binding(get: { RegionalLaunchConfiguration.language(storedLanguage) },
                set: { storedLanguage = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent { Text(verbatim:RegionalLaunchConfiguration.market?.rawValue ?? "—").accessibilityIdentifier("region.market.value") } label: { Text("region.market") }
                    Text("region.languageBoundary").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("settings.language", selection: language) {
                        Text("language.system").tag(AppLanguage.system)
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    }
                    .pickerStyle(.inline)
                } footer: { Text("settings.languageNotice") }
            }
            .appNavigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        // Explicitly update sheets as well as the app root when preference changes.
        .environment(\.locale, RegionalLaunchConfiguration.language(storedLanguage).locale)
    }
}
