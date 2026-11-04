import Foundation
import SwiftUI

@MainActor struct NativeWebhookManagementView: View {
    @ObservedObject var model: NativeWebhookViewModel
    var body: some View {
        List {
            if model.coordinator == nil {
                Section(nativeWebhookLocalized("当前不可用")) {
                    Text(nativeWebhookLocalized("频道 Webhook 管理尚未接入当前账号的真实频道、原生管理权限和事件目录。"))
                        .accessibilityIdentifier("webhook.source.unavailable")
                }
                NativeWebhookStatusSection(model: model)
            } else {
                Section {
                    Picker(nativeWebhookLocalized("集成类型"), selection: Binding(get: { model.coordinator?.family ?? .subscription }, set: { family in
                        Task { await model.switchFamily(family) }
                    })) {
                        Text(nativeWebhookLocalized("出站订阅")).tag(NativeWebhookFamily.subscription)
                        Text(nativeWebhookLocalized("入站端点")).tag(NativeWebhookFamily.endpoint)
                    }
                    .pickerStyle(.segmented).disabled(model.coordinator?.busy == true)
                    .accessibilityIdentifier("webhook.family")
                    if let context = model.coordinator?.context {
                        NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("当前频道")),value:context.binding.scope.channelID.rawValue)
                    }
                }
                NativeWebhookStatusSection(model: model)
                if model.coordinator?.pending != nil {
                    Section(nativeWebhookLocalized("原请求待核对")) {
                        Text(nativeWebhookLocalized("上次操作尚未完成结果核对。请先恢复原请求，再发起新操作。"))
                        Button(nativeWebhookLocalized("恢复原请求")) { Task { await model.openRecovery() } }
                            .disabled(!model.available || model.coordinator?.busy == true)
                            .accessibilityIdentifier("webhook.pending.recover")
                    }
                }
                if let coordinator = model.coordinator, model.available {
                    Section(coordinator.family == .subscription ? nativeWebhookLocalized("出站订阅") : nativeWebhookLocalized("入站端点")) {
                        if coordinator.resources.isEmpty && !coordinator.busy {
                            NativeChannelFlowNotice(title:Text(verbatim:nativeWebhookLocalized("当前频道暂无此类集成。")),symbol:"point.3.connected.trianglepath.dotted").accessibilityIdentifier("webhook.resources.empty")
                        }
                        ForEach(coordinator.resources) { resource in
                            NavigationLink(value: NativeWebhookDestination.resource(resource.id)) {
                                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                                    Text(resource.name).font(Theme.Font.sectionTitle).fixedSize(horizontal:false,vertical:true)
                                    Label(resource.status == .active ? nativeWebhookLocalized("已启用") : nativeWebhookLocalized("已停用"),systemImage:resource.status == .active ? "checkmark.circle":"pause.circle")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let host = resource.urlHost { Text(verbatim:host).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                                }
                            }
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.resource.\(resource.id.rawValue)")
                        }
                        if coordinator.hasMoreResources {
                            Button(nativeWebhookLocalized("加载更多")) { Task { await coordinator.load(nextPage: true) } }
                                .disabled(coordinator.busy).accessibilityIdentifier("webhook.resources.more")
                        }
                    }
                    Section {
                        Button(coordinator.family == .subscription ? nativeWebhookLocalized("新建订阅") : nativeWebhookLocalized("新建端点")) { model.edit() }.nativeChannelFlowAction()
                            .disabled(!model.canMutate).accessibilityIdentifier("webhook.resource.create")
                    }
                } else if model.coordinator?.busy == false {
                    Section { Text(nativeWebhookLocalized("请核对当前账号和频道授权后重新读取。")) }
                }
                Section {
                    Button(nativeWebhookLocalized("重新读取")) { Task { await model.coordinator?.load() } }
                        .disabled(model.coordinator?.busy == true).accessibilityIdentifier("webhook.resources.refresh")
                }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("Webhook 管理"))
        .refreshable { await model.coordinator?.load() }
        .accessibilityIdentifier("webhook.resources")
    }
}

@MainActor struct NativeWebhookResourceDetail: View {
    @ObservedObject var model: NativeWebhookViewModel
    let resourceID: NativeWebhookID
    @State private var testEvent = ""
    var body: some View {
        Form {
            NativeWebhookStatusSection(model: model)
            if let coordinator = model.coordinator, let resource = coordinator.selected,
               resource.id == resourceID, model.available {
                Section(nativeWebhookLocalized("集成详情")) {
                    NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("名称")),value:resource.name)
                    LabeledContent(nativeWebhookLocalized("状态"), value: resource.status == .active ? nativeWebhookLocalized("已启用") : nativeWebhookLocalized("已停用"))
                    NativeChannelFlowReference(label:Text(verbatim:nativeWebhookLocalized("编号")),value:resource.id.rawValue)
                    NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("当前频道")),value:resource.channelID.rawValue)
                    LabeledContent(nativeWebhookLocalized("版本"), value: String(resource.revision))
                    LabeledContent(nativeWebhookLocalized("密钥版本"), value: String(resource.keyVersion))
                    if let time = resource.updatedAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("更新时间")),value:time.rawValue) }
                }
                if coordinator.family == .subscription {
                    Section(nativeWebhookLocalized("订阅设置")) {
                        if let host = resource.urlHost { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("目标域名")),value:host) }
                        ForEach(resource.events ?? [], id: \.self) { event in Text(event).font(.caption).fixedSize(horizontal: false, vertical: true) }
                        if let failures = resource.failCount { LabeledContent(nativeWebhookLocalized("失败尝试累计"), value: String(failures)) }
                        if let error = resource.lastError { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("最近错误")),value:error) }
                        if let time = resource.lastDeliveryAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("最近投递尝试")),value:time.rawValue) }
                        NavigationLink(nativeWebhookLocalized("投递日志"), value: NativeWebhookDestination.deliveryLog)
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.deliveryLogs.open")
                    }
                    testSection(resource, coordinator: coordinator)
                } else {
                    Section(nativeWebhookLocalized("端点设置")) {
                        if let prefix = resource.tokenPrefix { LabeledContent(nativeWebhookLocalized("Token 前缀"), value: prefix) }
                        if let rate = resource.rateLimitPerMinute { LabeledContent(nativeWebhookLocalized("每分钟上限"), value: String(rate)) }
                        if let ips = resource.allowedIPs {
                            Text(ips.isEmpty ? nativeWebhookLocalized("未设置 IP 限制") : ips.joined(separator: "\n"))
                        }
                        if let time = resource.lastCalledAt { NativeChannelFlowFact(label:Text(verbatim:nativeWebhookLocalized("最近调用")),value:time.rawValue) }
                        NavigationLink(nativeWebhookLocalized("入站日志"), value: NativeWebhookDestination.inboundLog)
                            .disabled(coordinator.busy)
                            .accessibilityIdentifier("webhook.inboundLogs.open")
                    }
                }
                Section(nativeWebhookLocalized("管理操作")) {
                    Button(nativeWebhookLocalized("编辑")) { model.edit(resource) }
                        .accessibilityIdentifier("webhook.resource.edit")
                    Button(resource.status == .active ? nativeWebhookLocalized("停用") : nativeWebhookLocalized("启用")) {
                        model.setActive(resource.status != .active, resource: resource)
                    }.accessibilityIdentifier("webhook.resource.toggle")
                    Button(coordinator.family == .subscription ? nativeWebhookLocalized("轮换签名密钥") : nativeWebhookLocalized("轮换 Token 和签名密钥")) {
                        model.action(.rotate, resource: resource)
                    }.accessibilityIdentifier("webhook.resource.rotate")
                    Button(nativeWebhookLocalized("删除集成"), role: .destructive) { model.action(.delete, resource: resource) }
                        .accessibilityIdentifier("webhook.resource.delete")
                }
                .disabled(!model.canMutate)
                if coordinator.pending != nil {
                    Section { Button(nativeWebhookLocalized("恢复原请求")) { Task { await model.openRecovery() } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.detail.recover") }
                }
                Section {
                    Button(nativeWebhookLocalized("重新读取详情")) { Task { await coordinator.select(resourceID) } }
                        .disabled(coordinator.busy).accessibilityIdentifier("webhook.detail.refresh")
                }
            } else if model.coordinator?.busy == false {
                Section { Text(nativeWebhookLocalized("详情尚不可用，请返回列表重新核对当前资源。")) }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(nativeWebhookLocalized("集成详情"))
        .task(id: resourceID) { await model.coordinator?.select(resourceID) }
        .accessibilityIdentifier("webhook.detail")
    }
    @ViewBuilder private func testSection(_ resource: NativeWebhookResource, coordinator: NativeWebhookCoordinator) -> some View {
        Section(nativeWebhookLocalized("测试投递")) {
            if let options = coordinator.context?.eventCatalogue.options {
                let subscribed = options.filter { resource.events?.contains($0.id) == true }
                Picker(nativeWebhookLocalized("测试事件"), selection: $testEvent) {
                    Text(nativeWebhookLocalized("请选择事件")).tag("")
                    ForEach(subscribed) { option in Text(option.title).tag(option.id) }
                }.accessibilityIdentifier("webhook.test.event")
                Text(nativeWebhookLocalized("入队成功仍需查看原投递日志，不能据此确认送达。")).font(.footnote).foregroundStyle(.secondary)
                Button(nativeWebhookLocalized("请求测试事件入队")) { model.action(.test(eventType: testEvent), resource: resource) }
                    .disabled(!model.canMutate || resource.status != .active || !subscribed.contains(where: { $0.id == testEvent }))
                    .accessibilityIdentifier("webhook.test.prepare")
            } else {
                Text(nativeWebhookLocalized("当前事件目录不可用，暂不能选择或测试事件。"))
                    .accessibilityIdentifier("webhook.events.unavailable")
            }
        }
    }
}
