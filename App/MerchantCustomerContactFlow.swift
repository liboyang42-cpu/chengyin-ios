import SwiftUI

@MainActor private final class MerchantContactLease { var active = true }
@MainActor final class MerchantCustomerContactFlow: ObservableObject, Identifiable {
    let id = UUID()
    let selection: MerchantCustomerContactSelection
    let reader: MerchantSelectedContactReader
    let coordinator: MerchantEngagementCoordinator
    private let lease: MerchantContactLease
    @Published private(set) var revision = 0
    @Published private(set) var deviceIssue = false
    @Published private(set) var consumed = false
    @Published private(set) var consuming = false
    init(selection: MerchantCustomerContactSelection, reader: any MerchantEngagementReading,
         journal: any MerchantBusinessIntentStore, exports: any MerchantExportRecoveryStoring, current: @escaping () -> Bool) {
        self.selection = selection
        let lease = MerchantContactLease(); self.lease = lease
        let narrowed = MerchantSelectedContactReader(base: reader, selection: selection, current: { lease.active && current() })
        self.reader = narrowed; coordinator = .init(reader: narrowed, journal: journal, exportRecovery: exports)
    }
    var isCurrent: Bool { reader.scope == selection.scope }
    var canConsume: Bool {
        guard isCurrent, !consuming, let receipt = coordinator.receipt, case .contact(let contact) = receipt,
              coordinator.receiptScope == selection.scope, coordinator.receiptMerchantID == selection.merchantID,
              contact.customerID == selection.customerID, contact.purpose == selection.purpose else { return false }
        return reader.permitsDevice(.contact(selection.customerID, selection.purpose), merchantID: selection.merchantID)
    }
    func prepare() async {
        guard isCurrent, !coordinator.busy, !coordinator.locked, !consuming else { return }
        deviceIssue = false; consumed = false; revision += 1
        await coordinator.prepare(selection.command); revision += 1
        if !isCurrent { invalidate() }
    }
    func confirm(_ review: MerchantEngagementReview) async {
        guard isCurrent, review.command == selection.command else { invalidate(); return }
        revision += 1; await coordinator.confirm(review); revision += 1
        if !isCurrent { invalidate() }
    }
    func cancelReview() { coordinator.cancelReview(); revision += 1 }
    func reconcile() { if !isCurrent { invalidate() } }
    func invalidate() { lease.active = false; coordinator.invalidate(); revision += 1 }
    func consume(using delivery: any MerchantContactDelivering) async {
        guard canConsume else { return }
        consuming = true; defer { consuming = false; revision += 1 }
        do { try await coordinator.consumeContact(using: delivery); consumed = isCurrent }
        catch { deviceIssue = isCurrent }
        if !isCurrent { invalidate() }
    }
}

@MainActor struct MerchantCustomerContactSheet: View {
    @ObservedObject var flow: MerchantCustomerContactFlow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(verbatim: flow.selection.record.title).font(.headline)
                    LabeledContent("merchant.contactFlow.customer", value: String(flow.selection.customerID.rawValue))
                    Text(LocalizedStringKey("merchant.engagement.contact." + flow.selection.purpose.rawValue))
                    Text("merchant.contactFlow.privacy").font(.footnote)
                }
                if !flow.isCurrent { Text("merchant.contactFlow.stale") }
                else {
                    if flow.coordinator.busy || flow.consuming { ProgressView("merchant.loading") }
                    if let failure = flow.coordinator.failure { Text(LocalizedStringKey(failure.key)).accessibilityIdentifier("merchant.contactFlow.failure") }
                    if flow.coordinator.locked { Text("merchant.business.unknownResult") }
                    if flow.coordinator.receipt != nil {
                        Text("merchant.engagement.contactReady")
                        Button("merchant.engagement.consumeContact") {
                            Task { await flow.consume(using: MerchantContactDeviceAdapter(deviceEffectsAllowed: flow.canConsume)) }
                        }.disabled(!flow.canConsume).accessibilityIdentifier("merchant.contactFlow.consume")
                        if !flow.canConsume { Text("merchant.contactFlow.deviceUnavailable") }
                    } else {
                        Button("merchant.contactFlow.prepare") { Task { await flow.prepare() } }
                            .disabled(flow.coordinator.busy || flow.coordinator.locked || flow.consuming)
                            .accessibilityIdentifier("merchant.contactFlow.prepare")
                    }
                    if flow.consumed { Text("merchant.contactFlow.completed") }
                    if flow.deviceIssue { Text("merchant.contactFlow.deviceFailed") }
                }
            }
            .navigationTitle("merchant.contactFlow.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("merchant.contactFlow.close") { flow.invalidate(); dismiss() } } }
        }
        .sheet(item: Binding(get: { flow.coordinator.review }, set: { if $0 == nil && !flow.coordinator.busy { flow.cancelReview() } })) { review in
            MerchantEngagementReviewView(review: review,
                enabled: flow.isCurrent && flow.reader.canExecute(review.command, merchantID: flow.selection.merchantID),
                synthetic: flow.reader.isSyntheticEnabled, busy: flow.coordinator.busy,
                cancel: flow.cancelReview, confirm: { Task { await flow.confirm(review) } })
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { flow.invalidate() } }
        .onDisappear { if flow.coordinator.review == nil { flow.invalidate() } }
        .privacySensitive().accessibilityIdentifier("merchant.contactFlow.sheet")
    }
}
