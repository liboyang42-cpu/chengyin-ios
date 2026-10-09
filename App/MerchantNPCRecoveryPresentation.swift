import SwiftUI

/// Confirmation owns metadata only. It never copies or edits the composer,
/// changes a retry deadline, or manufactures a replacement request.
@MainActor struct MerchantNPCRecoveryPresentation {
    struct Confirmation: Identifiable {
        let id = UUID()
        fileprivate let owner: ObjectIdentifier
        fileprivate let scope: MerchantNPCScope
        fileprivate let namespaceBytes: [UInt8]
        fileprivate let requestID: UUID
        fileprivate let attemptCount: Int
        fileprivate let retryAt: Date?
        fileprivate let outcomeUnknown: Bool
        fileprivate let revision: Int
    }
    private(set) var confirmation: Confirmation?
    private var visible = false
    private var active = false

    mutating func appear(active: Bool) { visible = true; self.active = active; cancel() }
    mutating func sceneChanged(active: Bool) { self.active = active; cancel() }
    mutating func disappear() { visible = false; active = false; cancel() }
    mutating func cancel() { confirmation = nil }

    mutating func requestAbandon(_ expected: MerchantNPCChatCoordinator.RetryRecovery,
                                 coordinator: MerchantNPCChatCoordinator, revision: Int, sceneActive: Bool) {
        guard visible, active, sceneActive, confirmation == nil,
              let value = coordinator.retryRecovery(), value.canAbandon,
              value.requestID == expected.requestID, value.attemptCount == expected.attemptCount,
              value.retryAt == expected.retryAt, value.outcomeUnknown == expected.outcomeUnknown else { return }
        confirmation = Confirmation(owner: ObjectIdentifier(coordinator), scope: coordinator.scope,
            namespaceBytes: Array(coordinator.scope.namespace.utf8), requestID: value.requestID,
            attemptCount: value.attemptCount, retryAt: value.retryAt,
            outcomeUnknown: value.outcomeUnknown, revision: revision)
    }

    @discardableResult mutating func confirm(_ expected: Confirmation, coordinator: MerchantNPCChatCoordinator,
                                            revision: Int, sceneActive: Bool) -> Bool {
        guard confirmation?.id == expected.id, visible, active, sceneActive,
              expected.owner == ObjectIdentifier(coordinator), expected.scope == coordinator.scope,
              expected.namespaceBytes.elementsEqual(coordinator.scope.namespace.utf8), expected.revision == revision,
              let value = coordinator.retryRecovery(), value.canAbandon,
              value.requestID == expected.requestID, value.attemptCount == expected.attemptCount,
              value.retryAt == expected.retryAt, value.outcomeUnknown == expected.outcomeUnknown else { return false }
        // Synchronous one-use consumption precedes the existing local operation.
        confirmation = nil
        coordinator.abandon()
        return true
    }
}

@MainActor struct MerchantNPCRecoveryView: View {
    let coordinator: MerchantNPCChatCoordinator
    let revision: Int
    let currentRevision: () -> Int
    let retry: (UUID) -> Void
    @State private var presentation = MerchantNPCRecoveryPresentation()
    @State private var showsConfirmation = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let value = coordinator.retryRecovery(at: timeline.date) {
                VStack(alignment: .leading, spacing: 10) {
                    status(value)
                    Button("merchantNPC.retry") {
                        guard scenePhase == .active, coordinator.requestID == value.requestID, coordinator.canRetry else { return }
                        presentation.cancel()
                        retry(value.requestID)
                    }.disabled(scenePhase != .active || !coordinator.canRetry)
                        .frame(minHeight: 44).accessibilityIdentifier("merchantNPCRecovery.retry")
                    Button("merchantNPC.abandon", role: .destructive) {
                        presentation.requestAbandon(value, coordinator: coordinator, revision: currentRevision(), sceneActive: scenePhase == .active)
                        showsConfirmation = presentation.confirmation != nil
                    }.disabled(scenePhase != .active || !value.canAbandon)
                        .frame(minHeight: 44).accessibilityIdentifier("merchantNPCRecovery.abandon")
                }
            }
        }
        .confirmationDialog("merchantNPCRecovery.confirmTitle", isPresented: $showsConfirmation,
                            titleVisibility: .visible, presenting: presentation.confirmation) { confirmation in
            Button("merchantNPCRecovery.confirmAbandon", role: .destructive) {
                presentation.confirm(confirmation, coordinator: coordinator, revision: currentRevision(), sceneActive: scenePhase == .active)
            }
            Button("action.cancel", role: .cancel) { presentation.cancel() }
        } message: { _ in
            Text("merchantNPCRecovery.abandonConsequences")
        }
        .onAppear { presentation.appear(active: scenePhase == .active) }
        .onDisappear { presentation.disappear(); showsConfirmation = false }
        .onChange(of: revision) { _, _ in presentation.cancel(); showsConfirmation = false }
        .onChange(of: scenePhase) { _, phase in presentation.sceneChanged(active: phase == .active); showsConfirmation = false }
        .onChange(of: showsConfirmation) { _, shown in if !shown { presentation.cancel() } }
        .accessibilityIdentifier("merchantNPCRecovery.controls")
    }

    @ViewBuilder private func status(_ value: MerchantNPCChatCoordinator.RetryRecovery) -> some View {
        switch value.state {
        case .waitingForReply: Text("merchantNPC.pending")
        case .stoppingLocalWait: Text("npcQuick.stoppingLocalWait")
        case .cooldown(let seconds):
            if let deadline = value.retryAt {
                LabeledContent("merchantNPCRecovery.retrySeconds") { Text(verbatim: String(seconds)) }
                    // Read a stable absolute deadline instead of announcing each tick.
                    // No live-region, focus change, delayed action or automatic retry.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("merchantNPCRecovery.availableAfter"))
                    .accessibilityValue(Text(deadline, format: .dateTime.hour().minute().second()))
                    .accessibilityIdentifier("merchantNPCRecovery.countdown")
                Text("merchantNPCRecovery.explicitRetry").font(.footnote).foregroundStyle(.secondary)
            }
        case .retryAvailable:
            Text("merchantNPCRecovery.sameRequest").font(.footnote).foregroundStyle(.secondary)
        case .attemptLimitReached:
            Text("merchantNPCRecovery.limitReached").font(.footnote)
                .accessibilityIdentifier("merchantNPCRecovery.limitReached")
        case .unavailable: Text("merchantNPC.unavailable")
        }
    }
}
