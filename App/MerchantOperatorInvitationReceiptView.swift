import SwiftUI

@MainActor final class MerchantOperatorInvitationReceiptModel: ObservableObject {
    let presentationID: UUID
    @Published private(set) var revealed = false
    @Published private(set) var revision = 0
    @Published private(set) var busy = false
    @Published private(set) var issue: String?
    private var validatedAccess = false
    private var readGeneration = UUID()
    private(set) var active = true
    private weak var owner: MerchantBusinessViewModel?
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    init(owner: MerchantBusinessViewModel, presentationID: UUID,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.owner = owner; self.presentationID = presentationID; self.now = now; self.uptime = uptime
    }
    var metadata: MerchantOperatorInvitationPresentation? {
        guard active, let owner, let value = owner.coordinator.operatorInvitation, value.id == presentationID,
              owner.coordinator.reader.isConfigured, owner.coordinator.reader.scope == value.scope,
              owner.coordinator.reader.authorizationGeneration == value.authorizationGeneration,
              owner.coordinator.reader.canExecute(.inviteOperator(role: value.roleCode), merchantID: value.merchantID) else { return nil }
        return value
    }
    var canReveal: Bool {
        active && owner?.coordinator.operatorInvitationIsCurrent(id: presentationID, now: now(), uptime: uptime()) == true
    }
    var visibleCode: String? {
        guard active, revealed, validatedAccess else { return nil }
        return owner?.coordinator.operatorInvitationCode(id: presentationID, now: now(), uptime: uptime())
    }
    @discardableResult func reveal() async -> Bool {
        guard !busy else { return false }
        guard canReveal, let owner else { retire(); return false }
        let request = UUID(); readGeneration = request
        busy = true; revealed = false; validatedAccess = false; issue = nil
        defer { if readGeneration == request { busy = false } }
        do {
            // Existing read authority only. No invitation is issued or retried here.
            let access = try await owner.coordinator.reader.access()
            guard active, readGeneration == request, !Task.isCancelled, canReveal,
                  owner.coordinator.operatorInvitationAccessMatches(id: presentationID, access: access) else {
                if active, readGeneration == request { retire() }; return false
            }
            validatedAccess = true; revealed = true; return true
        } catch {
            guard active, readGeneration == request else { return false }
            guard !Task.isCancelled, canReveal else { retire(); return false }
            let failure = error as? MerchantBusinessFailure
            if error is CancellationError || failure == .denied || failure == .stale || failure == .disabled ||
                error as? APIError == .unauthorized || error as? APIError == .notConfigured {
                retire(); return false
            }
            issue = "merchant.operatorInvite.accessFailed"; return false
        }
    }
    func hide() { readGeneration = UUID(); busy = false; validatedAccess = false; revealed = false }
    func tick() {
        guard active else { return }
        guard let metadata else { retire(); return }
        if !metadata.privacyLifetimeIsActive(now: now(), uptime: uptime()) || (metadata.hasValidReceipt && !canReveal) { retire(); return }
        revision &+= 1
    }
    func retire() {
        guard active else { return }
        active = false; readGeneration = UUID(); busy = false; validatedAccess = false; revealed = false
        owner?.objectWillChange.send()
        owner?.coordinator.retireOperatorInvitation(id: presentationID)
        revision &+= 1
    }
}

/// Reveals only the existing acknowledged receipt. No URL origin, QR, clipboard
/// API, share sheet, persisted token or mutation is created by this view.
@MainActor struct MerchantOperatorInvitationReceiptView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: MerchantOperatorInvitationReceiptModel
    init(owner: MerchantBusinessViewModel, presentationID: UUID) {
        _model = StateObject(wrappedValue: .init(owner: owner, presentationID: presentationID))
    }
    var body: some View {
        Group {
            if let metadata = model.metadata {
                VStack(alignment: .leading, spacing: 10) {
                    Text("merchant.operatorInvite.title").font(.headline)
                    LabeledContent("merchant.business.storeID", value: String(metadata.merchantID))
                    if let name = metadata.merchantName { Text(verbatim: name) }
                    LabeledContent("merchant.business.role", value: metadata.roleName ?? metadata.roleCode)
                    if let inviteID = metadata.inviteID { LabeledContent("merchant.operatorInvite.identifier", value: String(inviteID)) }
                    if let expiry = metadata.expiresAtText { LabeledContent("merchant.operatorInvite.expires", value: expiry) }
                    if metadata.hasValidReceipt {
                        Text("merchant.operatorInvite.warning").font(.footnote).foregroundStyle(.secondary)
                        if let code = model.visibleCode {
                            Text(verbatim: code).font(.system(.body, design: .monospaced))
                                .textSelection(.enabled).privacySensitive()
                                .accessibilityIdentifier("merchant.operatorInvite.code")
                            Button("merchant.operatorInvite.hide") { model.hide() }
                                .accessibilityIdentifier("merchant.operatorInvite.hide")
                        } else {
                            Button("merchant.operatorInvite.reveal") {
                                guard scenePhase == .active else { model.retire(); return }
                                Task { _ = await model.reveal() }
                            }.disabled(!model.canReveal || model.busy).accessibilityIdentifier("merchant.operatorInvite.reveal")
                        }
                        Text("merchant.operatorInvite.recipientInstructions").font(.footnote)
                        Text("merchant.operatorInvite.memoryLifetime").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("merchant.operatorInvite.unavailable").font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.busy { ProgressView("merchant.operatorInvite.checkingAccess") }
                    if let issue = model.issue { Text(LocalizedStringKey(issue)).font(.footnote).foregroundStyle(.secondary) }
                    Button("merchant.operatorInvite.close") { model.retire() }
                        .accessibilityIdentifier("merchant.operatorInvite.close")
                }
            }
        }
        .task {
            guard scenePhase == .active else { model.retire(); return }
            while model.active && !Task.isCancelled {
                model.tick()
                guard model.active else { break }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.retire() } }
        .onDisappear { model.retire() }
    }
}
