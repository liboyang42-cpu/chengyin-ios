import SwiftUI

@MainActor private final class TopicSelfPlayModel: ObservableObject {
    let flow: TopicSelfPlayFlow
    @Published var revision = 0
    init(_ flow: TopicSelfPlayFlow) { self.flow = flow; flow.onChange = { [weak self] in self?.revision += 1 } }
}
@MainActor struct TopicSelfPlaySheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: TopicSelfPlayModel
    var orders: (() -> AnyView)? = nil
    var tickets: (() -> AnyView)? = nil
    init(flow: TopicSelfPlayFlow, orders: (() -> AnyView)? = nil, tickets: (() -> AnyView)? = nil) {
        _model = StateObject(wrappedValue: TopicSelfPlayModel(flow)); self.orders = orders; self.tickets = tickets
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: model.flow.topic.name).font(.headline)
                    TopicPrice(value: model.flow.topic.selfPlayPrice, label: "topic.selfPlayPrice")
                    Text("contextSelfPlay.validity")
                    Text("contextSelfPlay.paymentNotice").font(.caption)
                }
                if model.flow.pending == nil {
                    Section("contextSelfPlay.participant") {
                        TextField("contextSelfPlay.name", text: Binding(get: { model.flow.realName }, set: { model.flow.realName = $0; model.flow.changed() }))
                            .textContentType(.name).accessibilityIdentifier("contextSelfPlay.name")
                        TextField("contextSelfPlay.phone", text: Binding(get: { model.flow.phone }, set: { model.flow.phone = $0; model.flow.changed() }))
                            .keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("contextSelfPlay.phone")
                    }.disabled(!model.flow.canEdit)
                    Section {
                        if let document = model.flow.document { Link("contextSelfPlay.noticeLink", destination: document.officialURL) }
                        else { Text("contextSelfPlay.documentUnavailable").font(.caption) }
                        Toggle("contextSelfPlay.consent", isOn: Binding(get: { model.flow.consented }, set: { model.flow.consented = $0; model.flow.changed() }))
                            .disabled(!model.flow.canCreate).accessibilityIdentifier("contextSelfPlay.consent")
                        Button("contextSelfPlay.review") { model.flow.prepare() }
                            .disabled(!model.flow.canCreate).accessibilityIdentifier("contextSelfPlay.review")
                    }
                }
                if let key = model.flow.messageKey { Section { Text(LocalizedStringKey(key)).accessibilityIdentifier("contextSelfPlay.status") } }
                if model.flow.phase == .creating { ProgressView("contextSelfPlay.creating") }
                if let id = model.flow.registrationID {
                    Section {
                        LabeledContent("contextSelfPlay.order", value: String(id))
                        Button("contextSelfPlay.continuePayment") { Task { await model.flow.prepareExistingPayment() } }.disabled(model.flow.phase == .creating || model.flow.phase == .verifying || model.flow.phase == .complete || model.flow.pending?.paymentAttempted == true)
                        Button("contextSelfPlay.checkOrder") { model.flow.showReadback() }.disabled(model.flow.phase == .creating || model.flow.phase == .verifying)
                        Button("contextSelfPlay.reviewNewOrder") { Task { await model.flow.prepareNewOrderAfterClosure() } }.disabled(model.flow.phase == .creating || model.flow.phase == .verifying)
                        if let orders { NavigationLink("contextSelfPlay.orders") { orders() } }
                        if let tickets { NavigationLink("contextSelfPlay.tickets") { tickets() } }
                    }
                } else if model.flow.pending != nil, let orders {
                    NavigationLink("contextSelfPlay.orders") { orders() }
                }
            }.navigationTitle("contextSelfPlay.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { model.flow.leave(); dismiss() } } }
            .task { await model.flow.open() }
            .onDisappear { model.flow.leave() }
            .sheet(item: Binding(get: { model.flow.review }, set: { if $0 == nil { model.flow.cancelReview() } })) { review in
                NavigationStack {
                    Form {
                        Text(verbatim: model.flow.topic.name)
                        TopicPrice(value: review.price, label: "topic.selfPlayPrice")
                        Text(verbatim: review.intent.realName); Text(verbatim: review.intent.phone)
                        Text("contextSelfPlay.consentReview"); Text("contextSelfPlay.paymentNotice")
                        Link("contextSelfPlay.noticeLink", destination: review.document.officialURL)
                        Button("contextSelfPlay.confirm") { Task { await model.flow.confirm(review) } }.accessibilityIdentifier("contextSelfPlay.confirm")
                        Button("action.cancel", role: .cancel) { model.flow.cancelReview() }
                    }.navigationTitle("contextSelfPlay.review")
                }
            }
            .sheet(item: Binding(get: { model.flow.paymentReview }, set: { if $0 == nil { model.flow.cancelPaymentReview() } })) { review in
                TopicSelfPlayPaymentReviewSheet(review: review, confirm: { consent in Task { await model.flow.confirmExistingPayment(review, consented: consent) } }, cancel: model.flow.cancelPaymentReview)
            }
            .sheet(item: Binding(get: { model.flow.result }, set: { _ in })) { result in
                PaymentProviderReturnSheet(flow: result) { model.flow.closeResult($0) }
            }
        }
    }
}
@MainActor struct TopicSelfPlayUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss
    let topic: TopicDetail
    var body: some View {
        NavigationStack {
            Form {
                Text(verbatim: topic.name)
                TopicPrice(value: topic.selfPlayPrice, label: "topic.selfPlayPrice")
                Text("contextSelfPlay.validity")
                Text("contextSelfPlay.unavailable")
            }.navigationTitle("contextSelfPlay.title")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { dismiss() } } }
        }
    }
}

@MainActor private struct TopicSelfPlayPaymentReviewSheet: View {
    let review: TopicSelfPlayPaymentReview
    let confirm: (Bool) -> Void
    let cancel: () -> Void
    @State private var consented = false
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("contextSelfPlay.order", value: String(review.registrationID))
                TopicPrice(value: review.price, label: "topic.selfPlayPrice")
                Text("contextSelfPlay.sameOrder")
                Text("contextSelfPlay.paymentNotice")
                Link("contextSelfPlay.noticeLink", destination: review.document.officialURL)
                Toggle("contextSelfPlay.consent", isOn: $consented)
                Button("contextSelfPlay.continuePayment") { confirm(consented) }.disabled(!consented)
                Button("action.cancel", role: .cancel, action: cancel)
            }.navigationTitle("contextSelfPlay.review")
        }
    }
}
