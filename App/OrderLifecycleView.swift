import SwiftUI

@MainActor final class OrderLifecycleScreenModel: ObservableObject {
    let coordinator: OrderLifecycleCoordinator
    @Published private(set) var revision = 0
    init(coordinator: OrderLifecycleCoordinator) { self.coordinator = coordinator }
    func load(id: Int) async { revision += 1; await coordinator.load(id: id); revision += 1 }
    func prepare(_ action: OrderLifecycleAction, orderID: Int) { coordinator.prepare(action, orderID: orderID); revision += 1 }
    func dismiss() { coordinator.dismissReview(); revision += 1 }
    func closePayment() { coordinator.closePaymentReturn(); revision += 1 }
    func invalidate() { coordinator.becameInactive(); revision += 1 }
    func confirm(_ id: UUID) async { revision += 1; await coordinator.confirm(reviewID: id); revision += 1 }
}

/// A retained session-owned coordinator is injected; no view constructs a live writer.
@MainActor struct OrderLifecycleView: View {
    let id: Int
    @StateObject private var model: OrderLifecycleScreenModel
    @Environment(\.scenePhase) private var phase
    init(id: Int, coordinator: OrderLifecycleCoordinator) {
        self.id = id; _model = StateObject(wrappedValue: OrderLifecycleScreenModel(coordinator: coordinator))
    }
    private var coordinator: OrderLifecycleCoordinator { model.coordinator }
    var body: some View {
        List {
            if coordinator.isOfflineExample { Text("orderLifecycle.offline").font(.footnote).accessibilityIdentifier("orderLifecycle.offline") }
            if let issue = coordinator.issue {
                Section {
                    Label {
                        if let serverMessage = coordinator.serverMessage, !serverMessage.isEmpty { Text(verbatim: serverMessage) }
                        else { Text(LocalizedStringKey("orderLifecycle.issue." + issue.rawValue)) }
                    } icon: { Image(systemName: "exclamationmark.triangle") }
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("orderLifecycle.issue")
                }
            }
            if coordinator.accountID == nil { Text("orderLifecycle.issue.login") }
            else if coordinator.isLoading { ProgressView("orderLifecycle.loading") }
            else if let detail = coordinator.detail, detail.id == id {
                summary(detail)
                payment(detail)
                timeline(detail)
                refund(detail)
                actions(detail)
                Section {
                    NavigationLink { OrderPassPreviewView(orderID: id, coordinator: coordinator) } label: {
                        Label("orderLifecycle.pass.title", systemImage: "ticket")
                    }.accessibilityIdentifier("orderLifecycle.pass.open")
                }
            }
            Section { Text("orderLifecycle.production.caution").font(.footnote).foregroundStyle(.secondary) }
        }
        .listStyle(.insetGrouped)
        .appNavigationTitle("orderLifecycle.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.load(id: id) } } label: { Label("orderLifecycle.refresh", systemImage: "arrow.clockwise") }
                    .disabled(coordinator.isLoading || coordinator.accountID == nil)
                    .accessibilityIdentifier("orderLifecycle.refresh")
            }
        }
        .task(id: coordinator.scope) { await model.load(id: id) }
        .refreshable { await model.load(id: id) }
        .onDisappear { model.dismiss() }
        .onChange(of: phase) { _, value in
            if value != .active { model.invalidate() }
            else if !coordinator.isWaitingForPaymentProvider && coordinator.paymentReturn == nil { Task { await model.load(id: id) } }
        }
        .sheet(item: Binding(get: { coordinator.review }, set: { if $0 == nil { model.dismiss() } })) { review in
            OrderLifecycleReviewView(review: review, canSimulate: coordinator.canSimulate, canDispatch: coordinator.canDispatch,
                confirm: { Task { await model.confirm(review.id) } }, close: model.dismiss)
        }
        .sheet(item: Binding(get: { coordinator.paymentReturn }, set: { if $0 == nil { model.closePayment() } })) { flow in
            PaymentProviderReturnSheet(flow: flow) { _ in model.closePayment() }
        }
        .accessibilityIdentifier("orderLifecycle.detail")
    }
    private func summary(_ detail: OrderLifecycleDetail) -> some View {
        let state = detail.summary()
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                Label(LocalizedStringKey("orderLifecycle.state." + state.state.rawValue), systemImage: "ticket")
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("orderLifecycle.state")
                if let title = detail.title, !title.isEmpty { Text(verbatim: title).font(.title2.bold()) }
                else { Text("orderLifecycle.untitled").font(.title2.bold()) }
                if let reason = state.serverReason { Text(verbatim: reason).foregroundStyle(.secondary) }
                else { Text(LocalizedStringKey(state.explanationKey)).foregroundStyle(.secondary) }
            }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            OrderLifecycleField(label: "orderLifecycle.number", value: detail.registrationNumber)
            OrderLifecycleField(label: "orderLifecycle.ticket", value: detail.ticketName)
            LabeledContent("orderLifecycle.amount") { AmountLabel(amount: detail.payableAmount) }
        }
    }
    private func payment(_ detail: OrderLifecycleDetail) -> some View {
        let observation = OrderPaymentObservation(payment: detail.paymentStatus, registration: detail.registrationStatus)
        return Section("orderLifecycle.payment.title") {
            Text(LocalizedStringKey("orderLifecycle.payment." + observation.rawValue))
                .accessibilityIdentifier("orderLifecycle.payment.observation")
            Text("orderLifecycle.payment.caution").font(.footnote).foregroundStyle(.secondary)
            OrderLifecycleField(label: "orderLifecycle.payment.deadline", value: detail.payExpireTime)
        }
    }
    private func timeline(_ detail: OrderLifecycleDetail) -> some View {
        Section("orderLifecycle.timeline.title") {
            ForEach(detail.timeline()) { row in
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(row.labelKey))
                        if let time = row.time { Text(verbatim: time).font(.caption).foregroundStyle(.secondary) }
                    }.fixedSize(horizontal: false, vertical: true)
                } icon: { Image(systemName: row.done ? "checkmark.circle" : "clock").accessibilityHidden(true) }
                    .accessibilityIdentifier("orderLifecycle.timeline." + row.id)
            }
            Text("orderLifecycle.timeline.zone").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func refund(_ detail: OrderLifecycleDetail) -> some View {
        if detail.refundApplication != nil || detail.refundReason != nil || detail.refundDeadline != nil {
            Section("orderLifecycle.refund.title") {
                OrderLifecycleField(label: "orderLifecycle.refund.reason", value: detail.refundReason)
                OrderLifecycleField(label: "orderLifecycle.refund.deadline", value: detail.refundDeadline)
                if let amount = detail.refundApplication?.amount { LabeledContent("orderLifecycle.refund.amount") { AmountLabel(amount: amount) } }
                Text("orderLifecycle.refund.caution").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func actions(_ detail: OrderLifecycleDetail) -> some View {
        Section("orderLifecycle.actions") {
            ForEach(OrderLifecycleAction.allCases, id: \.self) { action in
                if OrderLifecycleCoordinator.isReviewable(action, detail: detail) {
                    Button { model.prepare(action, orderID: id) } label: { Text(LocalizedStringKey("orderLifecycle.review." + action.rawValue)) }
                        .accessibilityIdentifier("orderLifecycle.review." + action.rawValue)
                        .disabled(coordinator.isAttemptBlocking(action, orderID: detail.id))
                }
            }
            if let attempt = coordinator.attempt(orderID: detail.id) {
                switch attempt {
                case .submitted: ProgressView("orderLifecycle.attempt.submitted")
                case .outcomeUnknown: Text("orderLifecycle.attempt.unknown").accessibilityIdentifier("orderLifecycle.attempt.unknown")
                case .acknowledged:
                    Text("orderLifecycle.production.acknowledged")
                    if let message = coordinator.serverMessage { Text(verbatim: message) }
                case .paymentObserved(_, let observation):
                    Text(LocalizedStringKey("orderLifecycle.payment." + observation.rawValue))
                case .responseReceived(_, let observation):
                    if let message = coordinator.serverMessage { Text(verbatim: message) }
                    Text("orderLifecycle.attempt.received").accessibilityIdentifier("orderLifecycle.attempt.received")
                    OrderLifecycleField(label: "orderLifecycle.attempt.cancellation", value: observation.cancellationStatus)
                    OrderLifecycleField(label: "orderLifecycle.attempt.cash", value: observation.cashRefundStatus)
                    OrderLifecycleField(label: "orderLifecycle.attempt.points", value: observation.pointsRefundStatus)
                }
            }
        }
    }
}

struct OrderLifecycleField: View {
    let label: LocalizedStringKey
    let value: String?
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        if let value, !value.isEmpty {
            if size.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { Text(label).foregroundStyle(.secondary); Text(verbatim: value) }
                    .fixedSize(horizontal: false, vertical: true)
            } else { LabeledContent(label) { Text(verbatim: value).fixedSize(horizontal: false, vertical: true) } }
        }
    }
}

@MainActor private struct OrderLifecycleReviewView: View {
    let review: OrderLifecycleReview
    let canSimulate: Bool
    let canDispatch: Bool
    let confirm: () -> Void
    let close: () -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LocalizedStringKey("orderLifecycle.review." + review.action.rawValue)).font(.headline)
                    OrderLifecycleField(label: "orderLifecycle.number", value: review.detail.registrationNumber)
                    LabeledContent("orderLifecycle.amount") { AmountLabel(amount: review.detail.payableAmount) }
                    OrderLifecycleField(label: "orderLifecycle.refund.reason", value: review.detail.refundReason)
                    OrderLifecycleField(label: "orderLifecycle.refund.deadline", value: review.detail.refundDeadline)
                }
                Section {
                    Text("orderLifecycle.review.snapshot")
                    Text("orderLifecycle.refund.caution")
                    Text("orderLifecycle.production.caution").font(.footnote).foregroundStyle(.secondary)
                    if canDispatch {
                        Button(LocalizedStringKey("orderLifecycle.production.confirm." + review.action.rawValue), action: confirm)
                            .accessibilityIdentifier("orderLifecycle.review.confirmProduction")
                    } else if canSimulate && review.action != .payment {
                        Button("orderLifecycle.review.simulate", action: confirm).accessibilityIdentifier("orderLifecycle.review.confirmFixture")
                    } else {
                        Button("orderLifecycle.review.disabled", action: {}).disabled(true).accessibilityIdentifier("orderLifecycle.review.disabled")
                    }
                }
            }
            .appNavigationTitle("orderLifecycle.review.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("orderLifecycle.review.close", action: close).accessibilityIdentifier("orderLifecycle.review.close") } }
            .accessibilityIdentifier("orderLifecycle.review.sheet")
        }
    }
}
