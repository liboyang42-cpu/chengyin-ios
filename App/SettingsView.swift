import SwiftUI

struct SettingsView: View {
    var onOpenGuideDestination: ((SocialGuideDestination) -> Void)? = nil
    @EnvironmentObject private var session: AppSession
    @StateObject private var profileOwner = ProfileSettingsProfileOwner()
    @State private var favoritesOwner = ProfileSettingsFavoritesOwner()
    @AppStorage("preferences.language") private var storedLanguage = RegionalLaunchConfiguration.language(nil).rawValue
    @Environment(\.dismiss) private var dismiss

    private var language: Binding<AppLanguage> {
        Binding(get: { RegionalLaunchConfiguration.language(storedLanguage) },
                set: { storedLanguage = $0.rawValue })
    }

    var body: some View {
        NavigationStack {
            Form {
                ProfileSettingsProfileEntry(session: session, owner: profileOwner)
                ProfileSettingsFavoritesEntry(session: session, owner: favoritesOwner)
                Section {
                    NavigationLink {
                        ProfileGuideHost(reader: session.makeProfileGuideReader(),
                            makeArticleReader: { session.makeProfileGuideArticleReader($0) },
                            onOpenDestination: onOpenGuideDestination, templateReader: session)
                            .id(session.socialAccountReader.identity)
                    } label: { Label("social.guide.title", systemImage: "questionmark.circle") }
                        .accessibilityIdentifier("settings.playGuide")
                }
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
                SettingsSupportSections(market: session.operationalMarket, complianceCoordinator: session.accountComplianceCoordinator)
            }
            .modifier(ProfileSettingsProfileNavigation(session: session, owner: profileOwner))
            .modifier(ProfileSettingsFavoritesNavigation(session: session, owner: favoritesOwner))
            .appNavigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .onAppear { profileOwner.appear() }
        .onDisappear { profileOwner.retire() }
        .modifier(ProfileSettingsFavoritesLifecycle(session: session, owner: favoritesOwner))
        // Explicitly update sheets as well as the app root when preference changes.
        .environment(\.locale, RegionalLaunchConfiguration.language(storedLanguage).locale)
    }
}

/// One sheet presentation can hand a mode action back to its root only once,
/// after dismissal. Old dismissal callbacks cannot consume a newer request.
struct SettingsGuideHandoff {
    private(set) var presentation = UUID()
    private var active = false
    private var pending: (() -> Void)?
    mutating func begin() -> Bool {
        guard !active, pending == nil else { return false }
        presentation = UUID(); active = true; return true
    }
    mutating func request(_ id: UUID, action: @escaping () -> Void) -> Bool {
        guard active, id == presentation, pending == nil else { return false }
        active = false; pending = action; return true
    }
    mutating func finish(_ id: UUID) -> (() -> Void)? {
        guard id == presentation else { return nil }
        active = false
        let action = pending; pending = nil
        return action
    }
}
