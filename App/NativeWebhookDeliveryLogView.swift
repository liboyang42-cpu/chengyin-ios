import Foundation
import SwiftUI

@MainActor struct NativeWebhookDeliveryLogView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var filter: NativeWebhookDeliveryState?
    @State private var includePayload = false
    var body: some View {
        List {
            if let coordinator = model.coordinator, model.available, let resource = coordinator.selected {
                Section {
                    Picker(nativeWebhookLocalized("d7.webhook.field.status"), selection: $filter) {
                        Text(nativeWebhookLocalized("d7.webhook.filter.all")).tag(Optional<NativeWebhookDeliveryState>.none)
                        ForEach(NativeWebhookDeliveryState.allCases, id: \.rawValue) { state in
                            Text(nativeWebhookDeliveryText(state)).tag(Optional(state))
                        }
                    }.accessibilityIdentifier("webhook.deliveryLogs.filter")
                    Toggle(nativeWebhookLocalized("d7.webhook.deliveries.showContent"), isOn: $includePayload)
                        .accessibilityIdentifier("webhook.deliveryLogs.includePayload")
                }.disabled(coordinator.busy)
                NativeWebhookStatusSection(model: model)
                Section {
                    if coordinator.deliveries.isEmpty && !coordinator.busy {
                        ContentUnavailableView(nativeWebhookLocalized("d7.webhook.deliveries.empty"), systemImage: "tray")
                            .accessibilityIdentifier("webhook.deliveryLogs.empty")
                    }
                    ForEach(coordinator.deliveries) { delivery in
                        VStack(alignment: .leading, spacing: Theme.Space.s2) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(nativeWebhookDeliveryText(delivery.state), systemImage: delivery.state == .unknown ? "clock.arrow.circlepath" : "arrow.up.doc")
                                    .font(Theme.Font.sectionTitle)
                                Spacer(minLength: Theme.Space.s2)
                                if let time = delivery.createdAt {
                                    Text(time.date, format: .dateTime.month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            Text(verbatim: delivery.eventType).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            LabeledContent(nativeWebhookLocalized("d7.webhook.deliveries.attempts"), value: String(delivery.attempt))
                            if let code = delivery.reason { LabeledContent(nativeWebhookLocalized("d7.webhook.field.reason"), value: code) }
                            if let status = delivery.httpStatus { LabeledContent(nativeWebhookLocalized("d7.webhook.deliveries.responseCode"), value: String(status)) }
                            if let latency = delivery.latencyMilliseconds {
                                LabeledContent(nativeWebhookLocalized("d7.webhook.deliveries.responseTime"), value: String(format: nativeWebhookLocalized("d7.webhook.deliveries.ms %lld"), latency))
                            }
                            if let time = delivery.nextRetryAt { NativeWebhookTimeRow(label: nativeWebhookLocalized("d7.webhook.deliveries.nextRetry"), time: time) }
                            if includePayload, let payload = delivery.payload {
                                DisclosureGroup(nativeWebhookLocalized("d7.webhook.deliveries.content")) {
                                    Text(payloadText(payload)).font(.caption.monospaced())
                                        .privacySensitive().textSelection(.disabled)
                                }.accessibilityIdentifier("webhook.delivery.payload.\(delivery.id.rawValue)")
                            }
                            if delivery.offersExplicitRetry {
                                Button(nativeWebhookLocalized("d7.webhook.deliveries.retry")) {
                                    model.action(.retry(deliveryID: delivery.deliveryID), resource: resource, delivery: delivery)
                                }
                                .disabled(!model.canMutate || resource.status != .active)
                                .accessibilityIdentifier("webhook.delivery.retry.\(delivery.id.rawValue)")
                            }
                        }
                        .padding(.vertical,Theme.Space.s2)
                        .accessibilityIdentifier("webhook.delivery.\(delivery.id.rawValue)")
                    }
                    if coordinator.hasMoreLogs {
                        Button(nativeWebhookLocalized("d7.webhook.loadMore")) { Task { await read(nextPage: true) } }
                            .disabled(coordinator.busy).accessibilityIdentifier("webhook.deliveryLogs.more")
                    }
                }
                Section {
                    Button(nativeWebhookLocalized("d7.webhook.reload")) { Task { await read() } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.deliveryLogs.refresh")
                }
            } else {
                ContentUnavailableView(nativeWebhookLocalized("d7.webhook.detail.loadFailed"), systemImage: "exclamationmark.circle",
                    description: Text(verbatim: nativeWebhookLocalized("d7.webhook.goBack")))
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("d7.webhook.deliveries.title"))
        .task { await read() }
        .onChange(of: filter) { _ in Task { await read() } }
        .onChange(of: includePayload) { _ in Task { await read() } }
        .refreshable { await read() }
        .accessibilityIdentifier("webhook.deliveryLogs")
    }
    private func read(nextPage: Bool = false) async {
        await model.coordinator?.logs(nextPage: nextPage, deliveryFilter: filter, includePayload: includePayload)
    }
    private func payloadText(_ payload: NativeWebhookJSON) -> String {
        guard let data = try? NativeWebhookHTTPService.encoded(payload), let text = String(data: data, encoding: .utf8) else {
            return nativeWebhookLocalized("d7.webhook.deliveries.contentUnavailable")
        }
        return text
    }
}
