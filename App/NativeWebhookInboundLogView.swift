import Foundation
import SwiftUI

@MainActor struct NativeWebhookInboundLogView: View {
    @ObservedObject var model: NativeWebhookViewModel
    @State private var filter: NativeWebhookInboundState?
    var body: some View {
        List {
            if let coordinator = model.coordinator, model.available, coordinator.selected != nil {
                Section(nativeWebhookLocalized("筛选")) {
                    Picker(nativeWebhookLocalized("接收结果"), selection: $filter) {
                        Text(nativeWebhookLocalized("全部状态")).tag(Optional<NativeWebhookInboundState>.none)
                        ForEach(NativeWebhookInboundState.allCases, id: \.rawValue) { state in
                            Text(nativeWebhookLocalized(NativeWebhookPresentation.inbound(state))).tag(Optional(state))
                        }
                    }
                    .disabled(coordinator.busy).accessibilityIdentifier("webhook.inboundLogs.filter")
                }
                NativeWebhookStatusSection(model: model)
                Section(nativeWebhookLocalized("接收记录")) {
                    if coordinator.inboundLogs.isEmpty && !coordinator.busy {
                        NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized("当前筛选没有接收记录。")),symbol:"tray").accessibilityIdentifier("webhook.inboundLogs.empty")
                    }
                    ForEach(coordinator.inboundLogs) { log in
                        VStack(alignment: .leading, spacing: Theme.Space.s3) {
                            Label(nativeWebhookLocalized(NativeWebhookPresentation.inbound(log.state)),systemImage:log.state == .unknown ? "clock.arrow.circlepath":"arrow.down.doc").font(Theme.Font.sectionTitle)
                            NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("记录编号")),value:log.id.rawValue)
                            if let time = log.createdAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("接收时间")),value:time.rawValue) }
                            if let code = log.reason { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("原因")),value:code) }
                            if let id = log.messageID { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("原消息编号")),value:id.rawValue) }
                            if let time = log.createTime { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("原消息时间")),value:time.rawValue) }
                            if log.state == .unknown {
                                Text(nativeWebhookLocalized("原消息结果尚未确认。请重新读取日志核对，不会创建另一条消息。"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical,Theme.Space.s2)
                        .accessibilityIdentifier("webhook.inbound.\(log.id.rawValue)")
                    }
                    if coordinator.hasMoreLogs {
                        Button(nativeWebhookLocalized("加载更多")) { Task { await read(nextPage: true) } }
                            .disabled(coordinator.busy).accessibilityIdentifier("webhook.inboundLogs.more")
                    }
                }
                Section {
                    Button(nativeWebhookLocalized("重新读取日志")) { Task { await read() } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.inboundLogs.refresh")
                }
            } else {
                Section { Text(nativeWebhookLocalized("当前频道或集成详情已失效，请返回列表重新核对。")) }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("入站日志"))
        .task { await read() }
        .onChange(of: filter) { _ in Task { await read() } }
        .refreshable { await read() }
        .accessibilityIdentifier("webhook.inboundLogs")
    }
    private func read(nextPage: Bool = false) async {
        await model.coordinator?.logs(nextPage: nextPage, inboundFilter: filter)
    }
}
