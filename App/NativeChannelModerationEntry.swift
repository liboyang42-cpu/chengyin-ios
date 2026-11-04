import SwiftUI

@MainActor struct NativeChannelModerationEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelModerationFlow?
    @State private var flow: NativeChannelModerationFlow?
    @State private var generation = 0
    @State private var unavailable = false
    @State private var target = ""
    @State private var reason = ""
    @State private var reasonCode = "NOISE"
    @State private var seconds = "600"
    @State private var deleteMessageSeconds = "0"
    @State private var operation: NativeChannelModerationFlow.Operation = .timeout
    @State private var retryConfirmation = false
    @State private var invalidDraft = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow, flow.isCurrent {
                Form {
                    Section {
                        Text("只提交当前原权限允许的请求。成员层级、真实资格与范围由原服务端判定；列表读取权限不授予处置权限。")
                        if let id=flow.originalRequestID { NativeChannelFlowReference(label:Text("请求编号"),value:id) }
                        if flow.hasPending {
                            Text("原请求结果尚待确认。不会创建新请求，也不会自动重发。")
                            Button("回读同一原请求") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                            Button("确认后重试原请求") { retryConfirmation = true }.disabled(!flow.canRetry)
                        }
                        if flow.state == .unknown { NativeChannelFlowNotice(title:Text("结果未知，保留原请求等待回读。"),symbol:"clock.arrow.circlepath") }
                        if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("原来源或权限暂不可用；没有把失败当成成功。"),symbol:"lock.shield") }
                        if flow.state == .loading || flow.state == .submitting { ProgressView() }
                        if let result = flow.result {
                            Text("原服务已记录：\(result.type) · \(result.id) · \(result.status)")
                            Text("页面结果不代表自动恢复成员、角色或已删除内容。")
                        }
                    }
                    if !flow.hasPending {
                        Section("处置操作") {
                            Picker("操作",selection:$operation) {
                                Text("本频道限时禁言").tag(NativeChannelModerationFlow.Operation.timeout)
                                Text("移出当前组织").tag(NativeChannelModerationFlow.Operation.kick)
                                Text("限时禁止加入").tag(NativeChannelModerationFlow.Operation.ban)
                            }
                            TextField("真实成员编号",text:$target).keyboardType(.numberPad)
                            if operation != .kick { TextField("时长（秒）",text:$seconds).keyboardType(.numberPad) }
                            if operation == .ban {
                                TextField("同时删除该成员历史消息的窗口（秒，0 表示不删）",text:$deleteMessageSeconds).keyboardType(.numberPad)
                                Text("仅原服务允许的 0 至 604800 秒窗口。删除后即使撤销封禁，也不会恢复这部分历史消息；请先核对目标成员。")
                                    .foregroundStyle(.red)
                            }
                            Picker("原处置理由",selection:$reasonCode) {
                                Text("频道噪音（NOISE）").tag("NOISE")
                                ForEach(NativeChannelReportReason.allCases) { reason in
                                    Text(reason.title).tag(reason.rawValue)
                                }
                            }
                            Text("理由只用于原请求分类，不代表处置已成立。仍需填写具体事实理由。")
                            TextField("具体理由（必填）",text:$reason,axis:.vertical).lineLimit(3...7)
                            Text("历史删除默认关闭；App 不提供永久封禁。移出和封禁针对当前组织，禁言只针对本频道。")
                            Button("核对处置请求") {
                                invalidDraft = !flow.prepare(operation,target:target,seconds:operation == .kick ? 0 : (Int(seconds) ?? -1),reasonCode:reasonCode,reason:reason,deleteMessageSeconds:operation == .ban ? (Int(deleteMessageSeconds) ?? -1) : 0)
                            }.nativeChannelFlowAction().disabled(!flow.canPrepare(operation))
                            if invalidDraft { NativeChannelFlowNotice(title:Text("请核对成员编号、时长与具体理由；尚未生成或发送请求。"),symbol:"exclamationmark.circle") }
                        }
                    }
                    if flow.state == .reviewing {
                        Section("提交前确认") {
                            Text(flow.reviewedSummary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                            Button("确认提交这个原请求",role:.destructive) { Task { await flow.confirm() } }.nativeChannelFlowAction()
                            Button("取消") { flow.cancelReview() }
                        }
                    }
                    Section("处置记录") {
                        Button("刷新原记录") { Task { await flow.refresh() } }
                        if flow.readingCurrent { ProgressView("正在独立读取当前原记录…") }
                        if flow.currentReadFailed { Text("当前处置记录尚未读回。已确认的原请求结果不变；请刷新，不会重新执行处置。") }
                        ForEach(flow.actions) { action in
                            VStack(alignment:.leading,spacing:Theme.Space.s3) {
                                Text("\(action.type) · \(action.status)").font(Theme.Font.sectionTitle)
                                NativeChannelFlowReference(label:Text("处置编号"),value:action.id)
                                Text("成员 \(action.target) · \(action.scopeType) \(action.scopeID)")
                                Text(action.reason)
                                if !action.expiresAt.isEmpty { Text("原到期时间：\(action.expiresAt)") }
                                if flow.canRevoke(action) {
                                    Button("核对撤销此原处置") { invalidDraft = !flow.prepareRevoke(action,reason:reason) }
                                    Text("使用上方填写的必填理由；只可撤销原服务允许的有效禁言或封禁。")
                                }
                            }
                        }
                        if flow.canReadMore { Button("读取更早处置") { Task { await flow.loadMore() } } }
                    }
                }
                .confirmationDialog("只重试屏幕上的同一原请求？",isPresented:$retryConfirmation,titleVisibility:.visible) {
                    Button("回读后重试原请求",role:.destructive) { Task { await flow.retryOriginal() } }
                    Button("取消",role:.cancel) { }
                } message: { Text("先回读原回执。只有原服务明确允许、当前原权限仍有效时，才提交原 key 与原内容。") }
            } else {
                VStack {
                    Text(unavailable ? "当前管理来源或原权限不可用" : "正在读取原频道权限")
                    Button("重新读取原权限") { Task { await open() } }
                }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle("频道处置管理")
        .task { await open() }
        .task {
            while !Task.isCancelled {
                if let flow, !flow.isCurrent { close(); unavailable = true }
                do { try await Task.sleep(nanoseconds:500_000_000) } catch { return }
            }
        }
        .onDisappear { close() }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await open() } } else { close() } }
        .privacySensitive()
    }
    private func close() { generation += 1; flow?.deactivate();flow = nil;target = "";reason = "";deleteMessageSeconds = "0";retryConfirmation = false;invalidDraft = false }
    private func open() async {
        close();unavailable = false;let run = generation
        do {
            let captured = try await channels.currentChannelContext(channelID:channelID)
            guard run == generation,scenePhase == .active,!Task.isCancelled,channels.contextIsCurrent(captured),
                  let owner = makeFlow(captured) else { if run == generation { unavailable = true };return }
            await owner.activate()
            guard run == generation,scenePhase == .active,!Task.isCancelled else { owner.deactivate();return }
            flow = owner;unavailable = !owner.isCurrent
        } catch { if run == generation { unavailable = true } }
    }
}
