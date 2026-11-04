import SwiftUI

@MainActor struct NativeChannelAuditEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelAuditFlow?
    @State private var flow: NativeChannelAuditFlow?
    @State private var unavailable = false
    @State private var generation = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow, flow.isCurrent {
                List {
                    if flow.source == .lifecycle {
                        Section {
                            Text("原 im_channel_op_log 生命周期日志，与治理审计链是不同来源。此处不声称 hash 链或三路锚点证明，也不把原日志编号当治理 action_id。")
                        }
                        ForEach(flow.operations) { row in
                            Section(row.action) {
                                NativeChannelFlowFact(label:Text("原日志编号"),value:row.id)
                                NativeChannelFlowFact(label:Text("频道"),value:row.channelID)
                                if let value = row.fromStatus { LabeledContent("原 from_status", value: String(value)) }
                                if let value = row.toStatus { LabeledContent("原 to_status", value: String(value)) }
                                if let actor = row.operatorID { NativeChannelFlowFact(label:Text("原 operator_id"),value:actor) }
                                else { Text("原记录未提供操作成员编号") }
                                if let request = row.requestID { NativeChannelFlowReference(label:Text("请求编号"),value:request) }
                                Text("原 create_time：\(row.createdAt)")
                                if let reason = row.reason { Text(reason).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    } else {
                    Section {
                        Text("仅显示原审计源允许的快照。原链验证不等于外部锚点或历史补证。")
                        Button("验证原审计链") { Task { await flow.verifyOriginalChain() } }.disabled(!flow.canVerify)
                        if let proof = flow.verification {
                            Text(proof.chainOK ? "当前原链校验一致" : "未能确认完整原审计链")
                            LabeledContent("已核对原记录", value: String(proof.checkedRows))
                            LabeledContent("无原链证明记录", value: String(proof.unprovenOriginalRows))
                            NativeChannelFlowFact(label:Text("核对至原记录"),value:proof.verifiedThroughOriginalID)
                            NativeChannelFlowReference(label:Text("原链头"),value:proof.headHash)
                            if !proof.linkedProjectionOK { Text("原链不一致，未显示相关快照。") }
                            if proof.frozen { Text("原审计链写入已冻结；此页面不提供解除冻结操作。") }
                            if let anchors = proof.anchorEvidence {
                                Text(proof.externallyAnchored ? "同一原链头的三路记录齐全（弱等价锚点）" : "此原链头尚无完整三路锚点")
                                ForEach(anchors.channels, id: \.channel) { item in
                                    NativeChannelFlowFact(label:Text(verbatim:item.channel),value:item.state)
                                }
                                Text("OSS 对象读回、SMTP 服务器接受、后台页面截图存档分别计证。SMTP 接受不等于收件人收到；页面存档不等于外部接收。UNKNOWN 不算完成，亦非 WORM 保证。")
                            } else {
                                Text("未提供外部锚点。")
                            }
                            Text("旧记录不会被自动补成当时的证明。")
                        }
                    }
                    ForEach(flow.rows) { row in
                        Section(row.action) {
                            NativeChannelFlowFact(label:Text("记录"),value:row.id)
                            NativeChannelFlowFact(label:Text("频道"),value:row.channelID)
                            NativeChannelFlowFact(label:Text("原主体类型"),value:row.actorType)
                            if let actor = row.actorID { NativeChannelFlowFact(label:Text("主体编号"),value:actor) }
                            NativeChannelFlowFact(label:Text("原目标类型"),value:row.targetType)
                            if let target = row.targetID { NativeChannelFlowFact(label:Text("目标编号"),value:target) }
                            Text(row.createdAt)
                            if let reason = row.reason { Text(reason).fixedSize(horizontal: false, vertical: true) }
                            if let changes = row.changes { Text(changes).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                            else { Text("原变更快照不可用") }
                            if row.redacted { Text("部分信息已由原服务端隐藏") }
                        }
                    }
                    }
                    if flow.state == .ready,
                       (flow.source == .lifecycle ? flow.operations.isEmpty : flow.rows.isEmpty) {
                        NativeChannelFlowNotice(title:Text("暂无可显示的审计记录"),symbol:"doc.text.magnifyingglass")
                    }
                    if flow.state == .loading { ProgressView() }
                    if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("原权限或审计来源暂不可用，未保留旧快照。"),symbol:"lock.shield") }
                    Button("刷新原审计记录") { Task { await flow.refresh() } }
                    if flow.canLoadMore { Button("读取更早记录") { Task { await flow.more() } } }
                }
            } else {
                VStack {
                    Text(unavailable ? "当前原审计权限或来源不可用" : "正在核对原频道权限")
                    Button("重新读取原权限") { Task { await open() } }
                }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(flow?.source == .lifecycle ? "频道管理变更记录" : "频道审计记录")
        .task { await open() }
        .task {
            while !Task.isCancelled {
                if let flow, !flow.isCurrent { close(); unavailable = true }
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
        }
        .onDisappear { close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await open() } } else { close() }
        }
        .privacySensitive()
    }
    private func close() { generation += 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); unavailable = false; let run = generation
        do {
            let context = try await channels.currentChannelContext(channelID: channelID)
            guard run == generation, scenePhase == .active, !Task.isCancelled,
                  channels.contextIsCurrent(context), context.serverPermissionNames.contains("VIEW_AUDIT"),
                  let owner = makeFlow(context) else { if run == generation { unavailable = true }; return }
            await owner.activate()
            guard run == generation, scenePhase == .active, !Task.isCancelled else { owner.deactivate(); return }
            flow = owner; unavailable = !owner.isCurrent
        } catch { if run == generation { unavailable = true } }
    }
}
