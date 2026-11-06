import SwiftUI

private struct CityNodeReceiptFactoryKey: EnvironmentKey {
    static let defaultValue: (@MainActor () -> CityNodeRedemptionReceiptReader?)? = nil
}
extension EnvironmentValues {
    var cityNodeReceiptFactory: (@MainActor () -> CityNodeRedemptionReceiptReader?)? {
        get { self[CityNodeReceiptFactoryKey.self] }
        set { self[CityNodeReceiptFactoryKey.self] = newValue }
    }
}

@MainActor private final class CityNodeRedeemModel: ObservableObject {
    let coordinator: CityNodeRedemptionCoordinator
    private let reader: any MerchantBusinessReading
    private var receipt: CityNodeRedemptionReceiptReader?
    private var receiptResolved = false
    var canRecover: Bool { receipt?.isCurrent == true }
    private struct Authorization: Equatable {
        let scope: MerchantBusinessScope?
        let generation: UUID?
    }
    private var preparedAuthorization: Authorization?
    private var authorization: Authorization { .init(scope: reader.scope, generation: reader.authorizationGeneration) }
    var authorizationGeneration: UUID? { reader.authorizationGeneration }
    var isAvailable: Bool { coordinator.isAvailable && reader.canExecuteVerificationMutation }
    var blocksAllTargets: Bool { coordinator.pendingScope == .legacy || coordinator.pendingScope == .storage }
    @Published private(set) var revision = 0
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, receipt: CityNodeRedemptionReceiptReader? = nil) {
        self.reader = reader; self.receipt = receipt; coordinator = reader.cityNodeRedemption(journal: journal)
    }
    /// Resolve once per view owner. A replacement identity or grant cannot be silently adopted.
    func resolveReceipt(_ factory: (@MainActor () -> CityNodeRedemptionReceiptReader?)?) {
        guard !receiptResolved else { return }; receiptResolved = true
        if receipt == nil { receipt = factory?() }
        revision += 1
    }
    func prepare(_ raw: String) async {
        let captured = authorization; preparedAuthorization = nil; revision += 1
        await coordinator.prepare(raw, isCurrent: { self.authorization == captured && self.isAvailable })
        if coordinator.review != nil { preparedAuthorization = captured }
        revision += 1
    }
    func confirm(_ id: UUID) async {
        guard let captured = preparedAuthorization else { cancel(); return }
        preparedAuthorization = nil; revision += 1
        await coordinator.confirm(id, isCurrent: { self.authorization == captured && self.isAvailable })
        revision += 1
    }
    func recover(_ raw: String) async {
        let captured = authorization; preparedAuthorization = nil; revision += 1
        await coordinator.recover(raw, reader: receipt, isCurrent: { self.authorization == captured })
        revision += 1
    }
    func cancel() { preparedAuthorization = nil; coordinator.cancelReview(); revision += 1 }
    func next() { preparedAuthorization = nil; coordinator.next(); revision += 1 }
    func restore() { coordinator.restoreLocalPending(); revision += 1 }
    func invalidate() { preparedAuthorization = nil; coordinator.invalidate(); revision += 1 }
}

@MainActor struct CityNodeRedeemView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.cityNodeReceiptFactory) private var receiptFactory
    @StateObject private var model: CityNodeRedeemModel
    @State private var raw = ""
    @State private var showsScanner = false
    @State private var preparing = false
    @State private var confirming = false
    @State private var scannedCode: String?
    @State private var visible = false
    @State private var lifetime = UUID()
    @FocusState private var codeFocused: Bool
    init(reader: any MerchantBusinessReading, journal: any MerchantBusinessIntentStore, receipt: CityNodeRedemptionReceiptReader? = nil) {
        _model = StateObject(wrappedValue: CityNodeRedeemModel(reader: reader, journal: journal, receipt: receipt))
    }
    private var busy: Bool { preparing || confirming || model.coordinator.busy }
    var body: some View {
        Form {
            Section {
                Text("merchant.cityRedeem.instructions")
                if !model.isAvailable { Text("merchant.cityRedeem.disabled").foregroundStyle(.secondary) }
                SecureField("merchant.cityRedeem.code", text: $raw)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                    .focused($codeFocused).privacySensitive().disabled(!model.isAvailable || model.blocksAllTargets || busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.code")
                Button("merchant.cityRedeem.review") { prepare(raw) }
                    .disabled(!model.isAvailable || model.blocksAllTargets || raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.review")
                Button { showsScanner = true } label: { Label("merchant.cityRedeem.scan", systemImage: "qrcode.viewfinder") }
                    .disabled(!model.isAvailable || model.blocksAllTargets || busy || model.coordinator.review != nil)
                    .accessibilityIdentifier("merchant.cityRedeem.scan")
                if model.canRecover {
                    Button("回读原核销结果") { recover(raw) }
                        .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || model.coordinator.review != nil)
                        .accessibilityIdentifier("merchant.cityRedeem.recoverOriginal")
                }
                Text("merchant.cityRedeem.cameraConsent").font(.footnote).foregroundStyle(.secondary)
            }
            if busy { ProgressView("merchant.cityRedeem.processing") }
            if let result = model.coordinator.result {
                Section {
                    Label {
                        if result.isUnknown { Text(verbatim: CityNodeRedemptionResult.unknownMessage) }
                        else { Text(LocalizedStringKey(result.redeemed ? "merchant.cityRedeem.success" : "merchant.cityRedeem.rejected")) }
                    } icon: { Image(systemName: result.isUnknown ? "questionmark.circle" : result.redeemed ? "checkmark.circle" : "exclamationmark.circle") }
                    if !result.isUnknown {
                        Text(verbatim: result.message).textSelection(.enabled)
                            .accessibilityIdentifier("merchant.cityRedeem.serverMessage")
                    }
                    if let unverified = result.unverifiedServerMessage, !unverified.isEmpty {
                        Text(verbatim: "服务返回（尚未确认为本次回执）").font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: unverified).accessibilityIdentifier("merchant.cityRedeem.unverifiedMessage")
                    }
                    if !model.blocksAllTargets {
                        Button { raw = ""; model.next() } label: {
                            if model.coordinator.pendingScope != nil { Text(verbatim: "核销其他玩家或节点") }
                            else { Text("merchant.cityRedeem.next") }
                        }.accessibilityIdentifier("merchant.cityRedeem.next")
                    }
                }
            }
            if let pending = model.coordinator.pendingScope {
                Section {
                    if let result = model.coordinator.result, !result.isUnknown {
                        Text(verbatim: "服务已返回明确结果，但本机待办未能清除，仍保持原有阻断范围。不要重复核销；请联系平台处理。")
                    } else if pending == .legacy {
                        Text(verbatim: CityNodeRedemptionResult.legacyGuidance)
                    } else if pending == .storage {
                        Text(verbatim: "本机核销待办无法读取或保存，本次未提交。请检查本机存储并联系平台处理；不会自动清除已有待办。")
                    } else {
                        Text(verbatim: CityNodeRedemptionResult.unknownGuidance)
                        Text(verbatim: "可以核销其他玩家或节点；刷新短码、重新扫码或重新登录都不会重发同一目标。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("merchant.cityRedeem.pendingGuidance")
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
                    guard !busy, visible, model.isAvailable, !model.blocksAllTargets, scenePhase == .active else { return }
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
                guard visible, model.isAvailable, !model.blocksAllTargets, scenePhase == .active, !busy else { return }
                scannedCode = payload
            }
        }
        .onAppear { visible = true; model.resolveReceipt(receiptFactory); model.restore() }
        .onChange(of: model.coordinator.scope) { _, _ in clear() }
        .onChange(of: model.authorizationGeneration) { _, _ in clear() }
        .onChange(of: model.isAvailable) { _, available in if !available { clear() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clear() } }
        .onDisappear { visible = false; clear() }
    }
    private func recover(_ code: String) {
        guard visible, !busy, scenePhase == .active, model.canRecover else { return }
        codeFocused = false; raw = ""; preparing = true
        let captured = lifetime
        Task {
            guard visible, lifetime == captured, scenePhase == .active else { preparing = false; return }
            await model.recover(code); preparing = false
        }
    }
    private func prepare(_ code: String) {
        guard visible, model.isAvailable, !model.blocksAllTargets, !busy, scenePhase == .active else { return }
        codeFocused = false; raw = ""; preparing = true
        let captured = lifetime
        Task {
            guard visible, lifetime == captured, scenePhase == .active else { preparing = false; return }
            await model.prepare(code); preparing = false
        }
    }
    private func clear() { lifetime = UUID(); codeFocused = false; raw = ""; scannedCode = nil; showsScanner = false; model.invalidate() }
}
