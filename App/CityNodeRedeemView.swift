import SwiftUI

@MainActor private final class CityNodeRedeemModel: ObservableObject {
    let coordinator: CityNodeRedemptionCoordinator
    @Published private(set) var revision = 0
    init(_ coordinator: CityNodeRedemptionCoordinator) { self.coordinator = coordinator }
    func prepare(_ raw: String) async { revision += 1; await coordinator.prepare(raw); revision += 1 }
    func confirm(_ id: UUID) async { revision += 1; await coordinator.confirm(id); revision += 1 }
    func cancel() { coordinator.cancelReview(); revision += 1 }
    func next() { coordinator.next(); revision += 1 }
    func invalidate() { coordinator.invalidate(); revision += 1 }
}

@MainActor struct CityNodeRedeemView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: CityNodeRedeemModel
    @State private var raw = ""
    @State private var showsScanner = false
    @State private var preparing = false
    @State private var confirming = false
    @State private var scannedCode: String?
    @State private var visible = false
    @State private var lifetime = UUID()
    @FocusState private var codeFocused: Bool
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore) {
        _model = StateObject(wrappedValue: CityNodeRedeemModel(reader.cityNodeRedemption(journal: journal)))
    }
    private var busy: Bool { preparing || confirming || model.coordinator.busy }
    var body: some View {
        Form {
            Section {
                Text("merchant.cityRedeem.instructions")
                if !model.coordinator.isAvailable { Text("merchant.cityRedeem.disabled").foregroundStyle(.secondary) }
                SecureField("merchant.cityRedeem.code", text: $raw)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($codeFocused).privacySensitive().disabled(busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.code")
                Button("merchant.cityRedeem.review") { prepare(raw) }
                    .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.review")
                Button { showsScanner = true } label: { Label("merchant.cityRedeem.scan", systemImage: "qrcode.viewfinder") }
                    .disabled(!model.coordinator.isAvailable || busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.scan")
                Text("merchant.cityRedeem.cameraConsent").font(.footnote).foregroundStyle(.secondary)
            }
            if busy { ProgressView("merchant.cityRedeem.processing") }
            if let result = model.coordinator.result {
                Section {
                    Label {
                        Text(LocalizedStringKey(result.redeemed ? "merchant.cityRedeem.success" : "merchant.cityRedeem.rejected"))
                    } icon: { Image(systemName: result.redeemed ? "checkmark.circle" : "exclamationmark.circle") }
                    Text(verbatim: result.message).textSelection(.enabled)
                        .accessibilityIdentifier("merchant.cityRedeem.serverMessage")
                    Button("merchant.cityRedeem.next") { raw = ""; model.next() }
                        .accessibilityIdentifier("merchant.cityRedeem.next")
                }
            }
            if let failure = model.coordinator.failure {
                Text(LocalizedStringKey(failure)).accessibilityIdentifier("merchant.cityRedeem.failure")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .appNavigationTitle("merchant.cityRedeem.title")
        .confirmationDialog("merchant.cityRedeem.confirmTitle", isPresented: Binding(
            get: { model.coordinator.review != nil },
            set: { if !$0 && !confirming { model.cancel() } }
        ), titleVisibility: .visible) {
            if let review = model.coordinator.review {
                Button("merchant.cityRedeem.confirm") {
                    guard !busy, visible, scenePhase == .active else { return }
                    confirming = true
                    Task { await model.confirm(review.id); confirming = false }
                }.accessibilityIdentifier("merchant.cityRedeem.confirm")
                Button("action.cancel", role: .cancel) { model.cancel() }
            }
        } message: {
            Text("merchant.cityRedeem.confirmHint")
        }
        .sheet(isPresented: $showsScanner, onDismiss: {
            // Wait for scanner dismissal before presenting the short confirmation dialog.
            guard let payload = scannedCode else { return }
            scannedCode = nil
            prepare(payload)
        }) {
            // No automatic camera grant, payload URL navigation or redeem-on-detection.
            NativeQRScanner { payload in
                guard model.coordinator.isAvailable, scenePhase == .active, !busy else { return }
                scannedCode = payload
            }
        }
        .onAppear { visible = true }
        .onChange(of: model.coordinator.scope) { _, _ in clear() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
        .onDisappear { visible = false; clear() }
    }
    private func prepare(_ code: String) {
        guard visible, !busy, scenePhase == .active else { return }
        codeFocused = false; raw = ""; preparing = true
        let captured = lifetime
        Task {
            guard visible, lifetime == captured, scenePhase == .active else { preparing = false; return }
            await model.prepare(code); preparing = false
        }
    }
    private func clear() { lifetime = UUID(); codeFocused = false; raw = ""; scannedCode = nil; showsScanner = false; model.invalidate() }
}
