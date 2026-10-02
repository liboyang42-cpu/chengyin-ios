import SwiftUI

/// Navigation destination owns preparation/review. Only the actual camera is full-screen;
/// closing it returns to this destination with no synthetic scan or success callback.
@MainActor struct RoamPosterScanView: View {
    let node: RoamNodeDetail
    var coordinator: RoamPosterCoordinator? = nil
    var cameraEnabled = false
    @State private var purposeAccepted = false
    @State private var showingScanner = false
    @State private var revision = 0
    @State private var work: Task<Void, Never>?
    private var availability: RoamPosterAvailability { .init(node: node) }
    var body: some View {
        let _ = revision
        Form {
            Section {
                Text(verbatim: node.name).font(.headline)
                Text("media.poster.purpose")
                if availability != .available { Text(LocalizedStringKey(availabilityKey)) }
                if !cameraEnabled || coordinator?.available != true { Label("media.poster.disabled", systemImage: "lock.shield") }
            }
            if let coordinator {
                Section { Text(LocalizedStringKey("media.poster.phase." + phaseKey(coordinator.phase))) }
                if coordinator.phase == .review {
                    Button("media.poster.confirm") { run { await coordinator.submit() } }.accessibilityIdentifier("media.poster.confirm")
                }
                if coordinator.phase == .needsRedemption || availability == .needsRedemption {
                    NavigationLink("roam.experience.voucher") { RoamVoucherEntryView() }
                }
            }
            Section {
                Toggle("media.poster.consent", isOn: $purposeAccepted)
                Button("media.poster.scan") { showingScanner = true }
                    .disabled(!purposeAccepted || !cameraEnabled || coordinator?.available != true || availability != .available || !canScan)
                    .accessibilityIdentifier("media.poster.scan")
            }
        }.navigationTitle("media.poster.title")
            .fullScreenCover(isPresented: $showingScanner) {
                if cameraEnabled, let coordinator {
                    NativeQRScanner { code in showingScanner = false; run { await coordinator.scanned(code, purposeAccepted: purposeAccepted) } }
                }
            }
            .onAppear { coordinator?.changed = { revision += 1 } }
            .onDisappear { if !showingScanner { work?.cancel(); work = nil; coordinator?.cancel(); coordinator?.changed = nil } }
            .accessibilityIdentifier("media.poster.destination")
    }
    private var canScan: Bool { coordinator?.phase == .ready || coordinator?.phase == .failed }
    private var availabilityKey: String {
        switch availability {
        case .available: return "media.poster.ready"
        case .offline: return "roam.notPublished"
        case .completed: return "roam.completed"
        case .needsRedemption: return "media.poster.phase.needsRedemption"
        case .unsupported: return "media.poster.unsupported"
        }
    }
    private func phaseKey(_ phase: RoamPosterCoordinator.Phase) -> String {
        switch phase {
        case .ready: return "ready"
        case .locating: return "locating"
        case .review: return "review"
        case .preflighting: return "preflighting"
        case .submitting: return "submitting"
        case .unknown: return "unknown"
        case .completed: return "completed"
        case .needsRedemption: return "needsRedemption"
        case .unavailable: return "unavailable"
        case .failed: return "failed"
        }
    }
    private func run(_ action: @escaping @MainActor () async -> Void) { work?.cancel(); work = Task { await action(); revision += 1 } }
}
