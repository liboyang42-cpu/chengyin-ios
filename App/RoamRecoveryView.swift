import SwiftUI

@MainActor struct RoamRecoveryView: View {
    let reader: any RoamExperienceReading
    @State private var sessionID = ""
    @State private var coordinator: RoamRecoveryCoordinator
    @State private var revision = 0
    @State private var loading = false
    init(reader: any RoamExperienceReading) {
        self.reader = reader; _coordinator = State(initialValue: RoamRecoveryCoordinator(reader: reader))
    }
    var body: some View {
        List {
            Section {
                RoamExperienceNotice(offline: reader.isOfflineExample)
                Text("roam.experience.recoveryHint").font(.subheadline)
                TextField("roam.experience.sessionID", text: $sessionID)
                    .keyboardType(.numberPad).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("roam.experience.recovery.id")
                Button("roam.experience.checkSession") { Task { await recover() } }
                    .disabled(loading || (Int(sessionID) ?? 0) <= 0 || reader.identity == nil || !reader.isConfigured)
                    .accessibilityIdentifier("roam.experience.recovery.check")
                if reader.identity == nil { Text("roam.signInRequired") }
                else if !reader.isConfigured { Text("roam.notConfigured") }
            }
            Section {
                if loading { ProgressView("roam.loading") }
                else {
                    switch coordinator.phase {
                    case .idle, .loading: EmptyView()
                    case .active:
                        Label("roam.experience.sessionActive", systemImage: "pause.circle")
                        Text("roam.experience.activeHint").font(.caption)
                    case .notFound:
                        Label("roam.experience.sessionNotFound", systemImage: "questionmark.circle")
                    case .incomplete:
                        Label("roam.experience.settlementIncomplete", systemImage: "clock.badge.exclamationmark")
                        Text("roam.experience.incompleteHint").font(.caption)
                    case .finished:
                        Label("roam.experience.settled", systemImage: "checkmark.seal")
                        if let result = coordinator.fact?.result {
                            if let xp = result.totalXp { LabeledContent("roam.experience.xp", value: String(xp)) }
                            if let tiles = result.newTiles { LabeledContent("roam.experience.newTiles", value: String(tiles)) }
                            if let places = result.newPois { LabeledContent("roam.experience.newPlaces", value: String(places)) }
                            if let shops = result.sessionShops { LabeledContent("roam.experience.shops", value: String(shops)) }
                            if let medal = result.medal, !medal.isEmpty { Label { Text(verbatim: medal) } icon: { Image(systemName: "medal") } }
                            if let medal = result.shopMedal { Text(verbatim: medal.name) }
                        }
                        Text("roam.experience.recoveryNoTrack").font(.caption).foregroundStyle(.secondary)
                    case .failed:
                        if let error = coordinator.error { RoamExperienceIssue(error: error) { Task { await recover() } } }
                    }
                }
            }.accessibilityIdentifier("roam.experience.recovery.result")
        }.navigationTitle("roam.experience.recovery")
            .onChange(of: sessionID) { _, _ in coordinator.reset(); loading = false; revision += 1 }
            .onDisappear { coordinator.reset(); loading = false; revision += 1 }
            .accessibilityIdentifier("roam.experience.recovery")
    }
    private func recover() async {
        guard let id = Int(sessionID), id > 0 else { return }
        revision += 1; let ticket = revision
        loading = true
        await coordinator.recover(.sessionID(id))
        if revision == ticket { loading = false; revision += 1 }
    }
}
