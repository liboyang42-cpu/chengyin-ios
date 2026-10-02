#if DEBUG
import SwiftUI

@MainActor final class SettingsFixtureSoundStore: SettingsSoundStoring {
    private var preferences = SettingsSoundPreferences.defaults
    private var failRead: Bool
    private var failWrite: Bool
    init(scenario: String) { failRead = scenario == "loadFailure"; failWrite = scenario == "saveFailure" }
    func read() async throws -> SettingsSoundPreferences {
        try await Task.sleep(nanoseconds: 80_000_000)
        if failRead { failRead = false; throw SettingsSoundStoreError.invalidStoredValue }
        return preferences
    }
    func write(_ value: SettingsSoundPreferences) async throws {
        try await Task.sleep(nanoseconds: 80_000_000)
        if failWrite { failWrite = false; throw SettingsSoundStoreError.writeFailed }
        preferences = value
    }
}
@MainActor final class SettingsFixtureLegalReader: SettingsLegalReading {
    private var failRead: Bool
    init(scenario: String) { failRead = scenario == "legalFailure" }
    func document(type: SettingsLegalType, market: RegionalMarket?) async throws -> SettingsLegalAvailability {
        try await Task.sleep(nanoseconds: 80_000_000)
        if failRead { failRead = false; throw SettingsSoundStoreError.invalidStoredValue }
        return SettingsSourceLegalCatalog.document(type: type, market: market)
    }
}
@MainActor struct SettingsFixtureHostView: View {
    @State private var store: SettingsFixtureSoundStore
    @State private var reader: SettingsFixtureLegalReader
    private let scenario: String
    init() {
        let args = ProcessInfo.processInfo.arguments
        let index = args.firstIndex(of: "--uitesting-settings-scenario")
        let value = index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "content"
        scenario = value
        _store = State(initialValue: SettingsFixtureSoundStore(scenario: value))
        _reader = State(initialValue: SettingsFixtureLegalReader(scenario: value))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("settingsNative.fixture.notice").font(.footnote) }
                SettingsSupportSections(
                    market: scenario == "missingMarket" ? nil : RegionalLaunchConfiguration.market,
                    soundStore: store, legalReader: reader,
                    appInformation: scenario == "missingMetadata" ? SettingsAppInformation(info: [:]) : .current(),
                    copyText: { _ in if scenario == "copyFailure" { throw SettingsSoundStoreError.writeFailed } }
                )
            }
            .appNavigationTitle("settings.title")
        }
    }
}
#endif
