import SwiftUI

/// Insert these sections inside the existing SettingsView Form. No language picker, new root
/// NavigationStack, regional override, credentials, or session service is created here.
@MainActor struct SettingsSupportSections: View {
    let market: RegionalMarket?
    let complianceCoordinator: AccountComplianceCoordinator?
    let soundStore: any SettingsSoundStoring
    let legalReader: any SettingsLegalReading
    let appInformation: SettingsAppInformation
    init(market: RegionalMarket?, complianceCoordinator: AccountComplianceCoordinator? = nil, soundStore: (any SettingsSoundStoring)? = nil,
         legalReader: (any SettingsLegalReading)? = nil,
         appInformation: SettingsAppInformation = .current()) {
        self.complianceCoordinator = complianceCoordinator
        self.market = market; self.soundStore = soundStore ?? SettingsLocalSoundStore()
        self.legalReader = legalReader ?? SettingsBundledLegalReader()
        self.appInformation = appInformation
    }
    var body: some View {
        Section {
            NavigationLink {
                SettingsSoundPreferencesView(store: soundStore)
            } label: { Label("settingsNative.sound.title", systemImage: "speaker.wave.2") }
            .accessibilityIdentifier("settingsNative.openSound")
            NavigationLink {
                SettingsAboutView(market: market, appInformation: appInformation, legalReader: legalReader)
            } label: { Label("settingsNative.about.title", systemImage: "info.circle") }
            .accessibilityIdentifier("settingsNative.openAbout")
        }
        Section("settingsNative.legal.title") {
            ForEach(SettingsLegalType.allCases) { type in
                NavigationLink {
                    SettingsLegalDocumentView(type: type, market: market, reader: legalReader)
                } label: { Text(LocalizedStringKey(type.titleKey)) }
                .accessibilityIdentifier("settingsNative.openLegal.\(type.rawValue)")
            }
        }
        if let complianceCoordinator {
            AccountComplianceSettingsSection(makeCoordinator: { complianceCoordinator }, market: market, legalReader: legalReader)
        } else {
        Section("settingsNative.privacy.title") {
            ForEach(SettingsUnavailableFeature.allCases) { feature in
                NavigationLink {
                    SettingsUnavailableFeatureView(feature: feature, market: market, legalReader: legalReader)
                } label: { Text(LocalizedStringKey(feature.titleKey)) }
                .accessibilityIdentifier("settingsNative.openBlocked.\(feature.rawValue)")
            }
        }
        }
        SettingsAttributionsSection()
    }
}

@MainActor private final class SettingsSoundViewModel: ObservableObject {
    @Published private(set) var state = SettingsSoundState()
    private let coordinator: SettingsSoundCoordinator
    init(store: any SettingsSoundStoring) {
        coordinator = SettingsSoundCoordinator(store: store)
        coordinator.onChange = { [weak self] in self?.state = $0 }
    }
    func load() async { await coordinator.load() }
    func set(_ key: SettingsSoundKey, to value: Bool) async { await coordinator.set(key, to: value) }
}
@MainActor struct SettingsSoundPreferencesView: View {
    @StateObject private var model: SettingsSoundViewModel
    init(store: any SettingsSoundStoring) { _model = StateObject(wrappedValue: SettingsSoundViewModel(store: store)) }
    var body: some View {
        Form {
            if let preferences = model.state.preferences {
                Section {
                    soundToggle(.sound, preferences: preferences)
                    soundToggle(.haptics, preferences: preferences)
                }
                Section("settingsNative.sound.ambient") {
                    ForEach([SettingsSoundKey.airplane, .ocean, .raindrop, .forest]) { key in
                        soundToggle(key, preferences: preferences)
                    }
                }
                Section { Text("settingsNative.sound.localOnly").font(.footnote).foregroundStyle(.secondary) }
            } else if model.state.isBusy {
                ProgressView("settingsNative.loading").accessibilityIdentifier("settingsNative.sound.loading")
            }
            if let key = model.state.messageKey {
                Section {
                    Text(LocalizedStringKey(key)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settingsNative.sound.error")
                    if model.state.preferences == nil {
                        Button("settingsNative.retry") { Task { await model.load() } }
                            .accessibilityIdentifier("settingsNative.sound.retry")
                    }
                }
            }
        }
        .appNavigationTitle("settingsNative.sound.title")
        .task { await model.load() }
    }
    private func soundToggle(_ key: SettingsSoundKey, preferences: SettingsSoundPreferences) -> some View {
        Toggle(LocalizedStringKey(key.titleKey), isOn: Binding(
            get: { model.state.preferences?[key] ?? preferences[key] },
            set: { value in Task { await model.set(key, to: value) } }
        ))
        .disabled(model.state.isBusy)
        .accessibilityIdentifier("settingsNative.sound.\(key.rawValue)")
    }
}

@MainActor struct SettingsUnavailableFeatureView: View {
    let feature: SettingsUnavailableFeature
    let market: RegionalMarket?
    let legalReader: any SettingsLegalReading
    var body: some View {
        Form {
            Section {
                Label("settingsNative.blocked.unavailable", systemImage: "info.circle")
                Text(LocalizedStringKey(feature.messageKey)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settingsNative.blocked.message")
            }
            Section {
                let type: SettingsLegalType = feature == .accountDeletion ? .cancellationNotice : .privacyPolicy
                NavigationLink {
                    SettingsLegalDocumentView(type: type, market: market, reader: legalReader)
                } label: { Text(LocalizedStringKey(type.titleKey)) }
                .accessibilityIdentifier("settingsNative.blocked.openDocument")
            }
        }
        .navigationTitle(Text(LocalizedStringKey(feature.titleKey)))
    }
}

struct SettingsAttributionsSection: View {
    var body: some View {
        Section("settingsNative.attribution.title") {
            Text("settingsNative.attribution.context").font(.footnote).foregroundStyle(.secondary)
            ForEach(SettingsSourceAttribution.all) { attribution in
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: attribution.title).font(.subheadline.weight(.semibold))
                    Text(verbatim: attribution.detail).font(.footnote)
                    Text(verbatim: attribution.sourceURL).font(.footnote).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityIdentifier("settingsNative.attribution.\(attribution.id)")
            }
        }
    }
}
