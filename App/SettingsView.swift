import SwiftUI

struct SettingsView: View {
    @AppStorage("preferences.language") private var storedLanguage = AppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss

    private var language: Binding<AppLanguage> {
        Binding(get: { AppLanguage(storedValue: storedLanguage) },
                set: { storedLanguage = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("settings.language", selection: language) {
                        Text("language.system").tag(AppLanguage.system)
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("settings.language")
                } footer: { Text("settings.languageNotice") }
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        // Explicitly update sheets as well as the app root when preference changes.
        .environment(\.locale, AppLanguage(storedValue: storedLanguage).locale)
    }
}
