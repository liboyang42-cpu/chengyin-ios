import SwiftUI

private struct ClubOwnerRefundCoordinatorKey: EnvironmentKey {
    static let defaultValue: ClubOwnerRefundCoordinator? = nil
}
extension EnvironmentValues {
    var clubOwnerRefundCoordinator: ClubOwnerRefundCoordinator? {
        get { self[ClubOwnerRefundCoordinatorKey.self] }
        set { self[ClubOwnerRefundCoordinatorKey.self] = newValue }
    }
}
@MainActor struct ClubOwnerRefundPanel: View {
    let target: ClubOwnerRefundTarget
    let identity: ClubReadIdentity?
    let sourceCanRefund: Bool
    let onReadback: () -> Void
    @Environment(\.clubOwnerRefundCoordinator) private var coordinator
    @State private var review: ClubOwnerRefundReview?
    @State private var failure: ClubOwnerRefundFailure?
    @State private var ownerID = UUID()
    private var status: ClubOwnerRefundStatus { coordinator?.state(target) ?? .init() }
    var body: some View {
        if sourceCanRefund || status.phase != .idle {
            VStack(alignment: .leading, spacing: 12) {
                Text("club.refund.title").font(.headline)
                if let coordinator, coordinator.identity == identity {
                    Text(LocalizedStringKey("club.refund.phase." + status.phase.rawValue))
                        .accessibilityIdentifier("club.refund.phase")
                    if status.inFlight { ProgressView("club.refund.working") }
                    if let receipt = status.receipt { receiptRows(receipt) }
                    if status.phase == .outcomeUnknown || status.phase == .refundRecorded {
                        Text("club.refund.noReplay").font(.footnote)
                    }
                    if status.readbackUnavailable { Text("club.refund.readbackUnavailable").accessibilityIdentifier("club.refund.readbackUnavailable") }
                    if let failure = failure ?? status.failure {
                        Text(LocalizedStringKey(failure.localizationKey)).foregroundStyle(.secondary)
                        if let message = failure.message { fact("club.refund.serverMessage", message) }
                    }
                    if sourceCanRefund, [.idle, .notSent].contains(status.phase) {
                        Button("club.refund.review") { Task { await prepare(coordinator) } }
                            .disabled(status.inFlight).accessibilityIdentifier("club.refund.review")
                    }
                    if [.acknowledged, .manualReview, .outcomeUnknown, .refundRecorded].contains(status.phase) {
                        Button("club.refund.readback") {
                            Task { await coordinator.reconcile(target); if coordinator.identity == identity { onReadback() } }
                        }.disabled(status.inFlight).accessibilityIdentifier("club.refund.readback")
                    }
                    if !coordinator.canDispatchOffline { Text("club.refund.disabled").font(.footnote).accessibilityIdentifier("club.refund.disabled") }
                } else { Text("club.refund.disabled").font(.footnote) }
                Text("club.refund.policy").font(.footnote).foregroundStyle(.secondary)
            }
            .sheet(item: $review, onDismiss: cancelPending) { pending in
                NavigationStack {
                    Form {
                        Section("club.refund.target") {
                            fact("club.refund.player", pending.evidence.displayName)
                            fact("club.refund.topic", pending.evidence.topicName)
                            fact("club.refund.ticket", pending.evidence.ticketText)
                            fact("club.refund.order", pending.evidence.orderNo)
                            LabeledContent("club.refund.registration") { Text(pending.evidence.target.registrationID, format: .number) }
                            fact("club.refund.paid", pending.evidence.paidAmountText)
                        }
                        Section {
                            Text("club.refund.scopeWarning")
                            Text("club.refund.policy")
                            if coordinator?.canDispatchOffline == true { Text("club.refund.synthetic") }
                            else { Text("club.refund.disabled") }
                            Button(role: .destructive) {
                                guard let coordinator else { return }
                                Task {
                                    await coordinator.confirm(pending)
                                    review = nil
                                    if coordinator.identity == identity { onReadback() }
                                }
                            } label: { Text("club.refund.confirm") }
                            .disabled(coordinator?.canDispatchOffline != true || status.inFlight)
                            .accessibilityIdentifier("club.refund.confirm")
                            if status.inFlight { ProgressView("club.refund.working") }
                        }
                    }
                    .navigationTitle("club.refund.reviewTitle")
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button("club.refund.cancel") { coordinator?.cancel(pending); review = nil }
                            .disabled(status.inFlight).accessibilityIdentifier("club.refund.cancel")
                    } }
                }.interactiveDismissDisabled(status.inFlight)
            }
            .onChange(of: identity) { _, _ in coordinator?.leave(ownerID: ownerID); review = nil; failure = nil }
            .onDisappear { coordinator?.leave(ownerID: ownerID) }
            .accessibilityIdentifier("club.refund.panel")
        }
    }
    private func cancelPending() { coordinator?.leave(ownerID: ownerID) }
    private func prepare(_ coordinator: ClubOwnerRefundCoordinator) async {
        failure = nil
        do {
            let pending = try await coordinator.prepare(target, ownerID: ownerID)
            guard coordinator.identity == identity, !Task.isCancelled else { coordinator.cancel(pending); return }
            review = pending
        } catch { if coordinator.identity == identity { failure = error as? ClubOwnerRefundFailure ?? .unknown } }
    }
    private func fact(_ title: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent(title) { if let value { Text(verbatim: value) } else { Text("club.refund.unknownValue") } }
    }
    private func receiptRows(_ receipt: ClubOwnerRefundReceipt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("club.refund.cancellation") { Text(LocalizedStringKey("club.refund.cancellation." + receipt.cancellation.rawValue)) }
            LabeledContent("club.refund.cash") { Text(LocalizedStringKey("club.refund.cash." + receipt.cash.rawValue)) }
            LabeledContent("club.refund.points") { Text(LocalizedStringKey("club.refund.points." + receipt.points.rawValue)) }
            if let message = receipt.message { Text(verbatim: message) }
            if receipt.scope == "PARENT_ORDER" { Text("club.refund.parentOrder") }
        }.accessibilityIdentifier("club.refund.receipt")
    }
}
