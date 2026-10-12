import SwiftUI
import Combine
import CoreLocation
import UIKit

@MainActor protocol RoamLocationSettingsProviding {
    func readStatus() async throws -> RoamLocationSettingsSnapshot
    func openAppSettings() async -> Bool
}

/// Only static status queries: no manager construction, permission prompt, coordinates or GPS start.
@MainActor struct RoamSystemLocationSettingsProvider: RoamLocationSettingsProviding {
    func readStatus() async throws -> RoamLocationSettingsSnapshot {
        try Task.checkCancellation()
        let snapshot = await withCheckedContinuation { (reply: CheckedContinuation<RoamLocationSettingsSnapshot, Never>) in
            DispatchQueue.global(qos: .utility).async {
                // The static API avoids even constructing a CLLocationManager. It remains available
                // on the deployment target, though Apple deprecates it in favor of the instance getter.
                let status = CLLocationManager.authorizationStatus()
                reply.resume(returning: .init(authorization: Self.map(status),
                    servicesEnabled: CLLocationManager.locationServicesEnabled()))
            }
        }
        try Task.checkCancellation()
        return snapshot
    }
    nonisolated static func map(_ status: CLAuthorizationStatus) -> RoamSystemLocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways: return .always
        @unknown default: return .unknown
        }
    }
    func openAppSettings() async -> Bool {
        guard UIApplication.shared.applicationState == .active,
              let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        return await withCheckedContinuation { reply in
            UIApplication.shared.open(url, options: [:]) { reply.resume(returning: $0) }
        }
    }
}

@MainActor final class RoamLocationSettingsModel: ObservableObject {
    @Published private(set) var state = RoamLocationSettingsState()
    private let provider: any RoamLocationSettingsProviding
    private var isActive = false
    private var readTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    init(provider: any RoamLocationSettingsProviding) { self.provider = provider }
    func activate() { suspend(); isActive = true; refresh() }
    func refresh() {
        guard isActive else { return }
        settingsTask?.cancel(); settingsTask = nil
        readTask?.cancel()
        let attempt = state.beginRead()
        readTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let snapshot = try await self.provider.readStatus()
                guard !Task.isCancelled else { return }
                self.state.finishRead(attempt, snapshot: snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                self.state.finishRead(attempt, snapshot: nil)
            }
        }
    }
    func openSettings() {
        guard isActive, let attempt = state.beginSettingsOpen() else { return }
        settingsTask = Task { [weak self] in
            guard let self, !Task.isCancelled, self.state.acceptsSettingsOpen(attempt) else { return }
            let opened = await self.provider.openAppSettings()
            guard !Task.isCancelled else { return }
            self.state.finishSettingsOpen(attempt, opened: opened)
        }
    }
    func suspend() {
        isActive = false
        readTask?.cancel(); readTask = nil; settingsTask?.cancel(); settingsTask = nil
        state.invalidate()
    }
}

/// Ordinary production always uses actual OS status and the standard application-settings URL.
@MainActor struct RoamLocationSettingsDestination: View {
    @StateObject private var model: RoamLocationSettingsModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    init() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting-roam-experience"),
           let index = args.firstIndex(of: "--uitesting-roam-location-settings-scenario"), args.indices.contains(index + 1) {
            _model = StateObject(wrappedValue: RoamLocationSettingsModel(provider: RoamLocationSettingsFixtureProvider(scenario: args[index + 1])))
            return
        }
        #endif
        _model = StateObject(wrappedValue: RoamLocationSettingsModel(provider: RoamSystemLocationSettingsProvider()))
    }
    var body: some View {
        List {
            Section {
                Text("roam.locationSettings.hint").font(.subheadline).foregroundStyle(.secondary)
            }
            Section("roam.locationSettings.status") {
                switch model.state.phase {
                case .idle, .loading: ProgressView("roam.loading").accessibilityIdentifier("roam.locationSettings.loading")
                case .failed:
                    Text("roam.locationSettings.readFailed").accessibilityIdentifier("roam.locationSettings.readFailed")
                    Button("roam.locationSettings.retry") { model.refresh() }.accessibilityIdentifier("roam.locationSettings.retry")
                case .loaded(let snapshot):
                    LabeledContent("roam.locationSettings.authorization") {
                        Text(LocalizedStringKey("roam.locationSettings.authorization." + snapshot.authorization.rawValue))
                            .accessibilityIdentifier("roam.locationSettings.authorization." + snapshot.authorization.rawValue)
                    }
                    LabeledContent("roam.locationSettings.always") {
                        Text(snapshot.alwaysAuthorized ? "roam.locationSettings.granted" : "roam.locationSettings.notGranted")
                            .accessibilityIdentifier(snapshot.alwaysAuthorized ? "roam.locationSettings.always.granted" : "roam.locationSettings.always.notGranted")
                    }
                    LabeledContent("roam.locationSettings.services") {
                        Text(snapshot.servicesEnabled ? "roam.locationSettings.enabled" : "roam.locationSettings.disabled")
                            .accessibilityIdentifier(snapshot.servicesEnabled ? "roam.locationSettings.services.enabled" : "roam.locationSettings.services.disabled")
                    }
                }
                Text("roam.locationSettings.capabilityHint").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("roam.locationSettings.openSettings") { model.openSettings() }
                    .disabled(model.state.isOpeningSettings)
                    .accessibilityIdentifier("roam.locationSettings.openSettings")
                if model.state.settingsOpenFailed {
                    Text("roam.locationSettings.openFailed").foregroundStyle(.secondary)
                        .accessibilityIdentifier("roam.locationSettings.openFailed")
                }
                Button("roam.locationSettings.refresh") { model.refresh() }
                    .accessibilityIdentifier("roam.locationSettings.refresh")
            }
        }
        .navigationTitle("roam.locationSettings.title")
        .accessibilityIdentifier("roam.locationSettings.screen")
        .onAppear { isVisible = true; if scenePhase == .active { model.activate() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, isVisible { model.activate() } else { model.suspend() }
        }
        .onDisappear { isVisible = false; model.suspend() }
    }
}

#if DEBUG
/// Explicit UI fixtures never open Settings, start GPS, or change the device's actual authorization.
@MainActor private final class RoamLocationSettingsFixtureProvider: RoamLocationSettingsProviding {
    private let scenario: String
    private var reads = 0
    init(scenario: String) { self.scenario = scenario }
    func readStatus() async throws -> RoamLocationSettingsSnapshot {
        reads += 1
        if scenario == "readFailure", reads == 1 { throw CancellationError() }
        let status = scenario == "refreshChanges" ? (reads == 1 ? RoamSystemLocationAuthorization.denied : .whenInUse) :
            (RoamSystemLocationAuthorization(rawValue: scenario) ?? .whenInUse)
        return .init(authorization: status, servicesEnabled: scenario != "servicesDisabled")
    }
    func openAppSettings() async -> Bool { false }
}
#endif
