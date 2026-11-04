import SwiftUI

@MainActor struct NativeChannelPersonalStateEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelPersonalStateFlow?
    @State private var flow: NativeChannelPersonalStateFlow?
    @State private var generation = 0
    @State private var retryConfirmation = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow,flow.isCurrent {
                Form {
                    Section("只影响本人目录与通知偏好") {
                        Text("置顶、隐藏不改变原频道权限，也不影响其他成员。隐藏后可返回目录，明确开启“显示本人隐藏的频道”进行恢复。")
                        Button("刷新原状态或原回执") { Task { await flow.refresh() } }
                        if let id=flow.originalRequestID { NativeChannelFlowReference(label:Text("请求编号"),value:id) }
                        if flow.state == .loading || flow.state == .submitting || flow.readingCurrent { ProgressView() }
                        if flow.state == .unknown { NativeChannelFlowNotice(title:Text("结果未知，已保留原请求；不会自动重新发送。"),symbol:"clock.arrow.circlepath") }
                        if flow.state == .unavailable { NativeChannelFlowNotice(title:Text("当前原来源或独立授权不可用。"),symbol:"lock.shield") }
                        if flow.state == .applied { Text("原请求已有明确回执。下方当前偏好来自独立读取，不以历史回执代替。") }
                        if flow.currentReadFailed { Text("当前偏好尚未读回；已确认的原请求结果不变。请刷新原状态，不会重新提交。") }
                        if flow.state == .appliedHidden { Text("原请求已处理，但当前不可查看结果。没有恢复或扩大访问权。") }
                        if flow.hasPending {
                            Button("只回读同一请求") { Task { await flow.refresh() } }.disabled(!flow.canRecover)
                            Button("确认后重试同一请求") { retryConfirmation=true }.disabled(!flow.canRetry)
                        }
                    }
                    if let value=flow.currentState {
                        Section("当前偏好") {
                            LabeledContent("本人置顶",value:value.pinned ? "是" : "否")
                            LabeledContent("本人隐藏",value:value.hidden ? "是" : "否")
                            LabeledContent("有效静音",value:value.muted ? "是" : "否")
                            LabeledContent("永久静音",value:value.permanentMuted ? "是" : "否")
                            if let until=value.mutedUntil { LabeledContent("原静音截止",value:until) }
                            Text("取消本频道静音不修改其他原通知偏好，最终有效静音可能仍开启。")
                        }
                        Section("修改一项偏好") {
                            Button(value.pinned ? "取消本人置顶" : "本人置顶") { flow.prepare(.pinned,value:!value.pinned) }
                            Button(value.hidden ? "在本人目录重新显示" : "从本人目录隐藏") { flow.prepare(.hidden,value:!value.hidden) }
                            Button("沿原通知服务永久静音本频道") { flow.prepare(.muted,value:true) }
                            Button("取消本频道的原静音") { flow.prepare(.muted,value:false) }
                        }.disabled(!flow.canPrepare)
                    }
                    if flow.state == .reviewing {
                        Section("明确确认") {
                            Text(flow.reviewedSummary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                            Button("确认提交这一项本人偏好") { Task { await flow.confirm() } }.nativeChannelFlowAction()
                            Button("取消未发送请求") { flow.cancelReview() }
                        }
                    }
                }
                .confirmationDialog("仅原回执明确 NOT_FOUND 后才重试相同请求编号和原单项字节。",isPresented:$retryConfirmation) {
                    Button("确认重试原请求") { Task { await flow.retryOriginal() } }
                    Button("取消",role:.cancel) {}
                }
            } else { VStack { Text("本人频道状态原来源不可用");Button("重新读取当前权限") { Task { await open() } } } }
        }
        .nativeChannelFlowPage()
        .navigationTitle("本人目录与静音")
        .task { await open() }
        .task { while !Task.isCancelled { if let flow,!flow.isCurrent { close() };do { try await Task.sleep(nanoseconds:500_000_000) } catch { return } } }
        .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await open() } } else { close() } }
        .onDisappear { close() }.privacySensitive()
    }
    private func close() { generation += 1;flow?.deactivate();flow=nil;retryConfirmation=false }
    private func open() async {
        close();let run=generation
        do {
            let captured=try await channels.currentChannelContext(channelID:channelID)
            guard run == generation,scenePhase == .active,!Task.isCancelled,channels.contextIsCurrent(captured),let owner=makeFlow(captured) else { return }
            await owner.activate();guard run == generation,scenePhase == .active,!Task.isCancelled else { owner.deactivate();return };flow=owner
        } catch { }
    }
}
