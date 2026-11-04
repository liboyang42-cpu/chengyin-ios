import Foundation
import SwiftUI

@MainActor struct NativeWebhookDeliveryLogView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var filter: NativeWebhookDeliveryState?
    @State private var includePayload = false
    var body: some View {
        List {
            if let coordinator = model.coordinator, model.available, let resource = coordinator.selected {
                Section(nativeWebhookLocalized("筛选")) {
                    Picker(nativeWebhookLocalized("投递状态"), selection: $filter) {
                        Text(nativeWebhookLocalized("全部状态")).tag(Optional<NativeWebhookDeliveryState>.none)
                        ForEach(NativeWebhookDeliveryState.allCases, id: \.rawValue) { state in
                            Text(nativeWebhookLocalized(NativeWebhookPresentation.delivery(state))).tag(Optional(state))
                        }
                    }.accessibilityIdentifier("webhook.deliveryLogs.filter")
                    Toggle(nativeWebhookLocalized("读取公开事件内容"), isOn: $includePayload)
                        .accessibilityIdentifier("webhook.deliveryLogs.includePayload")
                    if includePayload { Text(nativeWebhookLocalized("仅回读服务端当前仍允许的原事件快照。")) }
                }.disabled(coordinator.busy)
                NativeWebhookStatusSection(model: model)
                Section(nativeWebhookLocalized("投递记录")) {
                    if coordinator.deliveries.isEmpty && !coordinator.busy {
                        NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized("当前筛选没有投递记录。")),symbol:"tray").accessibilityIdentifier("webhook.deliveryLogs.empty")
                    }
                    ForEach(coordinator.deliveries) { delivery in
                        VStack(alignment: .leading, spacing: Theme.Space.s3) {
                            Label(nativeWebhookLocalized(NativeWebhookPresentation.delivery(delivery.state)),systemImage:delivery.state == .unknown ? "clock.arrow.circlepath":"arrow.up.doc").font(Theme.Font.sectionTitle)
                            NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("投递编号")),value:delivery.deliveryID.rawValue)
                            NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("事件编号")),value:delivery.eventID)
                            Text(delivery.eventType).font(.caption).fixedSize(horizontal: false, vertical: true)
                            LabeledContent(nativeWebhookLocalized("尝试次数"), value: String(delivery.attempt))
                            if let time = delivery.createdAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("记录时间")),value:time.rawValue) }
                            if let code = delivery.reason { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("原因")),value:code) }
                            if let status = delivery.httpStatus { LabeledContent(nativeWebhookLocalized("HTTP 状态"), value: String(status)) }
                            if let latency = delivery.latencyMilliseconds { LabeledContent(nativeWebhookLocalized("耗时（毫秒）"), value: String(latency)) }
                            if let time = delivery.nextRetryAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("下次重试")),value:time.rawValue) }
                            if delivery.state == .unknown {
                                Text(nativeWebhookLocalized("远端是否已接收尚未确认。此记录不会自动重新发送。"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if includePayload, let payload = delivery.payload {
                                DisclosureGroup(nativeWebhookLocalized("原公开事件快照")) {
                                    Text(payloadText(payload)).font(.caption.monospaced())
                                        .privacySensitive().textSelection(.disabled)
                                }.accessibilityIdentifier("webhook.delivery.payload.\(delivery.id.rawValue)")
                            }
                            if delivery.offersExplicitRetry {
                                Button(nativeWebhookLocalized("重试原投递")) {
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
                        Button(nativeWebhookLocalized("加载更多")) { Task { await read(nextPage: true) } }
                            .disabled(coordinator.busy).accessibilityIdentifier("webhook.deliveryLogs.more")
                    }
                }
                Section {
                    Button(nativeWebhookLocalized("重新读取日志")) { Task { await read() } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.deliveryLogs.refresh")
                }
            } else {
                Section { Text(nativeWebhookLocalized("当前频道或集成详情已失效，请返回列表重新核对。")) }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("投递日志"))
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
            return nativeWebhookLocalized("事件内容暂不可显示。")
        }
        return text
    }
}
